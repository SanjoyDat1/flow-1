//
//  AppDelegate.swift
//  flow
//
//  APNs registration, BGTask registration, and notification delegate wiring.
//

import BackgroundTasks
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let bgTaskID = "com.getflow.flow.calendar-refresh"
    private let notificationDelegate = PenloNotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgTaskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            refresh.expirationHandler = { refresh.setTaskCompleted(success: false) }
            Task {
                let events = await MainActor.run { CalendarManager().upcomingEvents() }
                await NotificationManager.shared.refreshNotifications(for: events)
                self.scheduleBackgroundRefresh()
                refresh.setTaskCompleted(success: true)
            }
        }
        scheduleBackgroundRefresh()

        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { await PushRegistrationService.registerAPNsToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("[Penlo APNs] registration failed: \(error.localizedDescription)")
        #endif
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[Penlo BG] schedule failed: \(error.localizedDescription)")
            #endif
        }
    }
}

enum PushRegistrationService {
    @MainActor
    static func registerAPNsToken(_ token: String) async {
        guard let base = brainBaseURL(), let key = KeychainStore.readBrainKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return
        }
        guard let url = URL(string: "/api/v1/notifications/devices", relativeTo: base) else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["platform": "ios", "token": token]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    private static func brainBaseURL() -> URL? {
        guard let raw = KeychainStore.readBrainURL() else { return nil }
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
