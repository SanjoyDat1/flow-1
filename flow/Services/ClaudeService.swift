//
//  ClaudeService.swift
//  flow
//
//  Pure URLSession client for the Anthropic Messages API.
//  Reads the API key from KeychainStore on each request.
//
//  Provides two capabilities:
//  1. Chat — multi-turn conversation with context injection
//  2. Extraction — processes raw transcript text into structured MemoryPayload
//

import Foundation

// nonisolated(unsafe) is required because SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
// would otherwise bind these immutable constants to the main actor, preventing
// access from nonisolated async networking functions.
private nonisolated(unsafe) let kClaudeEndpoint    = URL(string: "https://api.anthropic.com/v1/messages")!
private nonisolated(unsafe) let kClaudeAPIVersion  = "2023-06-01"
private nonisolated(unsafe) let kChatModel         = "claude-sonnet-4-6"
private nonisolated(unsafe) let kExtractionModel   = "claude-haiku-4-5-20251001"
private nonisolated(unsafe) let kChatMaxTokens     = 2048
private nonisolated(unsafe) let kExtractionMaxTokens = 2048

private nonisolated(unsafe) let kChatSystemPrompt = """
    You are Penlo, an intelligent AI assistant for a wearable companion that passively \
    captures the user's conversations throughout the day and helps them stay organized \
    and informed.

    CONTEXT: The user wears a Penlo device (or uses their phone mic) that records and \
    transcribes meetings, calls, and conversations. Summaries of recently captured \
    conversations may be provided below as context — use them to give informed, \
    specific answers grounded in real data.

    FORMATTING RULES (Critical — your output is rendered with rich text):
    - Use **bold** for key names, decisions, and important terms
    - Use bullet points (- ) for lists of 2+ items
    - Use numbered lists (1. ) for sequential steps or ranked items
    - Use short paragraph breaks between distinct ideas
    - Keep responses well-structured but not overly long — aim for clarity over brevity
    - For summaries: use a brief intro sentence, then structured bullets
    - For action items: use numbered lists
    - For factual answers: lead with the answer, then context

    SOURCE ATTRIBUTION (Critical — when you reference captured conversations):
    - When your response draws on specific captured conversation context, end with a \
    source line on its own line starting with "📎 Based on:" followed by the source \
    conversation titles/times you referenced (e.g., "📎 Based on: Morning standup, 1:1 with Sarah")
    - Only include source attribution when you actually used conversation context
    - Do NOT include source attribution for general knowledge answers

    ENTITY TAGGING: When your response mentions specific entities, tag them inline:
    - [person:Full Name]
    - [feature:Feature Name]
    - [decision:Decision text]
    - [question:Open question text]

    Only tag entities that are genuinely relevant. Do not over-tag. The tags will be \
    parsed and displayed as chips in the UI, so keep the label concise (2-4 words max).

    PERSONALITY: Be direct, knowledgeable, and slightly warm. You have access to the \
    user's actual conversations — use that to be specific and actionable. Never give \
    generic advice when you have real context. If you don't have context, say so briefly.
    """

private nonisolated(unsafe) let kExtractionSystemPrompt = """
    You are the central Extraction Engine for "Penlo," an Enterprise AI Brain. Your sole \
    function is to process raw, messy, multi-speaker audio transcripts, strip out all \
    conversational filler, and extract high-signal, structured intelligence.

    You will output ONLY a valid JSON object. Do not include markdown code blocks, \
    conversational text, preambles, or explanations.

    # NON-NEGOTIABLE EXTRACTION RULES:

    1. TITLE: A short descriptive title for this conversation (max 6 words).

    2. THE FACT TRIPLES (Subject, Predicate, Object):
    - Subjects: MUST be proper nouns or well-formed noun phrases (e.g., "Sarah Chen", \
      "Acme Corp", "API rate limiter"). NEVER use pronouns ("he", "they", "it") or vague \
      references ("someone", "the team"). If a pronoun cannot be confidently resolved to a \
      specific name in the context, skip the fact entirely.
    - Predicates: MUST be short verb phrases in the present tense (e.g., "is working on", \
      "decided", "owns", "mentioned", "blocked by"). Do not use complex past-tense narratives.
    - Objects: Keep them concise and specific.

    3. CONFIDENCE SCORING (0.60 to 0.85):
    - Because you are processing an AI-generated transcript, your confidence score for any \
      fact MUST strictly fall between 0.60 and 0.85.
    - NEVER use 1.0.
    - Use 0.80-0.85 for clearly stated, unambiguous facts.
    - Use 0.60-0.70 for implied facts, or facts where the exact wording was messy.

    4. UNKNOWN SPEAKERS & DIARIZATION:
    - If a speaker states a fact but their identity is unknown, the subject MUST be \
      "Unknown Speaker [Number]".
    - Drop the confidence score for "Unknown Speaker" facts closer to 0.60.

    5. THE 11 ONTOLOGY NODE TYPES:
    Any extracted entity or concept must conceptually map to one of these 11 types: \
    person, topic, task, decision, feature, client, event, draft, team, company, agent. \
    When generating the "topicSummary" array, ensure the strings align with these categories.

    6. PEOPLE EXTRACTION:
    - Extract all specific humans mentioned or speaking.
    - If an email or phone number is mentioned, include it. Otherwise, return null.
    - Keep notes extremely brief (under 10 words).

    # REQUIRED JSON SCHEMA:
    {
      "title": "<Short title, max 6 words>",
      "facts": [
        {"subject": "<Proper Noun>", "predicate": "<Short present-tense verb phrase>", \
    "object": "<Concise detail>", "confidence": <Float 0.60-0.85>}
      ],
      "people": [
        {"name": "<String>", "email": "<String or null>", "phone": "<String or null>", \
    "notes": "<String or null>"}
      ],
      "topicSummary": ["<String>"]
    }

    Rules:
    - Return between 2-8 facts, 0-5 people, 1-4 topic summaries.
    - If a field has no content, use an empty array [].
    """

struct ClaudeService: Sendable {

    static let shared = ClaudeService()

    // Expose model names for external use (e.g. AudioEngineManager).
    static var chatModel: String         { kChatModel }
    static var extractionModel: String   { kExtractionModel }

    // MARK: - Types

    struct Turn: Sendable {
        let role: String
        let content: String
    }

    struct Response: Sendable {
        let text: String
        let nodes: [ExtractedNode]
    }

    enum ServiceError: LocalizedError, Sendable {
        case missingAPIKey
        case invalidResponse
        case apiError(status: Int, message: String)
        case networkError(String)
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No Claude API key found. Add your key in Settings."
            case .invalidResponse:
                return "Received an unexpected response from Claude."
            case .apiError(let status, let message):
                if status == 401 {
                    return "Invalid API key. Check your key in Settings."
                }
                if status == 429 {
                    return "Rate limit reached. Try again in a moment."
                }
                return "Claude API error (\(status)): \(message)"
            case .networkError(let desc):
                return "Network error: \(desc)"
            case .extractionFailed:
                return "Failed to extract intelligence from transcript."
            }
        }

        var userFacingMessage: String {
            errorDescription ?? "Something went wrong. Please try again."
        }
    }

    // MARK: - Public API: Chat

    /// Returns true if an API key is configured.
    nonisolated static var hasAPIKey: Bool {
        guard let key = KeychainStore.readAPIKey() else { return false }
        return !key.isEmpty
    }

    /// Send a multi-turn chat message with optional transcript context.
    /// Marked nonisolated so the network call runs off the main actor.
    nonisolated func send(messages: [Turn], transcriptContext: String? = nil) async throws -> Response {
        guard let apiKey = KeychainStore.readAPIKey(), !apiKey.isEmpty else {
            throw ServiceError.missingAPIKey
        }

        var systemPrompt = kChatSystemPrompt
        if let context = transcriptContext, !context.isEmpty {
            systemPrompt += "\n\nRECENT CAPTURED CONVERSATIONS:\n\(context)"
        }

        return try await performRequest(
            apiKey: apiKey,
            model: kChatModel,
            systemPrompt: systemPrompt,
            messages: messages,
            maxTokens: kChatMaxTokens
        )
    }

    /// Lightweight ping to validate an API key. Uses minimal tokens.
    nonisolated func verify(apiKey: String) async throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServiceError.missingAPIKey
        }
        _ = try await performRequest(
            apiKey: trimmed,
            model: kExtractionModel,
            systemPrompt: "Reply with exactly: OK",
            messages: [Turn(role: "user", content: "ping")],
            maxTokens: 8
        )
    }

    // MARK: - Public API: Briefing Generation

    /// Generates a pre-meeting briefing by analyzing transcript context against an upcoming meeting.
    nonisolated func generateBriefing(
        meetingTitle: String,
        minutesUntil: Int,
        transcriptContext: String
    ) async throws -> Briefing {
        guard let apiKey = KeychainStore.readAPIKey(), !apiKey.isEmpty else {
            throw ServiceError.missingAPIKey
        }

        let briefingPrompt = """
        You are generating a pre-meeting intelligence briefing. Given the meeting title and \
        recent conversation context, produce a JSON briefing. Return ONLY valid JSON:

        {
          "peopleContext": ["Person Name — role/relevance to this meeting"],
          "relevantDecisions": ["Recent decisions relevant to this meeting"],
          "openQuestions": ["Unresolved questions that may come up"]
        }

        Rules:
        - peopleContext: people who are likely attendees or relevant, with brief context
        - relevantDecisions: concrete decisions from recent conversations relevant to this meeting
        - openQuestions: questions that remain unresolved and might be discussed
        - If no relevant context exists for a field, use an empty array []
        - Keep each array to 2-5 items max
        """

        let userMessage = """
        Meeting: \(meetingTitle)
        Time: in \(minutesUntil) minutes

        Recent conversation context:
        \(transcriptContext)
        """

        let result = try await performRequest(
            apiKey: apiKey,
            model: kExtractionModel,
            systemPrompt: briefingPrompt,
            messages: [Turn(role: "user", content: userMessage)],
            maxTokens: kExtractionMaxTokens
        )

        let jsonText = extractJSON(from: result.text)
        guard let data = jsonText.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Briefing(
                meetingTitle: meetingTitle,
                minutesUntil: minutesUntil,
                peopleContext: [],
                relevantDecisions: [],
                openQuestions: []
            )
        }

        return Briefing(
            meetingTitle: meetingTitle,
            minutesUntil: minutesUntil,
            peopleContext: (parsed["peopleContext"] as? [String]) ?? [],
            relevantDecisions: (parsed["relevantDecisions"] as? [String]) ?? [],
            openQuestions: (parsed["openQuestions"] as? [String]) ?? []
        )
    }

    // MARK: - Public API: Transcript Extraction

    /// Processes raw transcript text through Claude using the Penlo Contract v1.1
    /// extraction prompt. Returns a fully-structured MemoryPayload with SPO fact
    /// triples, structured people, and ontology-aligned topic summaries.
    nonisolated func extractPayload(from rawText: String, capturedAt: Date = .now) async throws -> MemoryPayload {
        guard let apiKey = KeychainStore.readAPIKey(), !apiKey.isEmpty else {
            throw ServiceError.missingAPIKey
        }

        let userContent = "Extract structured intelligence from the following transcript. Return ONLY the JSON object.\n\n# TRANSCRIPT:\n\(rawText)"

        let result = try await performRequest(
            apiKey: apiKey,
            model: kExtractionModel,
            systemPrompt: kExtractionSystemPrompt,
            messages: [Turn(role: "user", content: userContent)],
            maxTokens: kExtractionMaxTokens
        )

        let jsonText = extractJSON(from: result.text)
        guard let data = jsonText.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.extractionFailed
        }

        return assemblePayload(from: raw, capturedAt: capturedAt)
    }

    /// Assembles a MemoryPayload from a raw JSON dictionary, mirroring
    /// the Python pipeline's assemble_payload() function.
    private nonisolated func assemblePayload(from raw: [String: Any], capturedAt: Date) -> MemoryPayload {
        let capturedAtISO = PenloTimestamp.from(capturedAt)
        let title = (raw["title"] as? String) ?? "Untitled Conversation"

        let rawFacts = (raw["facts"] as? [[String: Any]]) ?? []
        let facts: [PenloFact] = rawFacts.compactMap { dict in
            guard let subject = dict["subject"] as? String,
                  let predicate = dict["predicate"] as? String,
                  let object = dict["object"] as? String else { return nil }
            let confidence = (dict["confidence"] as? NSNumber)?.floatValue ?? 0.70
            return PenloFact(
                subject: subject,
                predicate: predicate,
                object: object,
                confidence: confidence,
                capturedAt: capturedAtISO
            )
        }

        let rawPeople = (raw["people"] as? [[String: Any]]) ?? []
        let people: [PenloPerson] = rawPeople.compactMap { dict in
            guard let name = dict["name"] as? String, !name.isEmpty else { return nil }
            return PenloPerson(
                name: name,
                email: dict["email"] as? String,
                phone: dict["phone"] as? String,
                notes: dict["notes"] as? String
            )
        }

        let topicSummary = (raw["topicSummary"] as? [String]) ?? []

        return MemoryPayload(
            title: title,
            facts: facts,
            people: people,
            topicSummary: topicSummary,
            capturedAt: capturedAt
        )
    }

    // MARK: - Request

    private nonisolated func performRequest(
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [Turn],
        maxTokens: Int
    ) async throws -> Response {
        var request = URLRequest(url: kClaudeEndpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(kClaudeAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ServiceError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let message = parseErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw ServiceError.apiError(status: http.statusCode, message: message)
        }

        guard let rawText = parseTextContent(from: data) else {
            throw ServiceError.invalidResponse
        }

        let parsed = Self.parseEntities(from: rawText)
        return Response(text: parsed.text, nodes: parsed.nodes)
    }

    // MARK: - Response Parsing

    private nonisolated func parseTextContent(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            return nil
        }
        return content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
    }

    private nonisolated func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
            return msg
        }
        return json["message"] as? String
    }

    /// Attempts to extract JSON from a response that may contain markdown fences.
    private nonisolated func extractJSON(from text: String) -> String {
        if let start = text.range(of: "{"),
           let end = text.range(of: "}", options: .backwards) {
            return String(text[start.lowerBound...end.upperBound])
        }
        return text
    }

    // MARK: - Entity Tag Parsing

    nonisolated static func parseEntities(from raw: String) -> (text: String, nodes: [ExtractedNode]) {
        let pattern = #"\[(person|feature|decision|question):([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (raw, [])
        }

        let nsRange = NSRange(raw.startIndex..., in: raw)
        var nodes: [ExtractedNode] = []
        var seen = Set<String>()

        regex.enumerateMatches(in: raw, options: [], range: nsRange) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 3,
                  let kindRange = Range(match.range(at: 1), in: raw),
                  let labelRange = Range(match.range(at: 2), in: raw) else { return }

            let kindStr = String(raw[kindRange])
            let label = String(raw[labelRange]).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { return }

            let kind: ExtractedNode.Kind
            switch kindStr {
            case "person": kind = .person
            case "feature": kind = .feature
            case "decision": kind = .decision
            case "question": kind = .question
            default: return
            }

            let dedupeKey = "\(kindStr):\(label.lowercased())"
            guard seen.insert(dedupeKey).inserted else { return }
            nodes.append(ExtractedNode(kind: kind, label: label))
        }

        let cleaned = regex.stringByReplacingMatches(
            in: raw,
            options: [],
            range: nsRange,
            withTemplate: ""
        )
        let text = cleaned
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (text, nodes)
    }
}
