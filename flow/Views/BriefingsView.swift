//
//  BriefingsView.swift
//  flow
//
//  Pre-meeting intelligent briefing — a beautifully typeset contextual
//  layer designed to look like a clean document template. Uses spacious
//  layout cushions (whitespace) rather than lines or frames.
//

import SwiftUI

struct BriefingsView: View {
    let briefing: Briefing

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 40) {
                    header
                    section(
                        title: "People to Know",
                        icon: "person.fill",
                        items: briefing.peopleContext
                    )
                    section(
                        title: "Historical Decisions",
                        icon: "checkmark.circle",
                        items: briefing.relevantDecisions
                    )
                    section(
                        title: "Open Questions",
                        icon: "questionmark.circle",
                        items: briefing.openQuestions
                    )
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 36)
                .padding(.bottom, 52)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { Haptics.success() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming Briefing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.royalBlue)
                .textCase(.uppercase)
                .tracking(1.2)

            Text(briefing.countdownLabel)
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(Color.textPrimary)

            Text(briefing.meetingTitle)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: Section

    private func section(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.royalBlue)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    BriefingsView(briefing: .sample)
}
