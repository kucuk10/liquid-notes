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

    /// The pixel dimensions of encoded image data, or `.zero` if they can't be read.
    static func pixelSize(of data: Data) -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else { return .zero }
        // EXIF orientations 5–8 are rotated by 90°.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Prepares every image that can be decoded, skipping the rest.
    static func preparedImages(from items: [Data]) -> [Data] {
        items.compactMap { preparedImageData(from: $0) }
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

/// An image dragged in from Photos, Files, Safari or another app.
struct DroppedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { DroppedImage(data: $0) }
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
