//
//  HardwareManagementSheet.swift
//  flow
//
//  Manage the BLE connection, view the local unsynced queue, and enter
//  the Claude API key. Standard iOS form in a modal sheet.
//

import SwiftData
import SwiftUI

struct HardwareManagementSheet: View {
    @ObservedObject var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Transcript> { !$0.isSynced })
    private var unsyncedTranscripts: [Transcript]

    @State private var apiKey: String = ""
    @State private var brainURL: String = ""
    @State private var brainKey: String = ""
    @State private var userEmail: String = ""
    @State private var aggressiveBackgroundSync = false
    @State private var wifiOnlySync = true
    @State private var verifyState: VerifyState = .idle

    private enum VerifyState: Equatable {
        case idle
        case verifying
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                phoneMicSection
                authSection
                accountSection
                enterpriseBrainSection
                queueSection
                batterySection
            }
            .scrollContentBackground(.hidden)
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("Penlo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAPIKeyIfNeeded()
                        dismiss()
                    }
                    .foregroundStyle(Color.royalBlue)
                }
            }
            .tint(.royalBlue)
            .onAppear {
                apiKey = KeychainStore.readAPIKey() ?? ""
                brainURL = KeychainStore.readBrainURL() ?? ""
                brainKey = KeychainStore.readBrainKey() ?? ""
                userEmail = KeychainStore.readUserEmail() ?? ""
            }
        }
    }

    // MARK: Connection

    private var connectionSection: some View {
        Section {
            HStack(spacing: 16) {
                ScanningRadar(
                    isScanning: bluetooth.state == .searching,
                    isConnected: bluetooth.state == .connected || bluetooth.state.isLive
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(bluetooth.state == .disconnected ? "Connect Penlo Wearable" : "Penlo Wearable")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(bluetooth.state.label)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Button {
                    if bluetooth.state == .disconnected {
                        bluetooth.connect()
                    } else {
                        bluetooth.disconnect()
                    }
                } label: {
                    Text(bluetooth.state == .disconnected ? "Connect" : "Disconnect")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.royalBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Connection")
        }
    }

    // MARK: Phone Mic

    private var phoneMicSection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(Color.royalBlue)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Phone Microphone")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Use your iPhone mic when Penlo wearable isn't connected")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Text("Smart Listening")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
            }

            HStack {
                Text("Auto-Stop After Silence")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("2 min")
                    .font(.body.weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }

            HStack {
                Text("On-Device Processing")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
            }
        } header: {
            Text("Phone Microphone")
        } footer: {
            Text("Tap the mic button in chat to start listening. Speech is processed entirely on-device. Recording auto-stops after 2 minutes of silence to preserve battery.")
        }
    }

    // MARK: Auth

    private var authSection: some View {
        Section {
            SecureField("sk-ant-…", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.textPrimary)
                .onChange(of: apiKey) { _, _ in
                    verifyState = .idle
                }

            Button {
                verifyAPIKey()
            } label: {
                HStack {
                    Text(verifyButtonTitle)
                    Spacer()
                    verifyTrailingIcon
                }
                .foregroundStyle(canVerify ? Color.royalBlue : Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!canVerify)
        } header: {
            Text("Claude API Key")
        } footer: {
            Text(footerText)
        }
    }

    private var canVerify: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && verifyState != .verifying
    }

    private var verifyButtonTitle: String {
        switch verifyState {
        case .verifying: return "Verifying…"
        case .success: return "Verified"
        default: return "Verify Key"
        }
    }

    @ViewBuilder
    private var verifyTrailingIcon: some View {
        switch verifyState {
        case .verifying:
            ProgressView().tint(.royalBlue).scaleEffect(0.85)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    private var footerText: String {
        switch verifyState {
        case .failure(let message):
            return message
        case .success:
            return "Key verified and saved. Penlo chat is now powered by Claude."
        default:
            return "Get your key at console.anthropic.com. Stored securely in Keychain on this device."
        }
    }

    // MARK: Account

    private var accountSection: some View {
        Section {
            TextField("you@company.com", text: $userEmail)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .foregroundStyle(Color.textPrimary)
        } header: {
            Text("Account")
        } footer: {
            Text("Your email is included in Enterprise Brain syncs to associate knowledge with your identity.")
        }
    }

    // MARK: Enterprise Brain

    private var enterpriseBrainSection: some View {
        Section {
            TextField("https://your-brain-endpoint.com/api/v1/ingest/penlo-brain", text: $brainURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .foregroundStyle(Color.textPrimary)

            SecureField("pb_live_…", text: $brainKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.textPrimary)

            HStack {
                Text("Status")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if !brainURL.isEmpty && !brainKey.isEmpty {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("Configured")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text("Not Connected")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.orange)
                    }
                }
            }
        } header: {
            Text("Enterprise Brain")
        } footer: {
            Text("Connect to your Enterprise Brain for persistent knowledge graph sync. The endpoint and API key will be provided by your team admin.")
        }
    }

    // MARK: Queue

    private var queueSection: some View {
        Section {
            HStack {
                Text("Local Unsynced Transcripts")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(unsyncedTranscripts.count)")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(unsyncedTranscripts.count > 0 ? Color.royalBlue : Color.textSecondary)
            }

            Button {
                syncAllTranscripts()
            } label: {
                HStack {
                    Text(bluetooth.isSyncing ? "Syncing…" : "Sync Now")
                    if bluetooth.isSyncing {
                        Spacer()
                        ProgressView().tint(.royalBlue)
                    }
                }
                .foregroundStyle(unsyncedTranscripts.count > 0 ? Color.royalBlue : Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(unsyncedTranscripts.isEmpty || bluetooth.isSyncing)
        } header: {
            Text("Queue Status")
        }
    }

    private func syncAllTranscripts() {
        let context = modelContext
        let transcriptsToSync = unsyncedTranscripts
        bluetooth.syncAll {
            try await Task.sleep(for: .seconds(0.3))
            await MainActor.run {
                for transcript in transcriptsToSync {
                    transcript.isSynced = true
                }
                try? context.save()
            }
        }
    }

    // MARK: Battery Optimization

    private var batterySection: some View {
        Section {
            Toggle("Aggressive Background Sync", isOn: $aggressiveBackgroundSync)
            Toggle("Wi-Fi Only Sync", isOn: $wifiOnlySync)
        } header: {
            Text("Battery Optimization")
        } footer: {
            Text("Wi-Fi-only sync preserves battery; aggressive background sync keeps your Enterprise Brain up to date in real time.")
        }
    }

    // MARK: - Keychain

    private func saveAPIKeyIfNeeded() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try KeychainStore.deleteAPIKey()
            } else {
                try KeychainStore.saveAPIKey(trimmed)
            }
        } catch {
            #if DEBUG
            print("[Penlo] Keychain save failed: \(error.localizedDescription)")
            #endif
        }

        // Save Enterprise Brain config
        KeychainStore.saveBrainURL(brainURL.trimmingCharacters(in: .whitespacesAndNewlines))
        KeychainStore.saveBrainKey(brainKey.trimmingCharacters(in: .whitespacesAndNewlines))

        // Save user email
        KeychainStore.saveUserEmail(userEmail.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func verifyAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        verifyState = .verifying
        Task {
            do {
                try KeychainStore.saveAPIKey(trimmed)
                try await ClaudeService.shared.verify(apiKey: trimmed)
                verifyState = .success
                Haptics.success()
            } catch let error as ClaudeService.ServiceError {
                verifyState = .failure(error.userFacingMessage)
                Haptics.medium()
            } catch {
                verifyState = .failure(error.localizedDescription)
                Haptics.medium()
            }
        }
    }
}

// MARK: - Scanning Radar

private struct ScanningRadar: View {
    let isScanning: Bool
    let isConnected: Bool

    @State private var ripple = false

    var body: some View {
        ZStack {
            if isScanning {
                Circle()
                    .stroke(Color.royalBlue.opacity(0.6), lineWidth: 1.5)
                    .scaleEffect(ripple ? 1.6 : 0.6)
                    .opacity(ripple ? 0 : 1)
            }
            Circle()
                .fill(isConnected ? Color.royalBlue : Color.gray.opacity(0.6))
                .frame(width: 10, height: 10)
        }
        .frame(width: 32, height: 32)
        .onChange(of: isScanning) { _, scanning in
            if scanning {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    ripple = true
                }
            } else {
                ripple = false
            }
        }
    }
}

#Preview {
    HardwareManagementSheet(bluetooth: BluetoothManager())
}
