//
//  SyncEventCard.swift
//  flow
//
//  Legacy card kept for backward compatibility. New timeline uses
//  StreamCard with progressive disclosure. This simple card is still
//  used in any context that needs a flat, non-interactive display.
//

import SwiftUI

struct SyncEventCard: View {
    let event: SyncEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.relativeTimeLabel)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

            Text(event.summary)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout {
                ForEach(event.nodes) { node in
                    NodeChip(node: node)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SyncEventCard(event: SyncEvent.samples[0])
        .padding()
        .background(Color.canvas)
}
