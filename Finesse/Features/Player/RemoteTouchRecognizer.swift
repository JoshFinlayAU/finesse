import SwiftUI
import UIKit

/// Reads horizontal swipes on the Siri Remote's touch surface. SwiftUI has no equivalent on tvOS.
/// The recognizer sits on the window because touches go to the focused view's ancestors.
struct RemotePanRecognizer: UIViewRepresentable {
    let onPan: (Double) -> Void
    let onEnded: () -> Void

    func makeUIView(context: Context) -> PanHostView {
        PanHostView()
    }

    func updateUIView(_ uiView: PanHostView, context: Context) {
        uiView.onPan = onPan
        uiView.onEnded = onEnded
    }

    final class PanHostView: UIView, UIGestureRecognizerDelegate {
        var onPan: ((Double) -> Void)?
        var onEnded: (() -> Void)?
        private lazy var recognizer: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(panned))
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            recognizer.view?.removeGestureRecognizer(recognizer)
            newWindow?.addGestureRecognizer(recognizer)
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .changed:
                guard let width = recognizer.view?.bounds.width, width > 0 else { return }
                onPan?(recognizer.translation(in: recognizer.view).x / width)
                recognizer.setTranslation(.zero, in: recognizer.view)
            case .ended, .cancelled:
                onEnded?()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
