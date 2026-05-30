//
//  ChatInputBar.swift
//  flow
//
//  Floating pill-shaped text input bar with horizontally scrollable
//  suggestion chips above it. The TextField uses `axis: .vertical`
//  for dynamic multi-line resize and handles keyboard avoidance via
//  SwiftUI's native `.scrollDismissesKeyboard(.interactively)`.
//

import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let suggestions: [String]
    let onSend: () -> Void
    let onSuggestion: (String) -> Void
    /// Increment from a parent view to programmatically focus the text field.
    var focusTrigger: Int = 0
    /// Whether the phone microphone is currently listening.
    var isListening: Bool = false
    /// Called when the user taps the mic button.
    var onMicTap: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            if !suggestions.isEmpty {
                suggestionChips
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            inputRow
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.25), value: suggestions.isEmpty)
        .animation(.snappy(duration: 0.22), value: isFocused)
        .onChange(of: focusTrigger) { _, _ in
            guard focusTrigger > 0 else { return }
            isFocused = true
        }
    }

    // MARK: - Suggestion Chips

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSuggestion(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(Color.textPrimary.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Input Row (dismiss button + pill)

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Chevron-down dismiss button — slides in when keyboard is open
            if isFocused {
                Button {
                    Haptics.light()
                    isFocused = false
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.textSecondary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    )
                )
            }

            inputField
        }
    }

    // MARK: - Input Pill

    private var inputField: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask Penlo…", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .focused($isFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onSubmit {
                    if canSend {
                        Haptics.light()
                        onSend()
                    }
                }

            if canSend {
                Button {
                    Haptics.light()
                    onSend()
                    isFocused = false
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.royalBlue)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
                .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    Haptics.medium()
                    onMicTap?()
                } label: {
                    Image(systemName: isListening ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isListening ? Color.red : Color.textSecondary.opacity(0.55))
                        .symbolEffect(.pulse, isActive: isListening)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background(
            isListening
                ? AnyShapeStyle(Color.red.opacity(0.06))
                : AnyShapeStyle(.ultraThinMaterial),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                isListening ? Color.red.opacity(0.3) : Color.textPrimary.opacity(0.08),
                lineWidth: isListening ? 1.5 : 0.5
            )
        )
        .animation(.snappy(duration: 0.2), value: canSend)
        .animation(.snappy(duration: 0.2), value: isListening)
    }
}

#Preview {
    ZStack {
        Color.canvas.ignoresSafeArea()
        VStack {
            Spacer()
            ChatInputBar(
                text: .constant(""),
                suggestions: ["Summarize my day", "Any open action items?", "Brief me"],
                onSend: {},
                onSuggestion: { _ in }
            )
        }
    }
    .preferredColorScheme(.dark)
}
