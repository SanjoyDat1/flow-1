//
//  QuickActionCard.swift
//  flow
//
//  A minimalist tappable card shown at the bottom of the empty-state
//  canvas. Provides single-tap access to recent context summaries,
//  outstanding tasks, or the upcoming briefing.
//

import SwiftUI

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.royalBlue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary.opacity(0.5))
            }
            .padding(16)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 12) {
        QuickActionCard(
            title: "Recent Context",
            subtitle: "3 conversations captured today",
            icon: "text.bubble"
        ) {}
        QuickActionCard(
            title: "Outstanding Tasks",
            subtitle: "2 action items pending",
            icon: "checklist"
        ) {}
    }
    .padding(Metrics.screenPadding)
    .background(Color.canvas)
}
