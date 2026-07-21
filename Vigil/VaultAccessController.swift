import Combine
import LocalAuthentication

final class VaultAccessController: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var message: String?

    private var context: LAContext?

    func unlock() {
        guard !isUnlocked, !isAuthenticating else { return }

        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        context.localizedFallbackTitle = "Use Passcode"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            message = "Set up Face ID or a device passcode in iPhone Settings to open the Vigil Vault."
            return
        }

        self.context = context
        isAuthenticating = true
        message = nil

        Task {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Unlock your private Vigil Vault"
                )
                guard self.context === context else { return }
                isAuthenticating = false
                if success {
                    isUnlocked = true
                }
            } catch let error as LAError {
                guard self.context === context else { return }
                isAuthenticating = false
                switch error.code {
                case .userCancel, .appCancel, .systemCancel:
                    message = nil
                default:
                    message = "Vigil Vault could not be unlocked. Try Face ID or your device passcode again."
                }
            } catch {
                guard self.context === context else { return }
                isAuthenticating = false
                message = "Vigil Vault could not be unlocked. Please try again."
            }
        }
    }

    func lock() {
        context?.invalidate()
        context = nil
        isAuthenticating = false
        isUnlocked = false
        message = nil
    }
}
