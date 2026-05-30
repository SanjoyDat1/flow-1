//
//  CalendarManager.swift
//  flow
//
//  Read-only EventKit access. Polls EKEventStore for calendar events
//  occurring within the next 24 hours. Polling is triggered only on
//  app foreground or via BGAppRefreshTask — never continuously.
//

import EventKit

@MainActor
final class CalendarManager {

    // MARK: - Shared Store

    /// Single store instance; reused across polls to avoid redundant auth prompts.
    private let store = EKEventStore()

    // MARK: - Authorization

    /// Request read-only calendar access. Returns `true` when granted.
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            log("Calendar access request failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Polling

    /// Fetch every event starting within the next 24 hours.
    /// Returns an empty array if access was not granted or the query fails.
    func upcomingEvents() -> [EKEvent] {
        let now = Date.now
        let end = Calendar.current.date(byAdding: .hour, value: 24, to: now)!
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        log("Polled \(events.count) events in the next 24h")
        return events
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        #if DEBUG
        print("[Penlo Cal] \(message)")
        #endif
    }
}
