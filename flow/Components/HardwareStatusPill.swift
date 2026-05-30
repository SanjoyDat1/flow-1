//
//  HardwareStatusPill.swift
//  flow
//
//  Ultra-minimalist Dynamic Island-style pill floating at the top center.
//  Shows a Bluetooth icon, battery %, and a pulsing status dot.
//  Tapping opens the Settings/Queue sheet.
//

import SwiftUI

struct HardwareStatusPill: View {
    @ObservedObject var bluetooth: BluetoothManager
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("\(bluetooth.batteryLevel.map { "\($0)" } ?? "--")%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)

                statusDot
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.textPrimary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Penlo. \(bluetooth.state.label). \(bluetooth.batteryLevel.map { "\($0) percent" } ?? "no battery info").")
    }

    // MARK: - Status Dot

    @ViewBuilder
    private var statusDot: some View {
        switch bluetooth.state {
        case .recording:
            PulsingDot(color: .royalBlue, glowing: true)
        case .searching:
            PulsingDot(color: .royalBlue, glowing: false)
        case .connected:
            Circle()
                .fill(Color.textPrimary)
                .frame(width: 6, height: 6)
        case .disconnected:
            Circle()
                .strokeBorder(Color.textSecondary, lineWidth: 1.2)
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    let color: Color
    let glowing: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            if glowing {
                Circle()
                    .fill(color.opacity(0.45))
                    .frame(width: 6, height: 6)
                    .blur(radius: 2)
                    .scaleEffect(pulse ? 2.0 : 1.0)
                    .opacity(pulse ? 0 : 0.8)
            }
        }
        .onAppear {
            let anim: Animation = glowing
                ? .easeOut(duration: 1.2).repeatForever(autoreverses: false)
                : .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
            withAnimation(anim) { pulse = true }
        }
    }
}

#Preview {
    ZStack {
        Color.canvas.ignoresSafeArea()
        HardwareStatusPill(bluetooth: BluetoothManager()) {}
    }
    .preferredColorScheme(.dark)
}
