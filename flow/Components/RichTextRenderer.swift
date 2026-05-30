//
//  RichTextRenderer.swift
//  flow
//
//  Parses lightweight markdown from Claude responses and renders
//  them as styled SwiftUI attributed text. Supports bold, italic,
//  inline code, bullet lists, numbered lists, and headers.
//

import SwiftUI

struct RichTextView: View {
    let text: String
    let isUser: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    // MARK: - Block Types

    private enum Block {
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
        case heading(String)
        case source(String)
    }

    // MARK: - Parsing

    private func parseBlocks(_ input: String) -> [Block] {
        let lines = input.components(separatedBy: "\n")
        var blocks: [Block] = []
        var currentParagraph = ""

        func flushParagraph() {
            let trimmed = currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.paragraph(trimmed))
            }
            currentParagraph = ""
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed.hasPrefix("### ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                flushParagraph()
                let heading = trimmed.drop(while: { $0 == "#" || $0 == " " })
                blocks.append(.heading(String(heading)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let content = String(trimmed.dropFirst(2))
                blocks.append(.bullet(content))
            } else if let match = trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let numberStr = trimmed[trimmed.startIndex..<match.lowerBound]
                let number = Int(numberStr) ?? 1
                let content = String(trimmed[match.upperBound...])
                blocks.append(.numbered(number, content))
            } else if trimmed.hasPrefix("📎") || trimmed.hasPrefix("Source:") || trimmed.hasPrefix("Based on:") {
                flushParagraph()
                blocks.append(.source(trimmed))
            } else {
                if !currentParagraph.isEmpty {
                    currentParagraph += " "
                }
                currentParagraph += trimmed
            }
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Rendering

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            styledText(text)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(isUser ? Color.white.opacity(0.6) : Color.textSecondary)
                    .frame(width: 5, height: 5)
                    .offset(y: 1)
                styledText(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case .numbered(let num, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(num).")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isUser ? .white.opacity(0.7) : Color.textSecondary)
                    .frame(width: 20, alignment: .trailing)
                styledText(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 2)

        case .heading(let text):
            Text(text)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isUser ? .white : Color.textPrimary)
                .padding(.top, 4)

        case .source(let text):
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.royalBlue.opacity(0.7))
                Text(cleanSourceText(text))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary.opacity(0.8))
                    .italic()
            }
            .padding(.top, 4)
            .padding(.horizontal, 4)
        }
    }

    private func cleanSourceText(_ text: String) -> String {
        text.replacingOccurrences(of: "📎 ", with: "")
            .replacingOccurrences(of: "📎", with: "")
    }

    // MARK: - Inline Styling

    private func styledText(_ text: String) -> Text {
        parseInlineMarkdown(text, baseColor: isUser ? .white : Color.textPrimary)
    }

    private func parseInlineMarkdown(_ input: String, baseColor: Color) -> Text {
        var result = Text("")
        var remaining = input[input.startIndex...]

        while !remaining.isEmpty {
            if remaining.hasPrefix("**") {
                let after = remaining.index(remaining.startIndex, offsetBy: 2)
                if let end = remaining[after...].range(of: "**") {
                    let bold = String(remaining[after..<end.lowerBound])
                    result = result + Text(bold)
                        .font(.body.weight(.semibold))
                        .foregroundColor(baseColor)
                    remaining = remaining[end.upperBound...]
                    continue
                }
            }

            if remaining.hasPrefix("`") {
                let after = remaining.index(remaining.startIndex, offsetBy: 1)
                if let end = remaining[after...].range(of: "`") {
                    let code = String(remaining[after..<end.lowerBound])
                    result = result + Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(baseColor.opacity(0.85))
                    remaining = remaining[end.upperBound...]
                    continue
                }
            }

            if remaining.hasPrefix("*") && !remaining.hasPrefix("**") {
                let after = remaining.index(remaining.startIndex, offsetBy: 1)
                if let end = remaining[after...].range(of: "*") {
                    let italic = String(remaining[after..<end.lowerBound])
                    result = result + Text(italic)
                        .italic()
                        .foregroundColor(baseColor.opacity(0.9))
                    remaining = remaining[end.upperBound...]
                    continue
                }
            }

            let nextSpecial = findNextSpecial(in: remaining)
            let plain = String(remaining[remaining.startIndex..<nextSpecial])
            result = result + Text(plain)
                .font(.body)
                .foregroundColor(baseColor)
            remaining = remaining[nextSpecial...]
        }

        return result
    }

    private func findNextSpecial(in text: Substring) -> String.Index {
        var idx = text.index(after: text.startIndex)
        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "*" || ch == "`" {
                return idx
            }
            idx = text.index(after: idx)
        }
        return text.endIndex
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            RichTextView(
                text: """
                Here's what I found from your conversations today:

                **Key Decisions:**
                1. Ship Enterprise Sync before the offsite
                2. Pause the BLE pairing redesign until Q4

                - Sarah mentioned the API rate limiter needs attention
                - The team agreed on a **weekly sync** cadence

                📎 Based on: Morning standup, 1:1 with Nolan
                """,
                isUser: false
            )
            .padding()

            RichTextView(
                text: "Give me the action items from today",
                isUser: true
            )
            .padding()
        }
    }
    .background(Color.canvas)
    .preferredColorScheme(.dark)
}
