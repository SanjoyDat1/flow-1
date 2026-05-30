//
//  ExtractedNode.swift
//  flow
//
//  A single piece of intelligence the wearable extracted from a
//  conversation (a feature, a person, a decision, an open question).
//  Rendered as a borderless Royal Blue text chip.
//

import Foundation

/// A discrete extracted entity attached to a `SyncEvent`.
struct ExtractedNode: Identifiable, Hashable, Sendable {
    let id = UUID()
    let kind: Kind
    let label: String

    /// The category of an extracted node. Only used to prefix the chip text;
    /// the visual treatment is intentionally uniform (Royal Blue, borderless).
    enum Kind: String {
        case feature  = "Feature"
        case person   = "Person"
        case decision = "Decision"
        case question = "Question"
    }

    /// e.g. "Feature: Enterprise Sync"
    var displayText: String {
        "\(kind.rawValue): \(label)"
    }
}
