import UIKit

/// A screenshot shrunk to a few hundred pixels, enough to tell whether a shelf is drawn.
/// The gallery and the Top Shelf test both use it.
struct ScreenSample {
    private static let width = 32
    private static let height = 18
    private var gray = [UInt8](repeating: 0, count: width * height)

    init(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        gray.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: Self.width, height: Self.height, bitsPerComponent: 8,
                bytesPerRow: Self.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        }
    }

    /// How much the picture varies above the dock, which is the bottom quarter of the screen.
    var detailAboveTheDock: Double {
        // Core Graphics puts row 0 at the top of the buffer.
        let values = gray.prefix(Self.width * Self.height * 3 / 4).map(Double.init)
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }
}
