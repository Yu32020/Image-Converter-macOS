import CoreImage
import Foundation
import ImageIO
import Darwin

// This file has no UI dependency; the regression runner uses the same conversion code.
enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg = "FORMAT_JPEG"
    case png = "FORMAT_PNG"
    case tiff = "FORMAT_TIFF"
    case heic = "FORMAT_HEIC"

    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .tiff: "tiff"
        case .heic: "heic"
        }
    }
}

enum ConversionError: Error, LocalizedError {
    case unreadableImage
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .unreadableImage: NSLocalizedString("ERROR_UNREADABLE_IMAGE", comment: "")
        case .invalidDestination: NSLocalizedString("ERROR_INVALID_DESTINATION", comment: "")
        }
    }
}

/// Keep the user's file/folder grant alive for queued files and background work.
final class SecurityScopedAccess: @unchecked Sendable {
    let url: URL
    private let started: Bool

    init(_ url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if started { url.stopAccessingSecurityScopedResource() }
    }
}

struct ImageInput: Sendable {
    let url: URL
    let access: SecurityScopedAccess
}

struct InputCollection: Sendable {
    var images: [ImageInput] = []
    var errors: [String] = []
}

enum InputCollector {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "nef", "cr2", "cr3", "raw", "dng",
        "heic", "heif", "arw", "orf", "pef"
    ]

    /// Folders intentionally include their immediate visible image files only.
    static func collect(_ urls: [URL], excluding: Set<URL> = []) -> InputCollection {
        var result = InputCollection()
        var seen = Set(excluding.map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isPackageKey]

        func append(_ url: URL, access: SecurityScopedAccess) throws {
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            guard supportedExtensions.contains(canonical.pathExtension.lowercased()),
                  try canonical.resourceValues(forKeys: keys).isRegularFile == true,
                  seen.insert(canonical).inserted else { return }
            result.images.append(ImageInput(url: canonical, access: access))
        }

        for url in urls where url.isFileURL {
            let access = SecurityScopedAccess(url)
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isDirectory == true, values.isPackage != true {
                    let children = try FileManager.default.contentsOfDirectory(
                        at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
                    ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    for child in children {
                        do { try append(child, access: access) }
                        catch { result.errors.append("\(child.lastPathComponent): \(error.localizedDescription)") }
                    }
                } else {
                    try append(url, access: access)
                }
            } catch {
                result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }
}

enum ImageProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func convert(source: URL, destinationFolder: URL, format: OutputFormat) throws -> URL {
        try autoreleasepool {
            guard try destinationFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw ConversionError.invalidDestination
            }
            guard let image = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]),
                  !image.extent.isEmpty, !image.extent.isInfinite else {
                throw ConversionError.unreadableImage
            }

            // Encode separately so an error cannot damage an original or leave a partial final file.
            let temporary = destinationFolder.appendingPathComponent(".image-converter-\(UUID().uuidString).\(format.fileExtension)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            switch format {
            case .jpeg:
                // JPEG has no alpha channel. Use a predictable white background instead of black.
                let background = CIImage(color: .white).cropped(to: image.extent)
                try context.writeJPEGRepresentation(of: image.composited(over: background), to: temporary,
                    colorSpace: colorSpace,
                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9])
            case .png:
                try context.writePNGRepresentation(of: image, to: temporary, format: .RGBA8,
                    colorSpace: colorSpace, options: [:])
            case .tiff:
                try context.writeTIFFRepresentation(of: image, to: temporary, format: .RGBA8,
                    colorSpace: colorSpace, options: [:])
            case .heic:
                try context.writeHEIFRepresentation(of: image, to: temporary, format: .RGBA8,
                    colorSpace: colorSpace,
                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85])
            }

            let baseName = source.deletingPathExtension().lastPathComponent
            var suffix = 0
            while true {
                let name = suffix == 0 ? baseName : "\(baseName) (\(suffix))"
                let output = destinationFolder.appendingPathComponent("\(name).\(format.fileExtension)")
                // RENAME_EXCL atomically refuses existing files, directories and symlinks, including
                // a file another converter creates after our encoding has started.
                let result = temporary.withUnsafeFileSystemRepresentation { from in
                    output.withUnsafeFileSystemRepresentation { to in
                        renamex_np(from, to, UInt32(RENAME_EXCL))
                    }
                }
                if result == 0 { return output }
                let code = errno
                if code == EEXIST { suffix += 1; continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: output.path])
            }
        }
    }

    static func thumbnailData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceThumbnailMaxPixelSize: 120,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

actor ConversionWorker {
    func convert(_ input: ImageInput, destination: URL, format: OutputFormat) throws -> URL {
        try ImageProcessor.convert(source: input.url, destinationFolder: destination, format: format)
    }

    func collect(_ urls: [URL], excluding: Set<URL>) -> InputCollection {
        InputCollector.collect(urls, excluding: excluding)
    }
}

/// One thumbnail decoder at a time, even when a large RAW queue is scrolled rapidly.
actor ThumbnailWorker {
    static let shared = ThumbnailWorker()

    func data(for input: ImageInput) -> Data? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            withExtendedLifetime(input.access) { ImageProcessor.thumbnailData(for: input.url) }
        }
    }
}
