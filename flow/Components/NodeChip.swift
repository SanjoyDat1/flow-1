//
//  NodeChip.swift
//  flow
//
//  A borderless Royal Blue text chip representing one extracted node.
//

import SwiftUI

struct NodeChip: View {
    let node: ExtractedNode

    var body: some View {
        Text(node.displayText)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.royalBlue)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        NodeChip(node: ExtractedNode(kind: .feature, label: "Enterprise Sync"))
        NodeChip(node: ExtractedNode(kind: .person, label: "Nolan Carroll"))
    }
    .padding()
    .background(Color.canvas)
}
