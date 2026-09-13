import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit

/// Catches layout regressions that assertions on model state cannot see: a row
/// whose artwork overflows its frame passes every other test we have.
///
/// References live in `__Snapshots__` beside the test that records them, found
/// through `#filePath` rather than the test bundle, so recording writes where
/// git can see it.
enum ViewSnapshot {
    /// Text metrics, system colours and corner rendering all change between
    /// iOS versions, so a reference recorded elsewhere fails for reasons that
    /// have nothing to do with our layout.
    static let pinnedMajorVersion = 26

    static var isPinnedRuntime: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == pinnedMajorVersion
    }

    /// Release dates format through `Locale.autoupdatingCurrent`, which the
    /// view gives no way to override, so "Jan 5, 2026" holds in one locale
    /// only. Another region skips these suites rather than failing on a date
    /// format that is correct.
    static var isPinnedLocale: Bool {
        Locale.current.identifier.hasPrefix("en_US")
    }

    static var isSupported: Bool {
        isPinnedRuntime && isPinnedLocale
    }

    /// Set `SOONR_RECORD_SNAPSHOTS=1` to overwrite references instead of
    /// comparing. Recording always fails the test, so a run left in recording
    /// mode cannot pass in CI.
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["SOONR_RECORD_SNAPSHOTS"] == "1"
    }

    /// Antialiasing along glyph edges shifts a channel by a few units between
    /// minor iOS releases; a layout change moves whole blocks of pixels.
    private static let channelTolerance = 16
    private static let differingPixelTolerance = 0.01

    @MainActor
    static func expect<V: View>(
        _ view: V,
        named name: String,
        size: CGSize,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        filePath: StaticString = #filePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let rendered = try render(
            view,
            size: size,
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize
        )

        let directory = referenceDirectory(forTestAt: filePath)
        let reference = directory.appending(path: "\(name).png")
        let failure = directory.appending(path: "\(name).actual.png")
        try? FileManager.default.removeItem(at: failure)

        guard isRecording == false else {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try pngData(of: rendered).write(to: reference)
            Issue.record(
                """
                Recorded \(name).png. Review it, then unset SOONR_RECORD_SNAPSHOTS \
                and run again.
                """,
                sourceLocation: sourceLocation
            )
            return
        }

        guard let referenceImage = UIImage(contentsOfFile: reference.path())?.cgImage else {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try pngData(of: rendered).write(to: failure)
            Issue.record(
                """
                No reference for \(name). Rendered it to \(failure.path()); record \
                references with SOONR_RECORD_SNAPSHOTS=1.
                """,
                sourceLocation: sourceLocation
            )
            return
        }

        let difference = try compare(rendered, referenceImage)
        guard difference.isWithinTolerance else {
            try pngData(of: rendered).write(to: failure)
            Issue.record(
                """
                \(name) does not match its reference: \(difference.summary). \
                Rendered output is at \(failure.path()).
                """,
                sourceLocation: sourceLocation
            )
            return
        }
    }

    @MainActor
    private static func render<V: View>(
        _ view: V,
        size: CGSize,
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize
    ) throws -> CGImage {
        let renderer = ImageRenderer(
            content:
                view
                .frame(width: size.width, height: size.height)
                // SwiftUI's own background style, which follows the color
                // scheme below; a UIKit dynamic colour would resolve against
                // the renderer's traits instead and leave dark references
                // with a light background.
                .background(.background)
                .environment(\.colorScheme, colorScheme)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        // Fixed, so a reference does not depend on the simulator's scale.
        renderer.scale = 2

        guard let image = renderer.cgImage else {
            throw SnapshotError.renderFailed
        }

        return image
    }

    private static func referenceDirectory(forTestAt filePath: StaticString) -> URL {
        URL(filePath: "\(filePath)")
            .deletingLastPathComponent()
            .appending(path: "__Snapshots__")
    }

    private static func pngData(of image: CGImage) throws -> Data {
        guard let data = UIImage(cgImage: image).pngData() else {
            throw SnapshotError.encodingFailed
        }

        return data
    }

    /// Draws both into the same bitmap layout first, so the comparison never
    /// depends on how either image happens to be stored.
    private static func compare(_ image: CGImage, _ reference: CGImage) throws -> Difference {
        guard image.width == reference.width, image.height == reference.height else {
            return Difference(
                size: CGSize(width: image.width, height: image.height),
                referenceSize: CGSize(width: reference.width, height: reference.height),
                differingPixels: 0,
                totalPixels: 0
            )
        }

        let pixels = try normalizedPixels(of: image)
        let referencePixels = try normalizedPixels(of: reference)
        let totalPixels = image.width * image.height

        var differingPixels = 0
        for pixel in 0..<totalPixels {
            let start = pixel * 4
            for channel in 0..<4 {
                let delta = abs(
                    Int(pixels[start + channel]) - Int(referencePixels[start + channel]))
                if delta > channelTolerance {
                    differingPixels += 1
                    break
                }
            }
        }

        return Difference(
            size: CGSize(width: image.width, height: image.height),
            referenceSize: CGSize(width: reference.width, height: reference.height),
            differingPixels: differingPixels,
            totalPixels: totalPixels
        )
    }

    private static func normalizedPixels(of image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw SnapshotError.comparisonFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private struct Difference {
        let size: CGSize
        let referenceSize: CGSize
        let differingPixels: Int
        let totalPixels: Int

        var isWithinTolerance: Bool {
            guard size == referenceSize else {
                return false
            }

            return differingRatio <= ViewSnapshot.differingPixelTolerance
        }

        var differingRatio: Double {
            guard totalPixels > 0 else {
                return 1
            }

            return Double(differingPixels) / Double(totalPixels)
        }

        var summary: String {
            guard size == referenceSize else {
                return
                    "it is \(Int(size.width))x\(Int(size.height)), the reference is "
                    + "\(Int(referenceSize.width))x\(Int(referenceSize.height))"
            }

            let percentage = (differingRatio * 100).formatted(.number.precision(.fractionLength(2)))
            return "\(differingPixels) of \(totalPixels) pixels differ (\(percentage)%)"
        }
    }

    enum SnapshotError: Error {
        case renderFailed
        case encodingFailed
        case comparisonFailed
    }
}
