//
//  flowApp.swift
//  flow
//
//  Created by Sanjoy Datta on 2026-05-29.
//

import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct flowApp: App {

    private let calendarManager = CalendarManager()
    private let notificationManager = NotificationManager()
    private let modelContainer = PenloStore.makeContainer()

    private static let bgTaskID = "com.getflow.flow.calendar-refresh"

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
        .backgroundTask(.appRefresh(Self.bgTaskID)) {
            await handleBackgroundRefresh()
        }
    }

    // MARK: - One-Time Permission Requests

    private func requestPermissionsOnce() async {
        _ = await calendarManager.requestAccess()
        _ = await notificationManager.requestAuthorization()
        await refreshBriefingNotifications()
    }

    // MARK: - Foreground & Background Refresh

    @Sendable
    private func refreshBriefingNotifications() async {
        let events = await MainActor.run { calendarManager.upcomingEvents() }
        await notificationManager.refreshNotifications(for: events)
    }

    @Sendable
    private func handleBackgroundRefresh() async {
        await refreshBriefingNotifications()
        scheduleNextBackgroundRefresh()
    }

    private func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[Penlo BG] Failed to schedule next refresh: \(error.localizedDescription)")
            #endif
        }
    }
}
