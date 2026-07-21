import AppIntents

struct StartVigilRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Vigil Recording"
    static let description = IntentDescription(
        "Open Vigil and begin recording with your default camera mode."
    )

    // Keeps the shortcut working on iOS 18–25. iOS 26 uses supportedModes below.
    static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    static var authenticationPolicy: IntentAuthenticationPolicy {
        .requiresAuthentication
    }

    func perform() async throws -> some IntentResult {
        QuickRecordingRequest.submit()
        return .result()
    }
}

struct VigilShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVigilRecordingIntent(),
            phrases: [
                "Start a recording with \(.applicationName)",
                "Record with \(.applicationName)"
            ],
            shortTitle: "Start Vigil Recording",
            systemImageName: "record.circle"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .red }
}
