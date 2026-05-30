//
//  PayloadValidator.swift
//  flow
//
//  Validates extracted MemoryPayload data against Penlo Contract v1.1 rules.
//  Mirrors the Python pipeline's Pydantic validation: confidence bounds,
//  pronoun rejection for fact subjects, and array size limits.
//
//  Rather than rejecting invalid payloads outright (which would lose data),
//  this validator clamps/filters to produce the best valid payload possible.
//

import Foundation

enum PayloadValidator {

    // MARK: - Configuration

    private static let confidenceMin: Float = 0.60
    private static let confidenceMax: Float = 0.85
    private static let maxFacts = 8
    private static let maxPeople = 10
    private static let maxTopics = 6

    private static let rejectedSubjectPronouns: Set<String> = [
        "he", "she", "they", "it", "we", "i", "you",
        "him", "her", "them", "us", "me",
        "someone", "somebody", "anyone", "everybody",
        "the team", "the group", "the company"
    ]

    // MARK: - Public

    /// Validates and sanitizes a MemoryPayload, clamping confidence scores,
    /// rejecting pronoun-based facts, and enforcing array size limits.
    /// Returns a cleaned payload that conforms to Penlo Contract v1.1.
    static func validate(_ payload: MemoryPayload) -> MemoryPayload {
        var result = payload

        // Filter facts: reject pronoun subjects, clamp confidence
        result.facts = payload.facts
            .filter { !isRejectedSubject($0.subject) }
            .prefix(maxFacts)
            .map { fact in
                var f = fact
                f.confidence = clampConfidence(f.confidence)
                f.subject = f.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                f.predicate = f.predicate.trimmingCharacters(in: .whitespacesAndNewlines)
                f.object = f.object.trimmingCharacters(in: .whitespacesAndNewlines)
                return f
            }

        // Filter people: remove empty names, deduplicate, cap
        var seenNames = Set<String>()
        result.people = payload.people
            .filter { person in
                let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return false }
                return seenNames.insert(name.lowercased()).inserted
            }
            .prefix(maxPeople)
            .map { person in
                var p = person
                p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return p
            }

        // Cap topics, deduplicate, trim
        var seenTopics = Set<String>()
        result.topicSummary = payload.topicSummary
            .compactMap { topic -> String? in
                let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                guard seenTopics.insert(trimmed.lowercased()).inserted else { return nil }
                return trimmed
            }
            .map { String($0) }
        if result.topicSummary.count > maxTopics {
            result.topicSummary = Array(result.topicSummary.prefix(maxTopics))
        }

        return result
    }

    /// Returns true if the payload has at least one meaningful extraction.
    static func isUsable(_ payload: MemoryPayload) -> Bool {
        !payload.facts.isEmpty || !payload.people.isEmpty || !payload.topicSummary.isEmpty
    }

    // MARK: - Private

    private static func isRejectedSubject(_ subject: String) -> Bool {
        let normalized = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rejectedSubjectPronouns.contains(normalized)
    }

    private static func clampConfidence(_ value: Float) -> Float {
        min(confidenceMax, max(confidenceMin, value))
    }
}
