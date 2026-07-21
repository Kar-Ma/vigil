import Combine
import UIKit

/// Owns only the display-privacy behavior. It never changes the camera session
/// or the recording pipeline, so Screen Curtain can be removed independently.
@MainActor
final class ScreenCurtainController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isGestureEnabled: Bool

    private let gestureDefaultsKey = "screenCurtainGestureEnabled"
    private let dimmedBrightness: CGFloat = 0.08
    private var brightnessBeforeCurtain: CGFloat?

    init() {
        if UserDefaults.standard.object(forKey: gestureDefaultsKey) == nil {
            isGestureEnabled = true
        } else {
            isGestureEnabled = UserDefaults.standard.bool(forKey: gestureDefaultsKey)
        }
    }

    func setGestureEnabled(_ isEnabled: Bool) {
        isGestureEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: gestureDefaultsKey)

        if !isEnabled {
            deactivate()
        }
    }

    func handleThreeFingerTripleTap() {
        guard isGestureEnabled else { return }

        // VoiceOver owns this gesture and provides Apple's real Screen Curtain.
        // Vigil must not compete with or replace that system accessibility behavior.
        guard !UIAccessibility.isVoiceOverRunning else { return }

        isActive ? deactivate() : activate()
    }

    func deactivateWhenLeavingForeground() {
        deactivate(feedback: false)
    }

    private func activate() {
        guard !isActive else { return }

        brightnessBeforeCurtain = UIScreen.main.brightness
        UIScreen.main.brightness = min(UIScreen.main.brightness, dimmedBrightness)
        isActive = true
        provideFeedback(isActivating: true)
        UIAccessibility.post(notification: .announcement, argument: "Screen Curtain on")
    }

    private func deactivate(feedback: Bool = true) {
        guard isActive || brightnessBeforeCurtain != nil else { return }

        if let brightnessBeforeCurtain {
            UIScreen.main.brightness = brightnessBeforeCurtain
        }
        brightnessBeforeCurtain = nil
        isActive = false

        if feedback {
            provideFeedback(isActivating: false)
            UIAccessibility.post(notification: .announcement, argument: "Screen Curtain off")
        }
    }

    private func provideFeedback(isActivating: Bool) {
        let generator = UIImpactFeedbackGenerator(style: isActivating ? .rigid : .soft)
        generator.prepare()
        generator.impactOccurred()
    }
}
