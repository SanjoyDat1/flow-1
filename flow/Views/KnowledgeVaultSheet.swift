//
//  KnowledgeVaultSheet.swift
//  flow
//
//  Shows extracted entities from all captured transcripts, filtered by
//  a selected category (people, topics, tasks, etc.). Driven by SwiftData.
//

import SwiftData
import SwiftUI

struct KnowledgeVaultSheet: View {
    let folder: VaultFolder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Transcript.capturedAt, order: .reverse)
    private var transcripts: [Transcript]

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle(folder.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Filtered Items

    private var filteredItems: [VaultItem] {
        var items: [VaultItem] = []
        var seen = Set<String>()

        for transcript in transcripts {
            guard let payload = transcript.payload else { continue }
            let source = payload.title
            let time = transcript.capturedAt

            switch folder {
            case .people:
                for person in payload.people {
                    let key = person.name.lowercased()
                    if seen.insert(key).inserted {
                        let detail = [person.email, person.notes].compactMap { $0 }.joined(separator: " · ")
                        items.append(VaultItem(label: person.name, detail: detail.isEmpty ? nil : detail, source: source, date: time))
                    }
                }
            case .topics:
                for topic in payload.topicSummary {
                    let key = topic.lowercased()
                    if seen.insert(key).inserted {
                        items.append(VaultItem(label: topic, source: source, date: time))
                    }
                }
            case .tasks:
                for fact in payload.facts where fact.predicate.lowercased().contains("need") || fact.predicate.lowercased().contains("should") || fact.predicate.lowercased().contains("will") || fact.object.lowercased().contains("action") {
                    let key = fact.displayText.lowercased()
                    if seen.insert(key).inserted {
                        items.append(VaultItem(label: fact.displayText, detail: fact.confidenceLabel, source: source, date: time))
                    }
                }
            case .decisions:
                for fact in payload.facts where fact.predicate.lowercased().contains("decided") || fact.predicate.lowercased().contains("is shipping") || fact.predicate.lowercased().contains("agreed") || fact.object.lowercased().contains("before") {
                    let key = fact.displayText.lowercased()
                    if seen.insert(key).inserted {
                        items.append(VaultItem(label: fact.displayText, detail: fact.confidenceLabel, source: source, date: time))
                    }
                }
            case .features:
                for topic in payload.topicSummary where topic.lowercased().contains("sync") || topic.lowercased().contains("ble") || topic.lowercased().contains("integration") || topic.lowercased().contains("api") {
                    let key = topic.lowercased()
                    if seen.insert(key).inserted {
                        items.append(VaultItem(label: topic, source: source, date: time))
                    }
                }
                for fact in payload.facts where fact.object.lowercased().contains("feature") || fact.predicate.lowercased().contains("ship") || fact.predicate.lowercased().contains("build") {
                    let key = fact.displayText.lowercased()
                    if seen.insert(key).inserted {
                        items.append(VaultItem(label: fact.displayText, detail: fact.confidenceLabel, source: source, date: time))
                    }
                }
            case .clients:
                for person in payload.people {
                    let key = person.name.lowercased()
                    if seen.insert(key).inserted {
                        let detail = person.email ?? person.notes
                        items.append(VaultItem(label: person.name, detail: detail, source: source, date: time))
                    }
                }
            }
        }
        return items
    }

    // MARK: - List

    private var itemList: some View {
        List {
            ForEach(filteredItems) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.royalBlue.opacity(0.8))
                    }
                    HStack(spacing: 4) {
                        Text(item.source)
                            .lineLimit(1)
                        Text("·")
                        Text(item.relativeTime)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: folder.icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.textSecondary.opacity(0.35))
            Text("No \(folder.title) Yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text("Penlo will extract \(folder.title.lowercased()) from your conversations automatically.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Vault Item

private struct VaultItem: Identifiable {
    let id = UUID()
    let label: String
    var detail: String? = nil
    let source: String
    let date: Date

    var relativeTime: String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
