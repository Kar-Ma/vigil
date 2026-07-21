import Combine
import GoogleSignIn
import UIKit

@MainActor
final class GoogleDriveManager: ObservableObject {
    static let driveFileScope = "https://www.googleapis.com/auth/drive.file"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isConnecting = false
    @Published private(set) var activeUploadCount = 0
    @Published private(set) var accountEmail: String?
    @Published private(set) var lastErrorMessage: String?

    private let enabledDefaultsKey = "saveToGoogleDrive"
    private let uploader = GoogleDriveUploader()

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    var statusDetail: String {
        if isConnecting {
            return "Connecting securely to your Google account…"
        }
        if activeUploadCount > 0 {
            return "Uploading a protected copy to Google Drive…"
        }
        if isEnabled, let accountEmail {
            return "Connected as \(accountEmail). New recordings upload automatically."
        }
        if let lastErrorMessage {
            return lastErrorMessage
        }
        return "Save a copy in a Vigil folder in your Google Drive."
    }

    func restoreConnection() async {
        guard isEnabled else { return }
        isConnecting = true
        defer { isConnecting = false }

        do {
            let user = try await restorePreviousUser()
            guard user.grantedScopes?.contains(Self.driveFileScope) == true else {
                throw GoogleDriveConnectionError.permissionMissing
            }
            applyConnectedUser(user)
        } catch {
            disableConnection(signOut: false)
        }
    }

    func setEnabled(_ shouldEnable: Bool) {
        guard shouldEnable != isEnabled else { return }

        if !shouldEnable {
            disableConnection(signOut: true)
            return
        }

        guard !isConnecting else { return }
        isConnecting = true
        lastErrorMessage = nil

        Task { [weak self] in
            await self?.connectInteractively()
        }
    }

    func uploadRecording(at fileURL: URL, createdAt: Date) async throws {
        guard isEnabled else {
            throw GoogleDriveConnectionError.notConnected
        }

        activeUploadCount += 1
        defer { activeUploadCount -= 1 }

        do {
            let user = try await refreshedUser()
            try await uploader.upload(
                fileURL: fileURL,
                createdAt: createdAt,
                accessToken: user.accessToken.tokenString
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = friendlyMessage(for: error)
            throw error
        }
    }

    private func connectInteractively() async {
        defer { isConnecting = false }

        do {
            guard let presentingViewController = presentingViewController() else {
                throw GoogleDriveConnectionError.cannotPresentSignIn
            }
            let user = try await signIn(presenting: presentingViewController)
            guard user.grantedScopes?.contains(Self.driveFileScope) == true else {
                throw GoogleDriveConnectionError.permissionMissing
            }
            applyConnectedUser(user)
        } catch {
            disableConnection(signOut: false)
            lastErrorMessage = friendlyMessage(for: error)
        }
    }

    private func applyConnectedUser(_ user: GIDGoogleUser) {
        isEnabled = true
        accountEmail = user.profile?.email
        lastErrorMessage = nil
        UserDefaults.standard.set(true, forKey: enabledDefaultsKey)
    }

    private func disableConnection(signOut: Bool) {
        if signOut {
            GIDSignIn.sharedInstance.signOut()
        }
        isEnabled = false
        accountEmail = nil
        UserDefaults.standard.set(false, forKey: enabledDefaultsKey)
    }

    private func signIn(presenting viewController: UIViewController) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: nil,
                additionalScopes: [Self.driveFileScope]
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: GoogleDriveConnectionError.signInFailed)
                }
            }
        }
    }

    private func restorePreviousUser() async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: GoogleDriveConnectionError.notConnected)
                }
            }
        }
    }

    private func refreshedUser() async throws -> GIDGoogleUser {
        let currentUser: GIDGoogleUser
        if let user = GIDSignIn.sharedInstance.currentUser {
            currentUser = user
        } else {
            currentUser = try await restorePreviousUser()
        }

        return try await withCheckedThrowingContinuation { continuation in
            currentUser.refreshTokensIfNeeded { user, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: GoogleDriveConnectionError.notConnected)
                }
            }
        }
    }

    private func presentingViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        return topViewController(from: root)
    }

    private func topViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = viewController as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tab = viewController as? UITabBarController,
           let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        return viewController
    }

    private func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == kGIDSignInErrorDomain,
           nsError.code == -5 {
            return "Google Drive was not connected. Your Vault remains active."
        }
        if let error = error as? GoogleDriveConnectionError {
            return error.localizedDescription
        }
        return "Google Drive could not be reached. The Vigil Vault copy is safe."
    }
}

enum GoogleDriveConnectionError: LocalizedError {
    case cannotPresentSignIn
    case signInFailed
    case permissionMissing
    case notConnected

    var errorDescription: String? {
        switch self {
        case .cannotPresentSignIn:
            "Vigil could not open Google sign-in. Please try again."
        case .signInFailed:
            "Google sign-in did not finish. Please try again."
        case .permissionMissing:
            "Allow Vigil to create its own Google Drive files to enable this option."
        case .notConnected:
            "Connect Google Drive in Settings before uploading."
        }
    }
}
