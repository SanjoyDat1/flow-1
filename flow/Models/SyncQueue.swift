//
//  SyncQueue.swift
//  flow
//
//  SwiftData model + persistence infrastructure for reliable, offline-first
//  syncing. Each `SyncQueue` row is a payload that failed to reach the
//  Enterprise Brain and must be retried — this is the safety net that
//  guarantees no conversation data is ever lost when the network drops.
//

import Foundation
import SwiftData

// MARK: - Model

@Model
final class SyncQueue {
    /// Stable identity for this queued payload.
    @Attribute(.unique) var id: UUID

    /// The `Transcript.id` this payload represents (for de-duplication).
    var transcriptID: UUID

    /// The serialized body that failed to send.
    var payload: Data

    /// When the payload was first enqueued.
    var enqueuedAt: Date

    /// Number of delivery attempts so far (for backoff / give-up policy).
    var retryCount: Int

    /// Timestamp of the most recent delivery attempt, if any.
    var lastAttemptAt: Date?

    /// Last transport error message, for diagnostics.
    var lastError: String?

    init(
        id: UUID = UUID(),
        transcriptID: UUID,
        payload: Data,
        enqueuedAt: Date = .now,
        retryCount: Int = 0,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.transcriptID = transcriptID
        self.payload = payload
        self.enqueuedAt = enqueuedAt
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }
}

// MARK: - Shared Container

/// Centralized SwiftData configuration so every layer (UI, view models,
/// background actors) talks to the same store.
enum PenloStore {
    /// The full schema for the app.
    static let schema = Schema([
        Transcript.self,
        SyncQueue.self
    ])

    /// Builds a `ModelContainer`. `inMemory` is useful for previews/tests.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Penlo ModelContainer: \(error)")
        }
    }

    // MARK: - Demo Seeding

    /// Populates SwiftData with realistic demo transcripts so the Privacy
    /// Staging Vault has content on first launch. Idempotent via UserDefaults flag.
    @MainActor
    static func seedDemoTranscripts(in context: ModelContext) {
        let key = "penlo.vault.demo-seeded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let encoder = JSONEncoder()

        let samples: [(raw: String, payload: MemoryPayload, offset: TimeInterval)] = [
            (
                "Reviewed the Q3 roadmap and aligned on shipping Enterprise Sync before the offsite.",
                MemoryPayload(
                    title: "Standup with Nolan",
                    facts: [
                        PenloFact(subject: "Enterprise Sync", predicate: "is shipping", object: "before offsite", confidence: 0.82, capturedAt: ""),
                        PenloFact(subject: "BLE pairing", predicate: "has", object: "reliability issues on v2.1 firmware", confidence: 0.78, capturedAt: ""),
                        PenloFact(subject: "Battery drain", predicate: "reported on", object: "extended recording sessions", confidence: 0.72, capturedAt: ""),
                        PenloFact(subject: "Target date", predicate: "is", object: "July 15th", confidence: 0.80, capturedAt: "")
                    ],
                    people: [PenloPerson(name: "Nolan Carroll"), PenloPerson(name: "Marcus Lee")],
                    topicSummary: ["Q3 Roadmap", "BLE Reliability"]
                ),
                -1_800
            ),
            (
                "Discussed ingestion limits and how to batch transcripts for the Enterprise Brain.",
                MemoryPayload(
                    title: "Coffee Chat: Ingestion Limits",
                    facts: [
                        PenloFact(subject: "Transcript batching", predicate: "is needed for", object: "ingestion limits", confidence: 0.80, capturedAt: ""),
                        PenloFact(subject: "Wi-Fi only sync", predicate: "preserves", object: "40% battery life", confidence: 0.75, capturedAt: ""),
                        PenloFact(subject: "Current ceiling", predicate: "is", object: "500 events per hour", confidence: 0.83, capturedAt: "")
                    ],
                    people: [PenloPerson(name: "Priya Anand", email: nil, phone: nil, notes: "Backend lead")],
                    topicSummary: ["Batch Ingestion", "Battery Optimization"]
                ),
                -7_200
            ),
            (
                "Enterprise client call about SSO requirements and EU data residency.",
                MemoryPayload(
                    title: "Enterprise Client Call",
                    facts: [
                        PenloFact(subject: "Client", predicate: "needs", object: "SSO before Q4", confidence: 0.84, capturedAt: ""),
                        PenloFact(subject: "Data residency in EU", predicate: "is", object: "a hard blocker", confidence: 0.82, capturedAt: ""),
                        PenloFact(subject: "Trial renewal", predicate: "is in", object: "3 weeks", confidence: 0.78, capturedAt: ""),
                        PenloFact(subject: "Competitor demo", predicate: "scheduled for", object: "next Tuesday", confidence: 0.76, capturedAt: "")
                    ],
                    people: [
                        PenloPerson(name: "Marcus Lee", notes: "Account exec"),
                        PenloPerson(name: "Sarah Chen", email: "sarah.chen@globex.com"),
                        PenloPerson(name: "David Park")
                    ],
                    topicSummary: ["Enterprise Sales", "SSO Integration", "EU Compliance"]
                ),
                -18_000
            )
        ]

        for sample in samples {
            let data = try? encoder.encode(sample.payload)
            let transcript = Transcript(
                rawText: sample.raw,
                capturedAt: Date.now.addingTimeInterval(sample.offset),
                isSynced: false,
                payloadData: data
            )
            context.insert(transcript)
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}

// MARK: - Thread-Safe Persistence Actor

/// All writes go through this actor so SwiftData mutations happen off the
/// main thread and never block the UI. Backed by its own `ModelContext`
/// derived from the shared container (`@ModelActor` synthesizes the
/// `init(modelContainer:)` and the isolated `modelContext`).
@ModelActor
actor PersistenceActor {

    /// Persist a freshly captured transcript.
    @discardableResult
    func insertTranscript(rawText: String, capturedAt: Date = .now, payloadData: Data? = nil) throws -> UUID {
        let transcript = Transcript(rawText: rawText, capturedAt: capturedAt, payloadData: payloadData)
        modelContext.insert(transcript)
        try modelContext.save()
        return transcript.id
    }

    /// Enqueue a payload that failed to send so it can be retried later.
    func enqueueFailedPayload(transcriptID: UUID, payload: Data, error: String?) throws {
        let item = SyncQueue(
            transcriptID: transcriptID,
            payload: payload,
            lastError: error
        )
        modelContext.insert(item)
        try modelContext.save()
    }

    /// Mark a transcript as synced and drop its queued payloads (if any).
    func markSynced(transcriptID: UUID) throws {
        let transcriptDescriptor = FetchDescriptor<Transcript>(
            predicate: #Predicate { $0.id == transcriptID }
        )
        for transcript in try modelContext.fetch(transcriptDescriptor) {
            transcript.isSynced = true
        }

        let queueDescriptor = FetchDescriptor<SyncQueue>(
            predicate: #Predicate { $0.transcriptID == transcriptID }
        )
        for queued in try modelContext.fetch(queueDescriptor) {
            modelContext.delete(queued)
        }

        try modelContext.save()
    }

    /// Record a failed retry attempt against an existing queue item.
    func recordRetryFailure(queueItemID: UUID, error: String?) throws {
        let descriptor = FetchDescriptor<SyncQueue>(
            predicate: #Predicate { $0.id == queueItemID }
        )
        guard let item = try modelContext.fetch(descriptor).first else { return }
        item.retryCount += 1
        item.lastAttemptAt = .now
        item.lastError = error
        try modelContext.save()
    }

    /// Permanently delete a queue item (for non-retryable errors like 400/422).
    func deleteQueueItem(id: UUID) throws {
        let descriptor = FetchDescriptor<SyncQueue>(
            predicate: #Predicate { $0.id == id }
        )
        for item in try modelContext.fetch(descriptor) {
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    /// Attach a Claude-extracted MemoryPayload to an existing transcript.
    func attachPayload(transcriptID: UUID, payloadData: Data) throws {
        let descriptor = FetchDescriptor<Transcript>(
            predicate: #Predicate { $0.id == transcriptID }
        )
        guard let transcript = try modelContext.fetch(descriptor).first else { return }
        transcript.payloadData = payloadData
        try modelContext.save()
    }
}
