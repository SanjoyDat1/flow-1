//
//  WearableStatusPill.swift
//  flow
//
//  Dynamic Island-style hardware pill that doubles as the entry
//  point to the Privacy Staging Vault. When unsynced local data
//  exists, the status dot morphs into a slow-pulsing Royal Blue
//  liquid-glass orb and a "N Pending" badge appears.
//

import SwiftUI

struct WearableStatusPill: View {
    @ObservedObject var bluetooth: BluetoothManager
    let unsyncedCount: Int
    var isPhoneListening: Bool = false
    let onTap: () -> Void

    private var hasPending: Bool { unsyncedCount > 0 }
    private var isActive: Bool { bluetooth.state.isLive || isPhoneListening }

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            HStack(spacing: 8) {
                if isPhoneListening {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.red)
                        .symbolEffect(.pulse, isActive: true)
                } else {
                    Image(systemName: isActive ? "waveform" : "bolt.horizontal.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }

                if isPhoneListening {
                    Text("Listening")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.red)
                } else if let battery = bluetooth.batteryLevel {
                    Text("\(battery)%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text(bluetooth.state.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }

                statusIndicator

                if hasPending {
                    Text("\(unsyncedCount) Pending")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.royalBlue)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isPhoneListening
                    ? AnyShapeStyle(Color.red.opacity(0.06))
                    : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isPhoneListening ? Color.red.opacity(0.3) : Color.textPrimary.opacity(0.06),
                    lineWidth: isPhoneListening ? 1 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.3), value: hasPending)
        .animation(.snappy(duration: 0.3), value: isPhoneListening)
        .accessibilityLabel(
            isPhoneListening
                ? "Phone listening. \(unsyncedCount) pending."
                : "Penlo. \(bluetooth.state.label). \(bluetooth.batteryLevel.map { "\($0) percent" } ?? "no battery info"). \(unsyncedCount) pending."
        )
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if hasPending {
            VaultPulse()
        } else {
            Circle()
                .fill(Color.penloWhite)
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Vault Pulse

/// Slow-pulsing Royal Blue liquid-glass dot indicating unsynced local data.
private struct VaultPulse: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.royalBlue)
                .frame(width: 6, height: 6)
            Circle()
                .fill(Color.royalBlue.opacity(0.4))
                .frame(width: 6, height: 6)
                .blur(radius: 2)
                .scaleEffect(pulse ? 2.4 : 1.0)
                .opacity(pulse ? 0 : 0.8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.canvas.ignoresSafeArea()
        VStack(spacing: 30) {
            WearableStatusPill(bluetooth: BluetoothManager(), unsyncedCount: 3) {}
            WearableStatusPill(bluetooth: BluetoothManager(), unsyncedCount: 0) {}
        }
    }
    .preferredColorScheme(.dark)
}
