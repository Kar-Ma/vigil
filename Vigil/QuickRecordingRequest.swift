import Foundation

/// Passes a short-lived recording request from App Intents to the foreground app.
/// The timestamp prevents an old request from unexpectedly starting a later session.
enum QuickRecordingRequest {
    static let notification = Notification.Name("VigilQuickRecordingRequested")

    private static let requestedAtKey = "quickRecordingRequestedAt"
    private static let maximumAge: TimeInterval = 30

    static func submit() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: requestedAtKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func consumeIfRecent(now: Date = Date()) -> Bool {
        let requestedAt = UserDefaults.standard.double(forKey: requestedAtKey)
        UserDefaults.standard.removeObject(forKey: requestedAtKey)

        guard requestedAt > 0 else { return false }
        let age = now.timeIntervalSince1970 - requestedAt
        return age >= -2 && age <= maximumAge
    }
}
