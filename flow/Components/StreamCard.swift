//
//  StreamCard.swift
//  flow
//
//  A single conversation segment in the Intelligence Stream.
//  Default state is deliberately minimal — compact title, relative
//  timestamp, and a row of borderless entity tokens. Tapping the card
//  either expands it inline or presents a detail sheet (progressive
//  disclosure) so users are never overwhelmed.
//

import SwiftUI

struct StreamCard: View {
    let event: SyncEvent

    /// Controls whether this card should expand inline (true) or pop a
    /// bottom sheet (false). Inline expansion is used for the primary
    /// timeline; the sheet path is available for deeper flows.
    var inlineExpansion: Bool = true

    @State private var isExpanded = false
    @State private var showDetailSheet = false

    var body: some View {
        Button {
            Haptics.light()
            if inlineExpansion {
                withAnimation(.snappy(duration: 0.3)) { isExpanded.toggle() }
            } else {
                showDetailSheet = true
            }
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetailSheet) {
            StreamDetailSheet(event: event)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Compact summary + relative time.
            HStack(alignment: .top) {
                Text(event.summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 10)

                Text(event.relativeTimeLabel)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .layoutPriority(1)
            }

            // Horizontal row of borderless entity tokens.
            FlowLayout {
                ForEach(event.nodes) { node in
                    NodeChip(node: node)
                }
            }

            // Progressive disclosure: expanded detail.
            if isExpanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    // MARK: Expanded Detail

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().overlay(Color.textSecondary.opacity(0.15))

            if !event.nodes.filter({ $0.kind == .person }).isEmpty {
                detailSection(title: "People", items: event.nodes.filter { $0.kind == .person })
            }
            if !event.nodes.filter({ $0.kind == .feature }).isEmpty {
                detailSection(title: "Features", items: event.nodes.filter { $0.kind == .feature })
            }
            if !event.nodes.filter({ $0.kind == .decision }).isEmpty {
                detailSection(title: "Decisions", items: event.nodes.filter { $0.kind == .decision })
            }
            if !event.nodes.filter({ $0.kind == .question }).isEmpty {
                detailSection(title: "Open Questions", items: event.nodes.filter { $0.kind == .question })
            }

            Text(event.timeLabel)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func detailSection(title: String, items: [ExtractedNode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            ForEach(items) { item in
                Text(item.label)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Metrics.cardSpacing) {
            StreamCard(event: SyncEvent.samples[0])
            StreamCard(event: SyncEvent.samples[1])
        }
        .padding(Metrics.screenPadding)
    }
    .background(Color.canvas)
}
