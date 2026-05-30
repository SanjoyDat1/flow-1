//
//  WearableStatusIsland.swift
//  flow
//
//  The floating status pill. Shows the hardware icon, battery %,
//  and a dynamic status dot. Tapping opens Hardware Management.
//

import SwiftUI

struct WearableStatusIsland: View {
    @ObservedObject var bluetooth: BluetoothManager
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: bluetooth.state.hardwareSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text("Penlo")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text("\(bluetooth.batteryLevel.map { "\($0)" } ?? "--")%")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                StatusDot(state: bluetooth.state)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.textPrimary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Penlo wearable. \(bluetooth.state.label). Battery \(bluetooth.batteryLevel.map { "\($0) percent" } ?? "unknown").")
    }
}

// MARK: - Status Dot

private struct StatusDot: View {
    let state: WearableState
    @State private var pulse = false

    var body: some View {
        Group {
            switch state {
            case .recording:
                ZStack {
                    Circle()
                        .fill(Color.royalBlue)
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(Color.royalBlue.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .blur(radius: 3)
                        .scaleEffect(pulse ? 1.8 : 1.0)
                        .opacity(pulse ? 0 : 0.8)
                }
                .onAppear {
                    withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        pulse = true
                    }
                }

            case .searching:
                Circle()
                    .fill(Color.royalBlue.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .opacity(pulse ? 0.3 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }

            case .connected:
                Circle()
                    .fill(Color.textPrimary)
                    .frame(width: 8, height: 8)

            case .disconnected:
                Circle()
                    .strokeBorder(Color.textSecondary, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.canvas.ignoresSafeArea()
        WearableStatusIsland(bluetooth: BluetoothManager()) {}
    }
}
