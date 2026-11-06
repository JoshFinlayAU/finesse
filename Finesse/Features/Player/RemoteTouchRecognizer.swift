import SwiftUI
import UIKit

/// Reads swipes on the Siri Remote's touch surface, which SwiftUI has no equivalent for on tvOS.
/// The recognizers sit on the window because touches go to the focused view's ancestors.
struct RemoteTouchRecognizer: UIViewRepresentable {
    let onPan: (Double) -> Void
    let onSwipe: (MoveCommandDirection) -> Void

    func makeUIView(context: Context) -> TouchHostView {
        TouchHostView()
    }

    func updateUIView(_ uiView: TouchHostView, context: Context) {
        uiView.onPan = onPan
        uiView.onSwipe = onSwipe
    }

    final class TouchHostView: UIView, UIGestureRecognizerDelegate {
        var onPan: ((Double) -> Void)?
        var onSwipe: ((MoveCommandDirection) -> Void)?

        private lazy var recognizers: [UIGestureRecognizer] = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            let up = UISwipeGestureRecognizer(target: self, action: #selector(swiped))
            up.direction = .up
            let down = UISwipeGestureRecognizer(target: self, action: #selector(swiped))
            down.direction = .down
            return [pan, up, down].map { recognizer in
                recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                return recognizer
            }
        }()

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            for recognizer in recognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
                newWindow?.addGestureRecognizer(recognizer)
            }
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            #if DEBUG
            logPan(recognizer)
            #endif
            guard recognizer.state == .changed, let width = recognizer.view?.bounds.width, width > 0 else {
                return
            }
            onPan?(recognizer.translation(in: recognizer.view).x / width)
            recognizer.setTranslation(.zero, in: recognizer.view)
        }

        @objc private func swiped(_ recognizer: UISwipeGestureRecognizer) {
            PlayerRemoteLog.note("swipe \(recognizer.direction == .up ? "up" : "down")")
            onSwipe?(recognizer.direction == .up ? .up : .down)
        }

        #if DEBUG
        /// Across the whole touch, so the log shows how far a full swipe and a resting thumb really go.
        private var panTotal = CGPoint.zero

        private func logPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view, view.bounds.width > 0 else {
                return
            }
            let step = recognizer.translation(in: view)
            if recognizer.state == .began {
                panTotal = .zero
            }
            panTotal.x += step.x
            panTotal.y += step.y
            let names: [UIGestureRecognizer.State: String] = [.began: "began", .changed: "changed", .ended: "ended", .cancelled: "cancelled"]
            let across = panTotal.x / view.bounds.width
            let down = panTotal.y / view.bounds.height
            PlayerRemoteLog.note("pan \(names[recognizer.state] ?? "other") across \(across) down \(down)")
        }
        #endif

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
