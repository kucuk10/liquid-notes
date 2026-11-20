import Foundation
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    /// A `CGImage` representation that works on every platform.
    var cgImageValue: CGImage? {
        #if canImport(UIKit)
        cgImage
        #else
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

/// Image helpers built on ImageIO so they behave the same on iOS, iPadOS and macOS.
enum ImageProcessing {
    /// Downscales and re-encodes an imported image so attachments stay small enough to sync quickly.
    static func preparedImageData(from data: Data, maxPixelSize: Int = 2048) -> Data? {
        guard let image = thumbnail(from: data, maxPixelSize: maxPixelSize) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Decodes an image at a reduced size, respecting its EXIF orientation.
    static func thumbnail(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

/// Renders a `CGImage` produced off the main thread, showing a placeholder until it's ready.
struct AsyncRenderedImage<Placeholder: View>: View {
    /// Changing the key re-renders the image.
    let key: AnyHashable
    let render: @Sendable () async -> CGImage?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
            } else {
                placeholder()
            }
        }
        .task(id: key) {
            let render = render
            image = await Task.detached(priority: .userInitiated) { await render() }.value
        }
    }
}
