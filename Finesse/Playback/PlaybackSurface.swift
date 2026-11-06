import SwiftUI
import UIKit

/// Shows an engine's video. This keeps each engine's UIKit render view out of feature code.
struct PlaybackSurface: UIViewRepresentable {
    let engine: any PlaybackEngine

    func makeUIView(context: Context) -> UIView {
        engine.makeRenderView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
