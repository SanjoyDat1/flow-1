//
//  StreamDetailSheet.swift
//  flow
//
//  Full progressive-disclosure sheet for a single conversation segment.
//  Renders the complete Pydantic Contract v1.1 object details — Facts,
//  People, Topics — on a clean, typeset surface. Presented when inline
//  expansion isn't used or when the user wants the full deep-dive.
//

import SwiftUI

struct StreamDetailSheet: View {
    let event: SyncEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    // Full summary.
                    Text(event.summary)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Timestamp.
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(event.timeLabel)
                            .font(.caption)
                    }
                    .foregroundStyle(Color.textSecondary)

                    // Grouped entities.
                    ForEach(groupedSections, id: \.title) { section in
                        entitySection(section)
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 24)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.canvas)
            .navigationTitle("Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.royalBlue)
                }
            }
        }
        .onAppear { Haptics.light() }
    }

    // MARK: Sections

    private struct SectionData: Hashable {
        let title: String
        let icon: String
        let items: [ExtractedNode]
    }

    private var groupedSections: [SectionData] {
        let groups: [(ExtractedNode.Kind, String, String)] = [
            (.person,   "People",         "person.fill"),
            (.feature,  "Features",       "sparkles"),
            (.decision, "Decisions",      "checkmark.circle"),
            (.question, "Open Questions", "questionmark.circle")
        ]
        return groups.compactMap { kind, title, icon in
            let items = event.nodes.filter { $0.kind == kind }
            return items.isEmpty ? nil : SectionData(title: title, icon: icon, items: items)
        }
    }

    private func entitySection(_ section: SectionData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.royalBlue)
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.items) { item in
                    Text(item.label)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary.opacity(0.85))
                }
            }
        }
    }
}

#Preview {
    StreamDetailSheet(event: SyncEvent.samples[0])
}
