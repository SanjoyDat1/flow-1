//
//  Theme.swift
//  flow
//
//  Single source of truth for Penlo's visual language.
//  Twin-mode semantic tokens that adapt to Light & Dark appearances,
//  mirroring the ChatGPT iOS aesthetic: hyper-minimal, airy, balanced.
//

import SwiftUI
import UIKit

// MARK: - Hex Initializer

extension Color {
    /// Initialize a Color from a hex string (e.g. "171717").
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: .alphanumerics.inverted))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Semantic Tokens

extension Color {

    /// Main canvas background — deep black in dark, crisp white in light.
    static let canvas = Color(
        light: Color(hex: "FFFFFF"),
        dark: Color(hex: "000000")
    )

    /// Secondary card / surface — soft-gray in light, matte slate in dark.
    static let surface = Color(
        light: Color(hex: "F9F9F9"),
        dark: Color(hex: "212121")
    )

    /// Primary typography — near-black in light, stark white in dark.
    static let textPrimary = Color(
        light: Color(hex: "171717"),
        dark: Color(hex: "FFFFFF")
    )

    /// Muted secondary text — charcoal in light, neutral ash in dark.
    static let textSecondary = Color(
        light: Color(hex: "6E6E73"),
        dark: Color(hex: "999999")
    )

    /// The single interactive accent — constant across both modes.
    static let royalBlue = Color(hex: "0053D6")

    // Legacy aliases.
    static let penloBlack = Color(hex: "000000")
    static let penloWhite = Color(hex: "FFFFFF")
}

// MARK: - Adaptive Color Helper

private extension Color {
    /// Create a color that resolves differently in light vs dark mode.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

// MARK: - Layout Constants

/// Centralized spacing & radius tokens. Named `Metrics` to avoid
/// colliding with SwiftUI's `Layout` protocol.
enum Metrics {
    static let screenPadding: CGFloat = 20
    static let cardSpacing: CGFloat = 24
    static let chipSpacing: CGFloat = 8

    static let pillRadius: CGFloat = 24
    static let cardRadius: CGFloat = 16
    static let bubbleRadius: CGFloat = 20

    static let islandTopInset: CGFloat = 8
    static let drawerWidth: CGFloat = 300
}

// MARK: - Haptics

/// Thin wrapper around `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`
/// so every state change fires a precise haptic with one call.
enum Haptics {
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare(); g.impactOccurred()
    }

    static func medium() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare(); g.impactOccurred()
    }

    static func success() {
        let g = UINotificationFeedbackGenerator()
        g.prepare(); g.notificationOccurred(.success)
    }
}
