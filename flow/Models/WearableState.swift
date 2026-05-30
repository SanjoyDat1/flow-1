//
//  WearableState.swift
//  flow
//
//  The connection lifecycle of the Penlo wearable. Drives the
//  status dot in the WearableStatusIsland and gates animations.
//

import SwiftUI

/// The four discrete states the wearable can be in.
enum WearableState: Equatable {
    case disconnected
    case searching
    case connected
    case recording

    /// Human-readable label for the status island / settings sheet.
    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .searching:    return "Searching…"
        case .connected:    return "Connected"
        case .recording:    return "Recording"
        }
    }

    /// Whether the wearable is actively streaming. Used to decide when the
    /// "liquid glass" animation should run (power efficiency).
    var isLive: Bool {
        self == .recording
    }

    /// SF Symbol representing the hardware in this state.
    var hardwareSymbol: String {
        switch self {
        case .disconnected: return "dot.radiowaves.left.and.right"
        case .searching:    return "dot.radiowaves.left.and.right"
        case .connected:    return "waveform"
        case .recording:    return "waveform"
        }
    }
}
