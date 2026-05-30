//
//  NotificationManager.swift
//  flow
//
//  Schedules local push notifications 15 minutes before each upcoming
//  calendar event. On every refresh cycle the manager removes ALL
//  previously pending Penlo briefing notifications before scheduling
//  the current set — this prevents stale or duplicated alerts when
//  events change or are cancelled.
//

import EventKit
import UserNotifications

@MainActor
final class NotificationManager {

    // MARK: - Constants

    /// All Penlo briefing notifications share this category so they can
    /// be bulk-removed on the next refresh.
    private static let categoryID = "com.getflow.flow.briefing"

    /// How many minutes before the meeting to fire the notification.
    private static let leadTimeMinutes = 15

    // MARK: - Authorization

    /// Request notification permission. Returns `true` when granted.
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log("Notification auth failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Schedule

    /// Full refresh: remove stale notifications, then schedule a new
    /// 15-minute-ahead alert for every event whose trigger time is
    /// still in the future.
    func refreshNotifications(for events: [EKEvent]) async {
        let center = UNUserNotificationCenter.current()

        // 1. Remove all pending Penlo briefing notifications.
        let pending = await center.pendingNotificationRequests()
        let penloIDs = pending
            .filter { $0.content.categoryIdentifier == Self.categoryID }
            .map(\.identifier)
        if !penloIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: penloIDs)
            log("Removed \(penloIDs.count) stale notifications")
        }

        // 2. Schedule fresh notifications for events that haven't passed.
        let now = Date.now
        var scheduled = 0

        for event in events {
            guard let fireDate = Calendar.current.date(
                byAdding: .minute,
                value: -Self.leadTimeMinutes,
                to: event.startDate
            ) else { continue }

            // Only schedule if the trigger time is still in the future.
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Meeting in \(Self.leadTimeMinutes)m"
            content.body = event.title ?? "Upcoming meeting"
            content.sound = .default
            content.categoryIdentifier = Self.categoryID

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let id = "\(Self.categoryID).\(event.eventIdentifier ?? UUID().uuidString)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                log("Failed to schedule notification for '\(event.title ?? "?")': \(error.localizedDescription)")
            }
        }

        log("Scheduled \(scheduled) briefing notifications")
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        #if DEBUG
        print("[Penlo Notif] \(message)")
        #endif
    }
}
