//
//  SyncEvent.swift
//  flow
//
//  A single conversation / extraction event captured by the wearable.
//  These populate the Intelligence Feed on the Home View.
//

import Foundation

/// One captured-and-extracted moment in the feed.
struct SyncEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let summary: String
    let nodes: [ExtractedNode]

    /// Relative timestamp ("12m ago", "2h ago") for the stream card.
    var relativeTimeLabel: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// Absolute timestamp for detail sheets.
    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Sample Data

extension SyncEvent {
    /// Demo feed so the UI renders meaningful content immediately.
    static let samples: [SyncEvent] = [
        SyncEvent(
            timestamp: Date().addingTimeInterval(-1_800),
            summary: "Reviewed the Q3 roadmap and aligned on shipping Enterprise Sync before the offsite.",
            nodes: [
                ExtractedNode(kind: .feature, label: "Enterprise Sync"),
                ExtractedNode(kind: .person, label: "Nolan Carroll"),
                ExtractedNode(kind: .decision, label: "Ship before offsite")
            ]
        ),
        SyncEvent(
            timestamp: Date().addingTimeInterval(-7_200),
            summary: "Standup: blockers on the BLE pairing flow, follow up with hardware team this week.",
            nodes: [
                ExtractedNode(kind: .question, label: "BLE pairing reliability"),
                ExtractedNode(kind: .person, label: "Hardware Team")
            ]
        ),
        SyncEvent(
            timestamp: Date().addingTimeInterval(-12_600),
            summary: "Coffee chat about the Enterprise Brain ingestion limits and how to batch transcripts.",
            nodes: [
                ExtractedNode(kind: .feature, label: "Batch Ingestion"),
                ExtractedNode(kind: .decision, label: "Wi-Fi only by default")
            ]
        )
    ]
}
