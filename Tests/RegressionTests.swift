import AppKit
import CoreImage
import Foundation
import ImageIO

func report(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw TestFailure(description: message) }
}

func fixture(at url: URL, orientation: Int? = nil) throws {
    let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 256,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    let image = context.makeImage()!
    let type = orientation == nil ? "public.png" : "public.jpeg"
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
    var properties: [CFString: Any] = [:]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    try expect(CGImageDestinationFinalize(destination), "Create fixture")
}

func decoded(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw TestFailure(description: "Output does not decode: \(url.path)")
    }
    return image
}

func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    let context = CGContext(data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    let offset = (y * image.width + x) * 4
    return Array(UnsafeBufferPointer(start: data + offset, count: 4))
}

@main
struct RegressionTests {
    @MainActor
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    static func run() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        report("Fixtures: \(root.path)")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let inputs = root.appendingPathComponent("inputs", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        try fm.createDirectory(at: inputs, withIntermediateDirectories: true)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let source = inputs.appendingPathComponent("透明 sample.png")
        try fixture(at: source)
        let originalBytes = try Data(contentsOf: source)
        let upper = inputs.appendingPathComponent("UPPER.PNG")
        try fixture(at: upper)
        let fakeDirectory = inputs.appendingPathComponent("folder.png", isDirectory: true)
        try fm.createDirectory(at: fakeDirectory, withIntermediateDirectories: true)
        try fixture(at: fakeDirectory.appendingPathComponent("nested.png"))
        try fixture(at: inputs.appendingPathComponent(".hidden.png"))
        let alias = root.appendingPathComponent("alias.png")
        try fm.createSymbolicLink(at: alias, withDestinationURL: source)
        let collected = InputCollector.collect([source, inputs, source, alias])
        try expect(collected.errors.isEmpty, "Unexpected import error")
        try expect(collected.images.count == 2, "Same-batch duplicates, aliases, image-named directories, hidden files or nested files")
        try expect(InputCollector.collect([source, inputs], excluding: Set(collected.images.map(\.url))).images.isEmpty,
                   "Existing queue deduplication")
        report("PASS import: duplicates, aliases, uppercase extensions, hidden files, directories and shallow folders")

        for format in OutputFormat.allCases {
            let result = try ImageProcessor.convert(source: source, destinationFolder: output, format: format)
            let image = try decoded(result)
            try expect(image.width == 64 && image.height == 32, "\(format) dimensions")
            if format == .jpeg {
                let rgba = pixel(image, x: 56, y: 16)
                try expect(rgba[0] > 245 && rgba[1] > 245 && rgba[2] > 245 && rgba[3] == 255,
                           "Transparent JPEG pixels must become white, got \(rgba)")
            }
            if format == .png || format == .tiff {
                try expect(pixel(image, x: 56, y: 16)[3] == 0, "\(format) must preserve alpha")
            }
            report("PASS \(format.fileExtension): decodes, dimensions and alpha behavior")
        }

        let inPlace = try ImageProcessor.convert(source: source, destinationFolder: inputs, format: .png)
        try expect(inPlace.lastPathComponent == "透明 sample (1).png", "Same-folder source collision numbering")
        try expect(try Data(contentsOf: source) == originalBytes, "Original was modified")
        let firstBytes = try Data(contentsOf: inPlace)
        let again = try ImageProcessor.convert(source: source, destinationFolder: inputs, format: .png)
        try expect(again.lastPathComponent == "透明 sample (2).png", "Repeated conversion numbering")
        try expect(try Data(contentsOf: inPlace) == firstBytes, "Earlier output was modified")

        let symlinkOutput = root.appendingPathComponent("symlinks", isDirectory: true)
        try fm.createDirectory(at: symlinkOutput, withIntermediateDirectories: true)
        let sentinel = root.appendingPathComponent("sentinel")
        let sentinelBytes = Data("must not overwrite".utf8)
        try sentinelBytes.write(to: sentinel)
        try fm.createSymbolicLink(at: symlinkOutput.appendingPathComponent("透明 sample.jpg"), withDestinationURL: sentinel)
        try fm.createSymbolicLink(at: symlinkOutput.appendingPathComponent("透明 sample (1).jpg"), withDestinationURL: root.appendingPathComponent("missing"))
        let linkResult = try ImageProcessor.convert(source: source, destinationFolder: symlinkOutput, format: .jpeg)
        try expect(linkResult.lastPathComponent == "透明 sample (2).jpg", "Existing or dangling symlinks must not be overwritten")
        try expect(try Data(contentsOf: sentinel) == sentinelBytes, "Symlink target modified")
        report("PASS no-overwrite: original, repeated results, existing and dangling symlinks")

        let concurrent = root.appendingPathComponent("concurrent", isDirectory: true)
        try fm.createDirectory(at: concurrent, withIntermediateDirectories: true)
        let results = try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try ImageProcessor.convert(source: source, destinationFolder: concurrent, format: .png)
                }
            }
            var urls: [URL] = []
            for try await result in group { urls.append(result) }
            return urls
        }
        try expect(Set(results).count == 8, "Concurrent conversions collided")
        for result in results { _ = try decoded(result) }
        report("PASS atomic publication: 8 concurrent same-name conversions remain unique")

        let oriented = inputs.appendingPathComponent("rotated.jpg")
        try fixture(at: oriented, orientation: 6)
        let rotated = try ImageProcessor.convert(source: oriented, destinationFolder: output, format: .png)
        let rotatedImage = try decoded(rotated)
        try expect(rotatedImage.width == 32 && rotatedImage.height == 64, "EXIF orientation must be applied exactly once")
        let rotatedSource = CGImageSourceCreateWithURL(rotated as CFURL, nil)!
        let rotatedProperties = CGImageSourceCopyPropertiesAtIndex(rotatedSource, 0, nil)! as NSDictionary
        let finalOrientation = rotatedProperties[kCGImagePropertyOrientation] as? Int ?? 1
        try expect(finalOrientation == 1, "Output must not retain old orientation")
        report("PASS orientation: EXIF 6 applied once")

        let corrupt = inputs.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: corrupt)
        do {
            _ = try ImageProcessor.convert(source: corrupt, destinationFolder: output, format: .png)
            throw TestFailure(description: "Corrupt image accepted")
        } catch is ConversionError {}
        do {
            _ = try ImageProcessor.convert(source: source, destinationFolder: sentinel, format: .png)
            throw TestFailure(description: "Non-directory destination accepted")
        } catch is ConversionError {}
        try expect(!fm.contentsOfDirectory(atPath: output.path).contains(where: { $0.hasPrefix(".image-converter-") }), "Temporary files leaked")
        try expect(!fm.fileExists(atPath: output.appendingPathComponent("corrupt.png").path), "Failed output was published")
        report("PASS error cleanup: corrupt source and invalid destination")

        let model = ConverterViewModel()
        model.handleDroppedItems(providers: [NSItemProvider(object: source as NSURL), NSItemProvider(object: corrupt as NSURL)])
        try expect(model.isImporting, "Import busy state must start synchronously")
        model.convert(to: output)
        model.clearJobs()
        try expect(!model.isProcessing, "Conversion must not race import")
        while model.isImporting { try await Task.sleep(for: .milliseconds(10)) }
        try expect(model.jobs.count == 2, "Import produced wrong queue")
        model.importURLs([source])
        while model.isImporting { try await Task.sleep(for: .milliseconds(10)) }
        try expect(model.jobs.count == 2, "Repeated import duplicated jobs")
        model.convert(to: output)
        model.cancelConversion()
        while model.isProcessing { try await Task.sleep(for: .milliseconds(10)) }
        try expect(model.jobs.allSatisfy { $0.statusKey == "STATUS_CANCELLED" }, "Immediate cancellation must leave pending files unconverted")
        model.selectedFormat = .png
        model.convert(to: output)
        model.importURLs([upper])
        model.remove(model.jobs[0])
        model.clearJobs()
        try expect(model.jobs.count == 2 && !model.isImporting, "Busy queue mutated")
        while model.isProcessing { try await Task.sleep(for: .milliseconds(10)) }
        try expect(model.jobs[0].statusKey == "STATUS_SUCCESS" && model.jobs[0].outputURL != nil, "View model lost successful output")
        try expect(model.jobs[1].statusKey == "STATUS_FAILED" && model.jobs[1].errorDescription != nil, "View model lost failure detail")
        try expect(model.progress == 1, "Batch progress incomplete")
        model.remove(model.jobs[1])
        try expect(model.jobs.count == 1, "Remove job")
        model.clearJobs()
        try expect(model.jobs.isEmpty && model.progress == 0, "Clear queue")
        report("PASS view model: import/convert exclusion, cancellation, retry, mixed failures, queue locks and removal")
        report("ALL REGRESSION CHECKS PASSED")
        report("Fixtures: \(root.path)")
    }
}
