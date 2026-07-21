import SwiftUI
import UIKit

/// Installs a non-blocking UIKit gesture on the current window. Keeping this
/// adapter separate prevents the shortcut from becoming coupled to camera code.
struct ThreeFingerTripleTapRecognizer: UIViewRepresentable {
    let isEnabled: Bool
    let onRecognized: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onRecognized: onRecognized)
    }

    func makeUIView(context: Context) -> GestureAttachmentView {
        let view = GestureAttachmentView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: GestureAttachmentView, context: Context) {
        context.coordinator.update(isEnabled: isEnabled, onRecognized: onRecognized)
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: GestureAttachmentView, coordinator: Coordinator) {
        uiView.onWindowChange = nil
        coordinator.attach(to: nil)
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var attachedView: UIView?
        private var onRecognized: () -> Void
        private let recognizer: UITapGestureRecognizer

        init(isEnabled: Bool, onRecognized: @escaping () -> Void) {
            self.onRecognized = onRecognized
            recognizer = UITapGestureRecognizer()
            super.init()

            recognizer.numberOfTouchesRequired = 3
            recognizer.numberOfTapsRequired = 3
            recognizer.cancelsTouchesInView = false
            recognizer.isEnabled = isEnabled
            recognizer.addTarget(self, action: #selector(recognized))
        }

        func update(isEnabled: Bool, onRecognized: @escaping () -> Void) {
            self.onRecognized = onRecognized
            recognizer.isEnabled = isEnabled
        }

        func attach(to view: UIView?) {
            guard attachedView !== view else { return }
            attachedView?.removeGestureRecognizer(recognizer)
            attachedView = view
            view?.addGestureRecognizer(recognizer)
        }

        @objc private func recognized() {
            onRecognized()
        }
    }
}

final class GestureAttachmentView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}
