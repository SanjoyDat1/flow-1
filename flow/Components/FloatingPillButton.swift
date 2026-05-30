//
//  FloatingPillButton.swift
//  flow
//
//  A reusable floating action pill on `.ultraThinMaterial`.
//

import SwiftUI

struct FloatingPillButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.textPrimary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.canvas.ignoresSafeArea()
        FloatingPillButton(title: "Upcoming", systemImage: "calendar") {}
    }
}
