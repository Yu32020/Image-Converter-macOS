import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
final class ImageJob: Identifiable, ObservableObject {
    let id = UUID()
    let input: ImageInput
    var url: URL { input.url }
    @Published var statusKey = "STATUS_PENDING"
    @Published var thumbnail: NSImage?
    @Published var outputURL: URL?
    @Published var errorDescription: String?

    private var thumbnailRequested = false

    init(input: ImageInput) { self.input = input }

    func loadThumbnail() async {
        guard !thumbnailRequested else { return }
        thumbnailRequested = true
        if let data = await ThumbnailWorker.shared.data(for: input) {
            thumbnail = NSImage(data: data)
        } else if Task.isCancelled {
            thumbnailRequested = false
        }
    }
}

@MainActor
final class ConverterViewModel: ObservableObject {
    @Published var jobs: [ImageJob] = []
    @Published var selectedFormat: OutputFormat = .jpeg
    @Published var isProcessing = false
    @Published var isImporting = false
    @Published var isCancelling = false
    @Published var progress = 0.0
    @Published var isDragging = false
    @Published var statusMessage: LocalizedStringKey = "STATUS_READY"
    @Published var importError: String?
    @Published var destinationFolder: URL?
    @AppStorage("selectedLanguage") var selectedLanguage = "system"

    var isBusy: Bool { isProcessing || isImporting }
    private let worker = ConversionWorker()
    private var conversionTask: Task<Void, Never>?

    func chooseImages() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }

    func importURLs(_ urls: [URL]) {
        guard !isBusy else { return }
        isImporting = true
        statusMessage = "STATUS_IMPORTING"
        Task { await finishImport(urls) }
    }

    func handleDroppedItems(providers: [NSItemProvider]) {
        guard !isBusy else { return }
        // Reserve the import state before awaiting providers; a conversion cannot take an incomplete queue.
        isImporting = true
        statusMessage = "STATUS_IMPORTING"
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                        continuation.resume(returning: object as? URL)
                    }
                }
                if let url { urls.append(url) }
            }
            await finishImport(urls)
        }
    }

    private func finishImport(_ urls: [URL]) async {
        let collection = await worker.collect(urls, excluding: Set(jobs.map(\.url)))
        jobs.append(contentsOf: collection.images.map(ImageJob.init))
        isImporting = false
        progress = 0
        if collection.images.isEmpty { statusMessage = "STATUS_NO_NEW_IMAGES" }
        else { statusMessage = "STATUS_ADDED_COUNT \(Int64(collection.images.count)) \(Int64(jobs.count))" }
        if !collection.errors.isEmpty { importError = collection.errors.joined(separator: "\n") }
    }

    func startConversion() {
        guard !isBusy, !jobs.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        convert(to: destination)
    }

    func convert(to destination: URL) {
        guard !isBusy, !jobs.isEmpty else { return }
        let destinationAccess = SecurityScopedAccess(destination)
        let snapshot = jobs
        let format = selectedFormat
        destinationFolder = destination
        isProcessing = true
        isCancelling = false
        progress = 0
        statusMessage = "STATUS_PREPARING"
        for job in snapshot {
            job.statusKey = "STATUS_QUEUED"
            job.outputURL = nil
            job.errorDescription = nil
        }
        conversionTask = Task {
            var succeeded = 0
            var failed = 0
            for (index, job) in snapshot.enumerated() {
                if Task.isCancelled { break }
                statusMessage = "STATUS_PROCESSING_PROGRESS \(Int64(index + 1)) \(Int64(snapshot.count)) \(job.url.lastPathComponent)"
                job.statusKey = "STATUS_PROCESSING"
                do {
                    job.outputURL = try await worker.convert(job.input, destination: destination, format: format)
                    job.statusKey = "STATUS_SUCCESS"
                    succeeded += 1
                } catch {
                    job.statusKey = "STATUS_FAILED"
                    job.errorDescription = error.localizedDescription
                    failed += 1
                }
                progress = Double(index + 1) / Double(snapshot.count)
            }
            let remaining = snapshot.filter { $0.statusKey == "STATUS_QUEUED" }
            for job in remaining { job.statusKey = "STATUS_CANCELLED" }
            if !remaining.isEmpty {
                statusMessage = "STATUS_CANCELLED_SUMMARY \(Int64(succeeded)) \(Int64(failed)) \(Int64(remaining.count))"
            } else if failed == 0 {
                statusMessage = "STATUS_COMPLETE_ALL_SUCCESS \(Int64(succeeded))"
            } else {
                statusMessage = "STATUS_COMPLETE_WITH_FAILURES \(Int64(succeeded)) \(Int64(failed))"
            }
            // Retain the chosen folder's sandbox grant until all writes have completed.
            withExtendedLifetime(destinationAccess) {}
            isProcessing = false
            isCancelling = false
            conversionTask = nil
        }
    }

    func cancelConversion() {
        guard isProcessing else { return }
        isCancelling = true
        conversionTask?.cancel()
        statusMessage = "STATUS_CANCELLING"
    }

    func remove(_ job: ImageJob) {
        guard !isBusy else { return }
        jobs.removeAll { $0.id == job.id }
        progress = 0
        statusMessage = jobs.isEmpty ? "STATUS_READY" : "STATUS_LIST_CHANGED"
    }

    func clearJobs() {
        guard !isBusy else { return }
        jobs.removeAll()
        progress = 0
        statusMessage = "STATUS_READY"
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ConverterViewModel()
    private let gradient = LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(gradient)
                VStack(alignment: .leading, spacing: 3) {
                    Text("APP_TITLE").font(.title2.bold())
                    Text("APP_SUBTITLE").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: viewModel.chooseImages) {
                    Label("BUTTON_ADD_IMAGES", systemImage: "plus")
                }
                .keyboardShortcut("o")
                .disabled(viewModel.isBusy)
            }

            if viewModel.jobs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(gradient)
                    Text(viewModel.isDragging ? "DROP_HERE_TITLE_DRAGGING" : "DROP_HERE_TITLE")
                        .font(.title2.weight(.semibold))
                    Text("DROP_HERE_SUBTITLE")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("BUTTON_BROWSE", action: viewModel.chooseImages)
                        .buttonStyle(.borderedProminent).disabled(viewModel.isBusy)
                    Text("FOLDER_IMPORT_HINT").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(viewModel.isDragging ? Color.accentColor : .secondary.opacity(0.25),
                                      style: StrokeStyle(lineWidth: 2, dash: [7]))
                }
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("LIST_TOTAL_COUNT \(Int64(viewModel.jobs.count))").font(.headline)
                        Spacer()
                        Button("BUTTON_CLEAR_LIST", action: viewModel.clearJobs).disabled(viewModel.isBusy)
                    }
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(viewModel.jobs) { job in
                                ImageJobRow(job: job, isBusy: viewModel.isBusy) { viewModel.remove(job) }
                            }
                        }
                        .padding(8)
                    }
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    if viewModel.isImporting { ProgressView().controlSize(.small) }
                    Text(viewModel.statusMessage).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(2).textSelection(.enabled)
                    Spacer()
                    if let destination = viewModel.destinationFolder, !viewModel.isProcessing {
                        Button { NSWorkspace.shared.open(destination) } label: {
                            Label("BUTTON_SHOW_OUTPUT", systemImage: "folder")
                        }
                    }
                }
                if viewModel.isProcessing {
                    ProgressView(value: viewModel.progress).tint(.accentColor)
                        .accessibilityLabel(Text("PROGRESS_LABEL"))
                }
                Divider()
                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OUTPUT_FORMAT_LABEL").font(.caption).foregroundStyle(.secondary)
                        Picker("OUTPUT_FORMAT_LABEL", selection: $viewModel.selectedFormat) {
                            ForEach(OutputFormat.allCases) { format in
                                Text(LocalizedStringKey(format.rawValue)).tag(format)
                            }
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(minWidth: 280)
                        .disabled(viewModel.isBusy)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LANGUAGE_LABEL").font(.caption).foregroundStyle(.secondary)
                        Picker("LANGUAGE_LABEL", selection: $viewModel.selectedLanguage) {
                            Text("LANGUAGE_SYSTEM").tag("system")
                            Text("English").tag("en")
                            Text("简体中文").tag("zh-Hans")
                        }
                        .labelsHidden().frame(width: 140)
                    }
                    Spacer(minLength: 0)
                    if viewModel.isProcessing {
                        Button(viewModel.isCancelling ? "BUTTON_CANCELLING" : "BUTTON_CANCEL", action: viewModel.cancelConversion)
                            .disabled(viewModel.isCancelling)
                            .help("CANCEL_HINT")
                    } else {
                        Button(action: viewModel.startConversion) {
                            Label("BUTTON_START", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(viewModel.isBusy || viewModel.jobs.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                Text("OUTPUT_SAFETY_HINT").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(minWidth: 820, minHeight: 560)
        .background(.background)
        .environment(\.locale, viewModel.selectedLanguage == "system" ? .autoupdatingCurrent : Locale(identifier: viewModel.selectedLanguage))
        .onDrop(of: [UTType.fileURL], isTargeted: $viewModel.isDragging) { providers in
            guard !viewModel.isBusy else { return false }
            viewModel.handleDroppedItems(providers: providers)
            return true
        }
        .alert("IMPORT_ERROR_TITLE", isPresented: Binding(
            get: { viewModel.importError != nil }, set: { if !$0 { viewModel.importError = nil } }
        )) { Button("BUTTON_OK", role: .cancel) {} } message: {
            Text(viewModel.importError ?? "")
        }
    }
}

struct ImageJobRow: View {
    @ObservedObject var job: ImageJob
    let isBusy: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = job.thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(job.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                    .help(job.url.path)
                if let error = job.errorDescription {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2).help(error)
                } else if let output = job.outputURL {
                    Text(output.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(job.url.deletingLastPathComponent().lastPathComponent)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if job.statusKey == "STATUS_PROCESSING" {
                ProgressView().controlSize(.small)
            } else {
                Text(LocalizedStringKey(job.statusKey)).font(.caption.weight(.medium))
                    .foregroundStyle(job.statusKey == "STATUS_FAILED" ? .red : job.statusKey == "STATUS_SUCCESS" ? .green : .secondary)
            }
            if let output = job.outputURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([output]) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless).help("BUTTON_REVEAL_FILE")
                .accessibilityLabel(Text("BUTTON_REVEAL_FILE"))
            }
            Button(action: remove) { Image(systemName: "xmark") }
                .buttonStyle(.borderless).disabled(isBusy).help("BUTTON_REMOVE")
                .accessibilityLabel(Text("BUTTON_REMOVE"))
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .task { await job.loadThumbnail() }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
