import SwiftUI
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import Combine

// MARK: - Models

enum OutputFormat: String, CaseIterable, Identifiable {
    case jpeg = "FORMAT_JPEG"
    case png = "FORMAT_PNG"
    case tiff = "FORMAT_TIFF"
    case heic = "FORMAT_HEIC"

    var id: String { self.rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .heic: return "heic"
        }
    }
}

class ImageJob: Identifiable, Hashable, ObservableObject {
    let id = UUID()
    let url: URL
    @Published var statusKey: String = "STATUS_PENDING"
    
    lazy var thumbnail: NSImage? = ImageJob.generateThumbnail(url: url)

    init(url: URL) {
        self.url = url
    }
    
    static func generateThumbnail(url: URL) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [NSString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize as NSString: 120,
            kCGImageSourceCreateThumbnailFromImageAlways as NSString: true,
            kCGImageSourceCreateThumbnailWithTransform as NSString: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ImageJob, rhs: ImageJob) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Image Processor

struct ImageProcessor {
    private static let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])

    static func convertImage(job: ImageJob, destinationFolder: URL, format: OutputFormat) -> Bool {
        var success = false
        
        autoreleasepool {
            guard let ciImage = CIImage(contentsOf: job.url, options: [.applyOrientationProperty: true]) else {
                print("❌ Error loading image: \(job.url.path)")
                return
            }

            let baseName = job.url.deletingPathExtension().lastPathComponent
            let outputURL = destinationFolder.appendingPathComponent("\(baseName).\(format.fileExtension)")

            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

            do {
                switch format {
                case .jpeg:
                    try ciContext.writeJPEGRepresentation(of: ciImage, to: outputURL, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9])
                case .png:
                    try ciContext.writePNGRepresentation(of: ciImage, to: outputURL, format: .RGBA8, colorSpace: colorSpace, options: [:])
                case .tiff:
                    try ciContext.writeTIFFRepresentation(of: ciImage, to: outputURL, format: .RGBA8, colorSpace: colorSpace, options: [:])
                case .heic:
                     try ciContext.writeHEIFRepresentation(of: ciImage, to: outputURL, format: .RGBA8, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85])
                }
                success = true
            } catch {
                print("❌ Failed to save image at \(outputURL.path). Error: \(error)")
            }
        }
        return success
    }
}

// MARK: - ViewModel

@MainActor
class ConverterViewModel: ObservableObject {
    @Published var jobs: [ImageJob] = []
    @Published var selectedFormat: OutputFormat = .jpeg
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var isDragging = false
    @Published var statusMessage: LocalizedStringKey = "STATUS_READY"
    
    @AppStorage("selectedLanguage") var selectedLanguage: String = "system"

    private let supportedExtensions = ["jpg", "jpeg", "png", "tiff", "tif", "nef", "cr2", "cr3", "raw", "dng", "heic", "arw", "orf", "pef"]
    
    func handleDroppedItems(providers: [NSItemProvider]) {
        guard !isProcessing else { return }

        Task {
            var urls: [URL] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    do {
                        let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
                        
                        if let url = item as? URL {
                            urls.append(url)
                        } else if let data = item as? Data {
                            if let urlString = String(data: data, encoding: .utf8),
                               let url = URL(string: urlString) {
                                urls.append(url)
                            }
                        }
                    } catch {
                        print("Error loading dropped item: \(error)")
                    }
                }
            }
            self.processInputURLs(urls)
        }
    }
    
    private func processInputURLs(_ urls: [URL]) {
        var newJobs: [ImageJob] = []
        let existingURLs = Set(jobs.map { $0.url })
        
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            
            var isDir: ObjCBool = false
            
            let filePath: String
            if #available(macOS 13.0, *) {
                filePath = standardizedURL.path(percentEncoded: false)
            } else {
                filePath = standardizedURL.path
            }
            
            if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir) {
                if isDir.boolValue {
                    newJobs.append(contentsOf: scanDirectory(standardizedURL, existingURLs: existingURLs))
                } else {
                    if isSupportedFileType(standardizedURL.pathExtension) && !existingURLs.contains(standardizedURL) {
                        newJobs.append(ImageJob(url: standardizedURL))
                    }
                }
            }
        }
        if !newJobs.isEmpty {
            jobs.append(contentsOf: newJobs)
            let addedCount = Int64(newJobs.count)
            let totalCount = Int64(jobs.count)
            statusMessage = "STATUS_ADDED_COUNT \(addedCount) \(totalCount)"
        }
    }
    
    private func scanDirectory(_ directoryURL: URL, existingURLs: Set<URL>) -> [ImageJob] {
        var foundJobs: [ImageJob] = []
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for url in contents {
                if isSupportedFileType(url.pathExtension) && !existingURLs.contains(url) {
                    foundJobs.append(ImageJob(url: url))
                }
            }
        } catch {
            print("Error scanning directory: \(error)")
        }
        return foundJobs
    }

    private func isSupportedFileType(_ fileExtension: String) -> Bool {
        return supportedExtensions.contains(fileExtension.lowercased())
    }

    func startConversion() {
        guard !jobs.isEmpty else {
            statusMessage = "STATUS_ADD_IMAGES_FIRST"
            return
        }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let destinationFolder = panel.url {
            isProcessing = true
            progress = 0.0
            statusMessage = "STATUS_PREPARING"
            
            for job in jobs {
                job.statusKey = "STATUS_QUEUED"
            }
            
            processJobs(destinationFolder: destinationFolder)
        }
    }

    private func processJobs(destinationFolder: URL) {
        let jobsSnapshot = self.jobs
        let currentFormat = self.selectedFormat
        
        Task.detached(priority: .userInitiated) {
            let totalJobsCount = Int64(jobsSnapshot.count)
            var completedCount = Int64(0)
            
            for (index, job) in jobsSnapshot.enumerated() {
                let currentIndex = Int64(index + 1)
                
                await MainActor.run {
                    let fileName = job.url.lastPathComponent
                    self.statusMessage = "STATUS_PROCESSING_PROGRESS \(currentIndex) \(totalJobsCount) \(fileName)"
                    job.statusKey = "STATUS_PROCESSING"
                }

                let result = ImageProcessor.convertImage(job: job, destinationFolder: destinationFolder, format: currentFormat)

                if result { completedCount += 1 }
                await MainActor.run {
                    job.statusKey = result ? "STATUS_SUCCESS" : "STATUS_FAILED"
                    self.progress = Double(currentIndex) / Double(totalJobsCount)
                }
            }

            await MainActor.run {
                self.isProcessing = false
                let failedCount = totalJobsCount - completedCount
                
                if failedCount == 0 {
                    self.statusMessage = "STATUS_COMPLETE_ALL_SUCCESS \(completedCount)"
                } else {
                    self.statusMessage = "STATUS_COMPLETE_WITH_FAILURES \(completedCount) \(failedCount)"
                }
            }
        }
    }
    
    func clearJobs() {
        if !isProcessing {
            jobs.removeAll()
            progress = 0.0
            statusMessage = "STATUS_READY"
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var viewModel = ConverterViewModel()
    
    let vibrantGradient = LinearGradient(
        gradient: Gradient(colors: [Color.blue, Color.purple]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var locale: Locale {
        if viewModel.selectedLanguage == "system" {
            return Locale.autoupdatingCurrent
        } else {
            return Locale(identifier: viewModel.selectedLanguage)
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            if viewModel.isDragging {
                vibrantGradient
                    .opacity(0.15)
                    .ignoresSafeArea()
            }

            VStack(spacing: 15) {
                HeaderView()
                
                if viewModel.jobs.isEmpty {
                    DropZoneView(viewModel: viewModel, vibrantGradient: vibrantGradient)
                } else {
                    ImageListView(viewModel: viewModel)
                }
                
                ControlPanelView(viewModel: viewModel, vibrantGradient: vibrantGradient)
            }
            .padding(20)
            .frame(minWidth: 780, maxWidth: .infinity, minHeight: 550, maxHeight: .infinity)
            .animation(.spring(), value: viewModel.jobs.isEmpty)
        }
        .environment(\.locale, locale)
        .onDrop(of: [UTType.fileURL], delegate: FileDropDelegate(viewModel: viewModel))
        .animation(.easeInOut, value: viewModel.isDragging)
    }
}

struct HeaderView: View {
    var body: some View {
        HStack {
            Text("APP_TITLE")
                .font(.largeTitle)
                .fontWeight(.heavy)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.top, 10)
    }
}

struct DropZoneView: View {
    @ObservedObject var viewModel: ConverterViewModel
    let vibrantGradient: LinearGradient
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 90))
                .foregroundStyle(vibrantGradient)
                .opacity(viewModel.isDragging ? 1.0 : 0.8)
            
            Text(viewModel.isDragging ? "DROP_HERE_TITLE_DRAGGING" : "DROP_HERE_TITLE")
                .font(.title)
                .fontWeight(.bold)
            
            Text("DROP_HERE_SUBTITLE")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .popover, blendingMode: .withinWindow)
                .opacity(0.5)
        )
        .cornerRadius(30)
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(viewModel.isDragging ? Color.purple : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 4, dash: [15]))
        )
        .scaleEffect(viewModel.isDragging ? 1.03 : 1.0)
    }
}

struct ImageListView: View {
    @ObservedObject var viewModel: ConverterViewModel
    
    var body: some View {
        VStack {
            HStack {
                Text("LIST_TITLE")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                
                Text("LIST_TOTAL_COUNT \(Int64(viewModel.jobs.count))")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if !viewModel.isProcessing {
                    Button(action: viewModel.clearJobs) {
                        Image(systemName: "trash.fill")
                        Text("BUTTON_CLEAR_LIST")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 10)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.jobs) { job in
                       ImageJobRow(job: job)
                    }
                }
                .padding(5)
            }
            .background(Color.black.opacity(0.05))
            .cornerRadius(15)
        }
    }
}

struct ImageJobRow: View {
    @ObservedObject var job: ImageJob
    
    var body: some View {
        HStack {
            if let thumbnail = job.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                Image(systemName: "photo.artframe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .padding(10)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(job.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(job.url.pathExtension.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if job.statusKey == "STATUS_PROCESSING" {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Text(LocalizedStringKey(job.statusKey))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor(job.statusKey))
            }
        }
        .padding(10)
        .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
        .cornerRadius(12)
    }
    
    func statusColor(_ statusKey: String) -> Color {
        if statusKey == "STATUS_SUCCESS" { return .green }
        if statusKey == "STATUS_FAILED" { return .red }
        if statusKey == "STATUS_QUEUED" || statusKey == "STATUS_PENDING" { return .gray }
        return .primary
    }
}

struct ControlPanelView: View {
    @ObservedObject var viewModel: ConverterViewModel
    let vibrantGradient: LinearGradient

    var body: some View {
        VStack(spacing: 15) {
            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(minHeight: 20)
                .multilineTextAlignment(.center)
                .animation(.easeInOut, value: viewModel.statusMessage)
            
            if viewModel.isProcessing {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(GradientProgressStyle(gradient: vibrantGradient))
                    .padding(.horizontal, 5)
                    .transition(.opacity)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("OUTPUT_FORMAT_LABEL").font(.headline)
                    Picker("Output Format:", selection: $viewModel.selectedFormat) {
                        ForEach(OutputFormat.allCases) { format in
                            Text(LocalizedStringKey(format.rawValue)).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(SegmentedPickerStyle())
                    .disabled(viewModel.isProcessing)
                }
                
                VStack(alignment: .leading) {
                    Text("LANGUAGE_LABEL").font(.headline)
                    Picker("Language", selection: $viewModel.selectedLanguage) {
                        Text("LANGUAGE_SYSTEM").tag("system")
                        Text("English").tag("en")
                        Text("简体中文").tag("zh-Hans")
                    }
                    .labelsHidden()
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 220)
                    .disabled(viewModel.isProcessing)
                }

                Spacer()

                Button(action: {
                    viewModel.startConversion()
                }) {
                    HStack {
                        Image(systemName: viewModel.isProcessing ? "hourglass.bottomhalf.filled" : "play.fill")
                        Text(viewModel.isProcessing ? "BUTTON_PROCESSING" : "BUTTON_START")
                    }
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 30)
                    .background(viewModel.isProcessing ? LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing) : vibrantGradient)
                    .cornerRadius(15)
                    .shadow(color: viewModel.isProcessing ? Color.clear : Color.purple.opacity(0.5), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.isProcessing || viewModel.jobs.isEmpty)
            }
        }
        .padding(.top, 10)
        .animation(.spring(), value: viewModel.isProcessing)
    }
}

// MARK: - Helpers

struct GradientProgressStyle: ProgressViewStyle {
    var gradient: LinearGradient
    var backgroundColor = Color.primary.opacity(0.2)
    var height = 8.0

    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2.0)
                    .fill(backgroundColor)
                
                RoundedRectangle(cornerRadius: height / 2.0)
                    .fill(gradient)
                    .frame(width: geometry.size.width * CGFloat(fractionCompleted))
            }
        }
        .frame(height: height)
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

@MainActor
struct FileDropDelegate: DropDelegate {
    let viewModel: ConverterViewModel

    func performDrop(info: DropInfo) -> Bool {
        viewModel.isDragging = false
        
        let providers = info.itemProviders(for: [UTType.fileURL.identifier])
        
        if !providers.isEmpty && !viewModel.isProcessing {
            viewModel.handleDroppedItems(providers: providers)
            return true
        }
        return false
    }

    func dropEntered(info: DropInfo) {
        if !viewModel.isProcessing {
            viewModel.isDragging = true
        }
    }

    func dropExited(info: DropInfo) {
        viewModel.isDragging = false
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
