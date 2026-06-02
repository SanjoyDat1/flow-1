//
//  flowApp.swift
//  flow
//

import SwiftUI

@main
struct flowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let calendarManager = CalendarManager()
    private let modelContainer = PenloStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .task { await requestPermissionsOnce() }
                .onReceive(
                    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                ) { _ in
                    Task { await refreshBriefingNotifications() }
                }
        }
    }

    private func requestPermissionsOnce() async {
        _ = await calendarManager.requestAccess()
        _ = await NotificationManager.shared.requestAuthorization()
        await refreshBriefingNotifications()
    }

    @Sendable
    private func refreshBriefingNotifications() async {
        let events = await MainActor.run { calendarManager.upcomingEvents() }
        await NotificationManager.shared.refreshNotifications(for: events)
    }
}
