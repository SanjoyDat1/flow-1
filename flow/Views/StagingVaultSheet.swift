//
//  StagingVaultSheet.swift
//  flow
//
//  The Privacy Review screen. Captured conversations are held here
//  until the user explicitly approves them. Clear, intuitive UX that
//  explains what's happening and gives full control.
//

import SwiftData
import SwiftUI

struct StagingVaultSheet: View {
    var brainSyncer: EnterpriseBrainSyncer

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Transcript> { !$0.isSynced },
        sort: \Transcript.capturedAt,
        order: .reverse
    )
    private var blocks: [Transcript]

    @State private var expandedID: UUID?
    @State private var syncingAll = false
    @State private var syncingID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if blocks.isEmpty {
                    emptyState
                } else {
                    headerExplanation
                    blockList
                }
            }
            .background(Color.penloBlack.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Review Memories")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.penloWhite)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .toolbarBackground(Color.penloBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { purgeExpired() }
        .onChange(of: blocks.count) { old, new in
            if new == 0 && old > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header

    private var headerExplanation: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                    .foregroundStyle(Color.royalBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(blocks.count) captured \(blocks.count == 1 ? "conversation" : "conversations")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.penloWhite)
                    Text("Review what Penlo heard. Approve to keep, swipe to discard.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }

            if blocks.count > 1 {
                Button {
                    syncAllBlocks()
                } label: {
                    HStack(spacing: 8) {
                        if syncingAll {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.subheadline.weight(.semibold))
                            Text("Approve All \(blocks.count) Memories")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundStyle(Color.penloWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Color.royalBlue.opacity(syncingAll ? 0.5 : 1.0),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(syncingAll)
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.vertical, 16)
        .background(Color.penloBlack)
    }

    // MARK: - Block List

    private var blockList: some View {
        List {
            ForEach(blocks) { transcript in
                MemoryBlockCard(
                    transcript: transcript,
                    isExpanded: expandedID == transcript.id,
                    onToggle: { toggleExpansion(transcript.id) },
                    onSync: { syncBlock(transcript) },
                    onDiscard: { deleteBlock(transcript) },
                    onRemoveItem: { kind, index in
                        removeItem(from: transcript, kind: kind, at: index)
                    }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(
                        top: 8,
                        leading: Metrics.screenPadding,
                        bottom: 8,
                        trailing: Metrics.screenPadding
                    )
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteBlock(transcript)
                    } label: {
                        Label("Discard", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        syncBlock(transcript)
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .tint(.royalBlue)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.royalBlue.opacity(0.6))
            Text("All Caught Up")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.penloWhite)
            Text("No conversations waiting for review.\nNew captures will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func toggleExpansion(_ id: UUID) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            expandedID = expandedID == id ? nil : id
        }
    }

    private func deleteBlock(_ transcript: Transcript) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            modelContext.delete(transcript)
            try? modelContext.save()
            Haptics.medium()
        }
    }

    private func syncBlock(_ transcript: Transcript) {
        syncingID = transcript.id
        Task {
            if brainSyncer.isConfigured {
                await brainSyncer.enqueueAndSync(transcript: transcript)
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                transcript.isSynced = true
                try? modelContext.save()
                syncingID = nil
                Haptics.success()
            }
        }
    }

    private func syncAllBlocks() {
        syncingAll = true
        Task {
            for block in blocks {
                if brainSyncer.isConfigured {
                    await brainSyncer.enqueueAndSync(transcript: block)
                }
                block.isSynced = true
            }
            try? modelContext.save()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                syncingAll = false
                Haptics.success()
            }
        }
    }

    private func removeItem(from transcript: Transcript, kind: String, at index: Int) {
        guard var payload = transcript.payload else { return }

        switch kind {
        case "facts":  guard index < payload.facts.count else { return };  payload.facts.remove(at: index)
        case "people": guard index < payload.people.count else { return }; payload.people.remove(at: index)
        case "topics": guard index < payload.topicSummary.count else { return }; payload.topicSummary.remove(at: index)
        default: return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if payload.isEmpty {
                modelContext.delete(transcript)
            } else {
                transcript.payload = payload
            }
            try? modelContext.save()
            Haptics.light()
        }
    }

    // MARK: - 72h TTL Purge

    private func purgeExpired() {
        let cutoff = Date.now.addingTimeInterval(-72 * 60 * 60)
        let expired = blocks.filter { $0.capturedAt < cutoff }
        guard !expired.isEmpty else { return }
        for t in expired { modelContext.delete(t) }
        try? modelContext.save()
    }
}

#Preview {
    StagingVaultSheet(brainSyncer: EnterpriseBrainSyncer())
        .modelContainer(PenloStore.makeContainer(inMemory: true))
}
