//
//  SettingsView.swift
//  Clop
//
//  Created by Alin Panaitiu on 10.07.2023.
//

import Defaults
import Foundation
import LaunchAtLogin
import Lowtech
import os
import SwiftUI
import System

private let log = Logger(subsystem: LOG_SUBSYSTEM, category: "SettingsView")

let TEXT_FIELD_OFFSET: CGFloat = if #available(macOS 15.0, *) {
    4
} else {
    0
}
let TEXT_FIELD_SCALE: CGFloat = if #available(macOS 15.0, *) {
    1.1
} else {
    1.0
}
let TEXT_FIELD_WIDTH: CGFloat = 550

extension String: @retroactive Identifiable {
    public var id: String {
        self
    }
}

let NOT_ALLOWED_TO_WATCH = [FilePath.clopBackups, FilePath.images, FilePath.videos, FilePath.forResize, FilePath.conversions, FilePath.downloads].map(\.portablePath)

import Combine

class TextDebounce: ObservableObject {
    init(for time: DispatchQueue.SchedulerTimeType.Stride) {
        $text
            .debounce(for: time, scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, value != debouncedText else {
                    return
                }
                DirListView.shouldSave = true
                debouncedText = value
            }
            .store(in: &subscriptions)
    }

    @Published var debouncedText = ""
    @Published var text = ""

    private var subscriptions = Set<AnyCancellable>()
}

// MARK: - SidebarHue

/// A muted, earthy sidebar colour with a light/dark pair: deeper on the light
/// sidebar, lifted on the dark one so the glyph keeps its weight either way.
/// Skin / stone / clay / sage / terracotta tones instead of saturated system
/// colours, shared across the lowtechguys settings sidebars (keep rcmd, Lunar,
/// Cling, Clop, Pipiri, Crank in step when the palette changes).
struct SidebarHue {
    static let sage = rgb(0.39, 0.49, 0.26, 0.60, 0.66, 0.50)
    static let dustyBlue = rgb(0.24, 0.43, 0.63, 0.53, 0.64, 0.75)
    static let periwinkle = rgb(0.41, 0.37, 0.68, 0.62, 0.60, 0.80)
    static let terracotta = rgb(0.74, 0.35, 0.23, 0.82, 0.52, 0.40)
    static let skin = rgb(0.74, 0.47, 0.30, 0.80, 0.64, 0.52)
    static let plum = rgb(0.58, 0.30, 0.55, 0.68, 0.55, 0.67)
    static let mutedTeal = rgb(0.15, 0.50, 0.45, 0.47, 0.68, 0.63)
    static let clay = rgb(0.63, 0.40, 0.24, 0.72, 0.57, 0.46)
    static let stone = rgb(0.45, 0.43, 0.37, 0.66, 0.64, 0.57)
    static let ochre = rgb(0.78, 0.56, 0.16, 0.83, 0.68, 0.40)
    static let dustyRose = rgb(0.76, 0.39, 0.40, 0.80, 0.60, 0.58)

    let light: Color
    let dark: Color

    func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }

    private static func rgb(_ lr: Double, _ lg: Double, _ lb: Double, _ dr: Double, _ dg: Double, _ db: Double) -> SidebarHue {
        SidebarHue(
            light: Color(.sRGB, red: lr, green: lg, blue: lb),
            dark: Color(.sRGB, red: dr, green: dg, blue: db)
        )
    }

}

// MARK: - SidebarIcon

/// The category glyph as a soft tinted tile: the earthy hue drives both the
/// glyph and a low-opacity same-hue background. `.resizable` into a fixed inner
/// frame keeps every glyph one size with a consistent inset from the tile edge.
struct SidebarIcon: View {
    let symbol: String
    let hue: SidebarHue
    var dimmed = false

    var body: some View {
        let color = hue.color(for: scheme)
        let tileOpacity = (scheme == .dark ? 0.22 : 0.15) * (dimmed ? 0.7 : 1)
        SwiftUI.Image(systemName: symbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color.opacity(dimmed ? 0.55 : 1))
            .frame(width: 12, height: 12)
            .frame(width: 20, height: 20)
            .background(
                color.opacity(tileOpacity),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    @Environment(\.colorScheme) private var scheme

}

struct DirListView: View {
    static var shouldSave = false

    var fileType: ClopFileType
    @StateObject var textDebounce = TextDebounce(for: .seconds(2))

    @Binding var dirs: [String]
    @Binding var enabled: Bool
    @State var selectedDirs: Set<String> = []
    @State var chooseFile = false
    @State var clopignoreHelpVisible = false
    @State var automationsExpanded = true

    var hideIgnoreRules = false

    @Default(.dirsHideFloatingResult) var dirsHideFloatingResult

    @ViewBuilder var ignoreRulesView: some View {
        if selectedDirs.count == 1, let dir = selectedDirs.first {
            HStack {
                Text("忽略规则").semibold(12).fixedSize()
                Spacer()
                Text("\(dir.replacingOccurrences(of: HOME.string, with: "~"))/.clopignore-\(fileType.rawValue)")
                    .mono(11)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .frame(maxWidth: 400, alignment: .trailing)
            }.padding(.top, 2).opacity(0.8)
            TextEditor(text: $textDebounce.text)
                .font(.mono(12))
                .onChange(of: textDebounce.debouncedText, perform: { value in
                    guard Self.shouldSave else { return }
                    saveIgnoreRules(text: value)
                })
                .frame(height: 100)
            HStack {
                Text("遵循标准 .gitignore 规则。").regular(10)
                Button("\(SwiftUI.Image(systemName: "arrowtriangle.down.square")) 点按查看详情") {
                    clopignoreHelpVisible.toggle()
                }
                .buttonStyle(.plain)
                .font(.semibold(10))
            }
            .opacity(0.8)

            if clopignoreHelpVisible {
                ScrollView {
                    Text("""
                    **Pattern syntax:**

                    1. **Wildcards**: You can use asterisks (`*`) as wildcards to match multiple characters or directories at any level. For example, `*.jpg` will match all files with the .jpg extension, such as `image.jpg` or `photo.jpg`. Similarly, `*.pdf` will match any PDF files.

                    2. **Directory names**: You can specify directories in patterns by ending the pattern with a slash (/). For instance, `images/` will match all files or directories named "images" or residing within an "images" directory.

                    3. **Negation**: Prefixing a pattern with an exclamation mark (!) negates the pattern, instructing the app to include files that would otherwise be excluded. For example, `!important.pdf` would include a file named "important.pdf" even if it satisfies other exclusion patterns.

                    4. **Comments**: You can include comments by adding a hash symbol (`#`) at the beginning of the line. These comments are ignored by the app and serve as helpful annotations for humans.

                    *More complex patterns can be found in the [gitignore documentation](https://git-scm.com/docs/gitignore#_pattern_format).*

                    **Examples:**

                    `# Ignore all files with the .jpg extension`
                    `*.jpg`
                    ` `
                    `# Ignore all folders and subfolders (like a non-recursive option)`
                    `*/*`
                    ` `
                    `# Exclude all files in a "DontOptimise" directory`
                    `DontOptimise/`
                    ` `
                    `# Exclude all MKV video files`
                    `*.mkv`
                    ` `
                    `# Exclude invoices (PDF files starting with "invoice-")`
                    `invoice-*.pdf`
                    ` `
                    `# Exclude a specific file named "confidential.pdf"`
                    `confidential.pdf`
                    ` `
                    `# Include a specific file named "important.pdf" even if it matches other patterns`
                    `!important.pdf`
                    """)
                    .foregroundColor(.secondary)
                }
                .roundbg(color: .black.opacity(0.05))
            }
        } else {
            (Text("选择单个路径以编辑其 ") + Text("忽略规则").bold())
                .padding(.top, 6)
                .opacity(0.8)
        }

    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                Table(dirs.sorted(), selection: $selectedDirs) {
                    TableColumn("Path") { dir in Text(dir.replacingOccurrences(of: HOME.string, with: "~")).mono(12) }
                    TableColumn("Show floating results") { dir in
                        Toggle("显示悬浮结果", isOn: showFloatingBinding(for: dir))
                            .toggleStyle(.checkbox)
                            .controlSize(.mini)
                            .labelsHidden()
                            .help("优化此文件夹中的文件时显示悬浮缩略图与进度")
                    }
                    .width(130)
                    TableColumn("") { dir in
                        Button(dirHasAutomation(dir) ? "编辑自动化" : "Add automation") {
                            showAutomations(folder: dir, addNew: !dirHasAutomation(dir))
                        }
                        .font(.round(10))
                        .buttonStyle(.borderless)
                        .foregroundColor(.accentColor)
                    }
                    .width(110)
                }
                .tableStyle(.inset)
                .frame(height: 150)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.6)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .searchAnchor("images.watchpaths.dirsHideFloatingResult")
            }.frame(height: 150)

            HStack(spacing: 2) {
                Button(action: { chooseFile = true }, label: { SwiftUI.Image(systemName: "plus").font(.bold(12)).frame(width: 16, height: 16) })
                    .fileImporter(
                        isPresented: $chooseFile,
                        allowedContentTypes: [.directory],
                        allowsMultipleSelection: true,
                        onCompletion: { result in
                            switch result {
                            case let .success(success):
                                dirs = (dirs + success.map(\.path.portablePath)).uniqued.without(NOT_ALLOWED_TO_WATCH)
                            case let .failure(failure):
                                log.error("\(failure.localizedDescription)")
                            }
                        }
                    )
                    .disabled(!enabled)

                Button(
                    action: {
                        dirs = Set(dirs).without(selectedDirs)
                        selectedDirs = []
                    },
                    label: { SwiftUI.Image(systemName: "minus").font(.bold(12)).frame(width: 16, height: 16) }
                )
                .disabled(selectedDirs.isEmpty || !enabled)
                Spacer()
                Toggle(" 启用 **\(fileType == .pdf ? "PDF" : fileType.rawValue)** 自动优化", isOn: $enabled)
                    .font(.round(11, weight: .regular))
                    .controlSize(.mini)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .searchAnchor("pdf.watchpaths.enableAutomaticPDFOptimisations")
                    .searchAnchor("audio.watchpaths.enableAutomaticAudioOptimisations")
                    .searchAnchor("images.watchpaths.enableAutomaticImageOptimisations")
                    .searchAnchor("video.watchpaths.enableAutomaticVideoOptimisations")
            }

            if enabled, selectedDirs.count == 1, let dir = selectedDirs.first {
                FolderAutomationsSection(fileType: fileType, folder: dir, expanded: $automationsExpanded)
            }
            if !hideIgnoreRules, enabled {
                ignoreRulesView
            }
        }
        .padding(4)
        .onChange(of: selectedDirs) { [selectedDirs] newSelectedDirs in
            Self.shouldSave = false
            guard newSelectedDirs.count == 1, let dir = newSelectedDirs.first else {
                return
            }
            if textDebounce.text != textDebounce.debouncedText {
                saveIgnoreRules(text: textDebounce.text, dir: selectedDirs.first)
            }

            textDebounce.debouncedText = (try? String(contentsOfFile: "\(dir.resolvedPath)/.clopignore-\(fileType.rawValue)")) ?? ""
            textDebounce.text = textDebounce.debouncedText
        }
        .onChange(of: enabled) { enabled in
            if !enabled {
                selectedDirs = []
            }
        }
    }

    func showFloatingBinding(for dir: String) -> Binding<Bool> {
        Binding(
            get: { !dirsHideFloatingResult.contains(dir) },
            set: { show in
                if show {
                    dirsHideFloatingResult.remove(dir)
                } else {
                    dirsHideFloatingResult.insert(dir)
                }
            }
        )
    }

    func dirHasAutomation(_ dir: String) -> Bool {
        Defaults[fileType.pipelineKey][dir]?.isEmpty == false
    }

    func showAutomations(folder: String, addNew: Bool) {
        selectedDirs = [folder]
        withAnimation(.easeOut(duration: 0.15)) { automationsExpanded = true }
        guard addNew else { return }
        var dict = Defaults[fileType.pipelineKey]
        dict[folder, default: []].append(Pipeline(steps: []))
        Defaults[fileType.pipelineKey] = dict
    }

    func saveIgnoreRules(text: String, dir: String? = nil) {
        guard let dir = dir ?? selectedDirs.first else { return }

        let clopIgnore = "\(dir.resolvedPath)/.clopignore-\(fileType.rawValue)"
        guard text.isNotEmpty else {
            log.debug("Deleting \(clopIgnore)")
            try? fm.removeItem(atPath: clopIgnore)
            return
        }
        do {
            log.debug("Saving \(clopIgnore)")
            try text.write(toFile: clopIgnore, atomically: false, encoding: .utf8)
        } catch {
            log.error("\(error.localizedDescription)")
        }
    }
}

/// Per-path automations shown below the watched-paths table. Edits the same Defaults the
/// Automation tab uses (`fileType.pipelineKey`), filtered to a single folder.
struct FolderAutomationsSection: View {
    let fileType: ClopFileType
    let folder: String
    @Binding var expanded: Bool

    @Default(.pipelinesToRunOnImage) var imagePipelines
    @Default(.pipelinesToRunOnVideo) var videoPipelines
    @Default(.pipelinesToRunOnPdf) var pdfPipelines
    @Default(.pipelinesToRunOnAudio) var audioPipelines

    var pipelinesBinding: Binding<[String: [Pipeline]]> {
        switch fileType {
        case .image: $imagePipelines
        case .video: $videoPipelines
        case .pdf: $pdfPipelines
        case .audio: $audioPipelines
        }
    }

    var count: Int {
        pipelinesBinding.wrappedValue[folder]?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }) {
                HStack(spacing: 5) {
                    SwiftUI.Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.semibold(9)).foregroundColor(.secondary)
                    Text("自动化").semibold(12)
                    if count > 0 {
                        Text("\(count)").mono(10)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                PipelineEditorRow(
                    source: .dir(folder),
                    fileType: fileType,
                    pipelines: pipelinesBinding,
                    editingKey: $editingKey,
                    onRemoveSource: { pipelinesBinding.wrappedValue[folder] = nil }
                )
            }
        }
        .padding(.top, 6)
    }

    @State private var editingKey: String?

}

/// Reusable automation editor scoped to a single non-folder `OptimisationSource`
/// (drop zone, clipboard). Stacks one `PipelineEditorRow` per file type, each
/// bound to the matching `pipelinesToRunOn<Type>` Defaults dict keyed by
/// `source.string`. Writes the SAME storage as the Automation tab, so both
/// views update live. Per-file-type editors are always shown (no collapse).
///
/// Produces interface (consumed by the clipboard pane in a later phase):
///   SourceAutomationsSection(source: .dropZone)
struct SourceAutomationsSection: View {
    let source: OptimisationSource
    var disabledTypes: Set<ClopFileType> = []

    @Default(.pipelinesToRunOnImage) var imagePipelines
    @Default(.pipelinesToRunOnVideo) var videoPipelines
    @Default(.pipelinesToRunOnPdf) var pdfPipelines
    @Default(.pipelinesToRunOnAudio) var audioPipelines

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ClopFileType.allCases, id: \.self) { fileType in
                let isDisabled = disabledTypes.contains(fileType)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        SwiftUI.Image(systemName: fileType.symbolName)
                            .frame(width: 14)
                        Text(fileType == .pdf ? "PDF" : fileType.description.capitalized)
                            .semibold(10)
                    }
                    .foregroundColor(fileType.color)
                    PipelineEditorRow(
                        source: source,
                        fileType: fileType,
                        pipelines: binding(for: fileType),
                        editingKey: $editingKey,
                        onRemoveSource: nil,
                        hideInertRemoveButton: true
                    )
                }
                .disabled(isDisabled)
                .saturation(isDisabled ? 0 : 1)
                .opacity(isDisabled ? 0.5 : 1)
            }
        }
        .padding(.top, 6)
    }

    func binding(for fileType: ClopFileType) -> Binding<[String: [Pipeline]]> {
        switch fileType {
        case .image: $imagePipelines
        case .video: $videoPipelines
        case .pdf: $pdfPipelines
        case .audio: $audioPipelines
        }
    }

    @State private var editingKey: String?

}

struct PDFSettingsView: View {
    @Default(.pdfDirs) var pdfDirs
    @Default(.maxPDFSizeMB) var maxPDFSizeMB
    @Default(.minPDFSizeKB) var minPDFSizeKB
    @Default(.maxPDFFileCount) var maxPDFFileCount
    @Default(.pdfDPI) var pdfDPI
    @Default(.enableAutomaticPDFOptimisations) var enableAutomaticPDFOptimisations

    var body: some View {
        Form {
            Section(header: SectionHeader(title: "监视路径", subtitle: "这些文件夹里出现的 PDF 会被自动优化")) {
                DirListView(fileType: .pdf, dirs: $pdfDirs, enabled: $enableAutomaticPDFOptimisations)
            }
            .searchAnchor("pdf.watchpaths.pdfDirs")
            Section(header: SectionHeader(title: "优化规则")) {
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "folder.badge.gearshape")
                    Text("文件去向设置于").foregroundColor(.secondary)
                    Button("文件处理") { settingsViewManager.tab = .files }.buttonStyle(.link)
                }.font(.system(size: 11))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("压缩").regular(13)
                            .searchAnchor("pdf.optimisationrules.pdfDPI")
                        Slider(
                            value: Binding(
                                get: { Double(pdfStopIndex(pdfDPI == PDF_DPI_ADAPTIVE ? lastPDFDPI : pdfDPI)) },
                                set: { pdfDPI = PDF_DPI_STOPS[Int($0.rounded())] }
                            ),
                            in: 0 ... Double(PDF_DPI_STOPS.count - 1), step: 1
                        )
                        .accessibilityLabel("压缩")
                        .disabled(pdfDPI == PDF_DPI_ADAPTIVE)
                        Text("\(pdfDPI == PDF_DPI_ADAPTIVE ? lastPDFDPI : pdfDPI) DPI")
                            .mono(11).foregroundColor(.secondary)
                            .opacity(pdfDPI == PDF_DPI_ADAPTIVE ? 0.2 : 1)
                            .frame(width: 56, alignment: .trailing)
                        Button("自适应") {
                            if pdfDPI == PDF_DPI_ADAPTIVE {
                                pdfDPI = lastPDFDPI
                            } else {
                                lastPDFDPI = pdfDPI
                                pdfDPI = PDF_DPI_ADAPTIVE
                            }
                        }
                        .buttonStyle(ToggleButton(isOn: .oneway { pdfDPI == PDF_DPI_ADAPTIVE }))
                        .font(.mono(11))
                    }
                    Text(pdfCompressionSubtitle).round(10, weight: .regular).foregroundColor(.secondary)
                }
            }
            Section(header: SectionHeader(title: "监视文件过滤", subtitle: "只有在此范围内的文件会被优化")) {
                FileSizeRangeRow(minKB: $minPDFSizeKB, maxMB: $maxPDFSizeMB)
                    .searchAnchor("pdf.watchedfilefilters.minPDFSizeKB")
                CountSliderRow(count: $maxPDFFileCount, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "PDF is" : "PDFs are") copied or moved at once" })
                    .searchAnchor("pdf.watchedfilefilters.maxPDFFileCount")
            }
        }
        .scrollContentBackground(.hidden)
        .padding(4)
    }

    @State private var lastPDFDPI = 150

    private var pdfCompressionSubtitle: String {
        if pdfDPI == PDF_DPI_ADAPTIVE {
            return "Clop automatically picks a per-PDF DPI from the source image density and downscales images above it"
        }
        if pdfDPI >= PDF_DPI_NO_DOWNSAMPLE {
            return "无损压缩,从元数据和重编码中省空间;体积可能减少有限。"
        }
        return "Downscales high resolution images to \(pdfDPI) DPI; lower-resolution images are left untouched"
    }

    private func pdfStopIndex(_ dpi: Int) -> Int {
        PDF_DPI_STOPS.firstIndex(of: dpi)
            ?? PDF_DPI_STOPS.enumerated().min(by: { abs($0.element - dpi) < abs($1.element - dpi) })?.offset
            ?? 0
    }

}

struct VideoSettingsView: View {
    @Default(.videoDirs) var videoDirs
    @Default(.formatsToConvertToMP4) var formatsToConvertToMP4
    @Default(.maxVideoSizeMB) var maxVideoSizeMB
    @Default(.minVideoSizeKB) var minVideoSizeKB
    @Default(.minVideoResolution) var minVideoResolution
    @Default(.maxVideoResolution) var maxVideoResolution
    @Default(.videoFormatsToSkip) var videoFormatsToSkip
    @Default(.adaptiveVideoSize) var adaptiveVideoSize
    @Default(.capVideoFPS) var capVideoFPS
    @Default(.targetVideoFPS) var targetVideoFPS
    @Default(.minVideoFPS) var minVideoFPS
    @Default(.playbackSpeedFrameBehaviour) var playbackSpeedFrameBehaviour
    @Default(.maxVideoFileCount) var maxVideoFileCount
    @Default(.removeAudioFromVideos) var removeAudioFromVideos
    @Default(.convertAudioToAAC) var convertAudioToAAC

    @Default(.videoEncoder) var videoEncoder
    @Default(.videoCompression) var videoCompression
    #if arch(arm64)
        @Default(.useCPUIntensiveEncoder) var useCPUIntensiveEncoder
    #endif
    @Default(.useAggressiveOptimisationMP4) var useAggressiveOptimisationMP4
    @Default(.enableAutomaticVideoOptimisations) var enableAutomaticVideoOptimisations

    var videoResolvedTier: CompressionTier {
        videoCompression.tier == .custom ? .smaller : videoCompression.tier
    }

    var body: some View {
        CompatibilityScrollForm {
            Section(header: SectionHeader(title: "监视路径", subtitle: "这些文件夹里出现的视频会被自动优化")) {
                DirListView(fileType: .video, dirs: $videoDirs, enabled: $enableAutomaticVideoOptimisations)
            }
            .searchAnchor("video.watchpaths.videoDirs")
            Section(header: SectionHeader(title: "优化规则")) {
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "folder.badge.gearshape")
                    Text("文件去向设置于").foregroundColor(.secondary)
                    Button("文件处理") { settingsViewManager.tab = .files }.buttonStyle(.link)
                }.font(.system(size: 11))
                HStack(spacing: 8) {
                    Text("压缩").regular(13)
                        .searchAnchor("video.optimisationrules.videoCompression")
                    Spacer()
                    Menu {
                        ForEach([CompressionTier.adaptive, .lossless, .fast, .smaller], id: \.self) { tier in
                            Toggle(isOn: Binding(
                                get: { videoResolvedTier == tier },
                                set: {
                                    if $0 {
                                        videoCompression = CompressionQuality(tier: tier, factor: videoCompression.factor)
                                    }
                                }
                            )) {
                                Text(videoCompressionTitle(tier))
                                Text(videoCompressionSubtitle(tier))
                            }
                        }
                    } label: {
                        Text(videoCompressionTitle(videoResolvedTier))
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
                if videoCompression.tier == .smaller || videoCompression.tier == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Button("自动") {
                                if videoCompression.videoUsesAutoCRF {
                                    videoCompression = CompressionQuality(tier: .smaller, factor: lastVideoFactor)
                                } else {
                                    lastVideoFactor = max(5, videoCompression.factor)
                                    videoCompression = CompressionQuality(tier: .smaller, factor: 0)
                                }
                            }
                            .buttonStyle(ToggleButton(isOn: .oneway { videoCompression.videoUsesAutoCRF }))
                            .font(.mono(11))
                            Slider(
                                value: Binding(
                                    get: { Double(videoCompression.videoUsesAutoCRF ? lastVideoFactor : max(5, videoCompression.factor)) },
                                    set: { videoCompression = CompressionQuality(tier: .smaller, factor: Int($0.rounded())) }
                                ),
                                in: 5 ... 100, step: 1
                            ) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("更佳画质").round(9, weight: .regular).foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("更小体积").round(9, weight: .regular).foregroundColor(.secondary)
                            }
                            .accessibilityLabel("压缩")
                            .frame(maxWidth: .infinity)
                            .disabled(videoCompression.videoUsesAutoCRF)
                            .help("向「更佳画质」拖动画质更好,向「更小体积」拖动文件更小")
                            Text("\(videoCompression.videoUsesAutoCRF ? lastVideoFactor : videoCompression.factor)%")
                                .mono(11).foregroundColor(.secondary)
                                .opacity(videoCompression.videoUsesAutoCRF ? 0.2 : 1)
                                .frame(width: 38, alignment: .trailing)
                        }
                        if videoCompression.videoUsesAutoCRF {
                            Text("编码器将根据视频内容选择最佳压缩系数")
                                .round(10, weight: .regular).foregroundColor(.secondary)
                        }
                    }
                }
                Toggle("移除优化后视频的音轨", isOn: $removeAudioFromVideos)
                    .searchAnchor("video.optimisationrules.removeAudioFromVideos", namesControl: true)
                Toggle(isOn: $capVideoFPS.animation(.spring())) {
                    HStack {
                        Text("帧率上限设为").regular(13).padding(.trailing, 10)
                        Spacer()

                        Button("30fps") {
                            withAnimation(.spring()) { targetVideoFPS = 30 }
                        }.buttonStyle(ToggleButton(isOn: .oneway { targetVideoFPS == 30 }))
                        Button("60fps") {
                            withAnimation(.spring()) { targetVideoFPS = 60 }
                        }.buttonStyle(ToggleButton(isOn: .oneway { targetVideoFPS == 60 }))
                        Button("原片的 1/2") {
                            withAnimation(.spring()) { targetVideoFPS = -2 }
                        }.buttonStyle(ToggleButton(isOn: .oneway { targetVideoFPS == -2 }))
                        Button("原片的 1/4") {
                            withAnimation(.spring()) { targetVideoFPS = -4 }
                        }.buttonStyle(ToggleButton(isOn: .oneway { targetVideoFPS == -4 }))
                    }.disabled(!capVideoFPS)
                }
                .accessibilityLabel("限制帧率")
                .searchAnchor("video.optimisationrules.capVideoFPS")
                if targetVideoFPS < 0, capVideoFPS {
                    HStack {
                        Text("但不低于").regular(13).padding(.trailing, 10)
                            .searchAnchor("video.optimisationrules.minVideoFPS")
                        Spacer()

                        Button("10fps") {
                            minVideoFPS = 10
                        }.buttonStyle(ToggleButton(isOn: .oneway { minVideoFPS == 10 }))
                        Button("24fps") {
                            minVideoFPS = 24
                        }.buttonStyle(ToggleButton(isOn: .oneway { minVideoFPS == 24 }))
                        Button("30fps") {
                            minVideoFPS = 30
                        }.buttonStyle(ToggleButton(isOn: .oneway { minVideoFPS == 30 }))
                        Button("60fps") {
                            minVideoFPS = 60
                        }.buttonStyle(ToggleButton(isOn: .oneway { minVideoFPS == 60 }))
                    }
                    .padding(.leading, 10)
                }
                Picker(selection: $playbackSpeedFrameBehaviour) {
                    Text("保留帧(更流畅,帧率更高)").tag(PlaybackSpeedFrameBehaviour.keepFrames)
                    Text("丢帧(文件更小)").tag(PlaybackSpeedFrameBehaviour.dropFrames)
                } label: {
                    Text("播放速度调整").regular(13)
                }
                .accessibilityLabel("播放速度调整")
                .searchAnchor("video.optimisationrules.playbackSpeedFrameBehaviour")

            }
            Section(header: SectionHeader(title: "监视文件过滤", subtitle: "只有在此范围内的文件会被优化")) {
                FileSizeRangeRow(minKB: $minVideoSizeKB, maxMB: $maxVideoSizeMB)
                    .searchAnchor("video.watchedfilefilters.minVideoSizeKB")
                ResolutionRangeRow(label: "Resolution", minRes: $minVideoResolution, maxRes: $maxVideoResolution)
                    .searchAnchor("video.watchedfilefilters.minVideoResolution")
                CountSliderRow(count: $maxVideoFileCount, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "video is" : "videos are") copied or moved at once" })
                    .searchAnchor("video.watchedfilefilters.maxVideoFileCount")
                HStack {
                    Text("忽略这些扩展名的视频").regular(13).padding(.trailing, 10)
                        .searchAnchor("video.watchedfilefilters.videoFormatsToSkip")
                    Spacer()

                    ForEach(VIDEO_FORMATS, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            videoFormatsToSkip.toggle(format)
                        }.buttonStyle(ToggleButton(isOn: .oneway { videoFormatsToSkip.contains(format) }))
                            .font(.mono(11))
                    }
                }
            }
            Section(header: SectionHeader(title: "兼容性", subtitle: "优化前把小众格式转换为更兼容的格式")) {
                HStack {
                    (Text("转换为 ").regular(13) + Text("mp4").mono(13)).padding(.trailing, 10)
                        .searchAnchor("video.compatibility.formatsToConvertToMP4")
                    Spacer()

                    ForEach(FORMATS_CONVERTIBLE_TO_MP4, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            formatsToConvertToMP4.toggle(format)
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToMP4.contains(format) }))
                            .font(.mono(11))
                    }
                }
                Toggle("将音频转换为 AAC", isOn: $convertAudioToAAC)
                    .searchAnchor("video.compatibility.convertAudioToAAC", namesControl: true)
            }
            .id("compatibility")
        }
        .scrollContentBackground(.hidden)
        .padding(4)
    }

    func videoCompressionTitle(_ tier: CompressionTier) -> String {
        switch tier {
        case .adaptive: "Adaptive"
        case .lossless: "Visually lossless"
        case .fast: "Hardware encoder"
        default: "Software encoder"
        }
    }

    func videoCompressionSubtitle(_ tier: CompressionTier) -> String {
        switch tier {
        case .adaptive: "Picks the best encoder and amount of compression for each file"
        case .lossless: "无可感知的画质损失"
        case .fast: "快速省电,几乎不占 CPU,体积收益一般"
        default: "更慢、更占 CPU,画质与体积收益更好"
        }
    }

    @State private var lastVideoFactor = 50

}

struct SectionHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        Text(title).round(15, weight: .semibold)
            + (subtitle.map { Text("\n\($0)").font(.caption).foregroundColor(.secondary) } ?? Text(""))
    }
}

let DEFAULT_NAME_TEMPLATE = "clop_%y-%m-%d_%i"
let DEFAULT_SAME_FOLDER_NAME_TEMPLATE = "%f-optimised"
let DEFAULT_SPECIFIC_FOLDER_NAME_TEMPLATE = "%P/optimised/%f"

// MARK: - Compact template field (without token table) for inline use in File handling pane

struct CompactSameFolderTemplate: View {
    let type: ClopFileType
    @Binding var template: String

    /// The INPUT file extension shown in the example (e.g. "webp" for auto-convert, nil for optimise).
    var inputExtension: String?
    /// The OUTPUT file extension for the example (e.g. "jpeg" for auto-convert, nil = same as input).
    var outputExtension: String?

    /// Build the path used by the example generator: base stem + the OUTPUT extension
    /// (so the template is applied to the file that will actually be written).
    var examplePath: FilePath {
        let ext = outputExtension ?? inputExtension
        guard let ext else { return type.defaultNameTemplatePath }
        let base = type.defaultNameTemplatePath
        let stem = base.lastComponent?.stem ?? "shot"
        return base.removingLastComponent().appending("\(stem).\(ext)")
    }

    var inputName: String {
        let base = type.defaultNameTemplatePath
        let stem = base.lastComponent?.stem ?? "shot"
        if let ext = inputExtension {
            return "\(stem).\(ext)"
        }
        return base.lastComponent?.string ?? "shot.png"
    }

    var outputName: String {
        generateFileName(template: template ?! DEFAULT_SAME_FOLDER_NAME_TEMPLATE, for: examplePath, autoIncrementingNumber: &Defaults[.lastAutoIncrementingNumber])
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("", text: $template, prompt: Text(DEFAULT_SAME_FOLDER_NAME_TEMPLATE))
                .accessibilityLabel("文件名模板")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.gray, lineWidth: 1)
                )
            ExampleContainer(inputName: inputName, outputName: outputName, inputExt: inputExtension, outputExt: outputExtension)
                .layoutPriority(1)
        }
    }
}

struct CompactSpecificFolderTemplate: View {
    let type: ClopFileType
    @Binding var template: String

    /// The INPUT file extension shown in the example (e.g. "webp" for auto-convert, nil for optimise).
    var inputExtension: String?
    /// The OUTPUT file extension for the example (e.g. "jpeg" for auto-convert, nil = same as input).
    var outputExtension: String?

    /// Build the path used by the example generator: base stem + the OUTPUT extension.
    var examplePath: FilePath {
        let ext = outputExtension ?? inputExtension
        guard let ext else { return type.defaultNameTemplatePath }
        let base = type.defaultNameTemplatePath
        let stem = base.lastComponent?.stem ?? "shot"
        return base.removingLastComponent().appending("\(stem).\(ext)")
    }

    var inputName: String {
        let base = type.defaultNameTemplatePath
        let stem = base.lastComponent?.stem ?? "shot"
        if let ext = inputExtension {
            return "\(stem).\(ext)"
        }
        return base.lastComponent?.string ?? "shot.png"
    }

    var outputPath: String {
        (try? generateFilePath(
            template: template ?! DEFAULT_SPECIFIC_FOLDER_NAME_TEMPLATE,
            for: examplePath,
            autoIncrementingNumber: &Defaults[.lastAutoIncrementingNumber],
            mkdir: false
        ))?.flatMap(\.shellString) ?? "Invalid path"
    }

    /// Stores a pasted home path as `~/…` so the template still points somewhere real on the other
    /// Macs it syncs to, where the username differs.
    var portableTemplate: Binding<String> {
        Binding(get: { template }, set: { template = $0.portablePath })
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("", text: portableTemplate, prompt: Text(DEFAULT_SPECIFIC_FOLDER_NAME_TEMPLATE))
                .accessibilityLabel("文件夹模板")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.gray, lineWidth: 1)
                )
            ExampleContainer(inputName: inputName, outputName: outputPath, inputExt: inputExtension, outputExt: outputExtension)
                .layoutPriority(1)
        }
    }
}

// MARK: - Example container: "Example: [inputPill] becomes [outputPill]"

// The whole expression lives in a single bordered+bg element at the right of the row.

/// A filled muted pill for a filename token. Content-sized (fixedSize), mono font.
private struct ExampleFilePill: View {
    let name: String
    /// Tint for the capsule fill; nil = neutral grey.
    var tint: Color?

    var body: some View {
        Text(name)
            .font(.mono(10))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .fixedSize()
            .background(Capsule().fill(fillColor))
            .foregroundColor(.primary)
    }

    private var fillColor: Color {
        if let tint {
            return tint.opacity(0.11)
        }
        return adaptiveColor(
            light: Color(white: 0.0).opacity(0.07),
            dark: Color(white: 1.0).opacity(0.10)
        )
    }

}

/// Wraps "Example: [in] becomes [out]" in a single subtle bordered container.
private struct ExampleContainer: View {
    let inputName: String
    let outputName: String
    // Extensions used purely for hue-tinting the pills (nil = neutral).
    var inputExt: String?
    var outputExt: String?

    var body: some View {
        HStack(spacing: 4) {
            Text("示例:")
                .font(.round(11))
                .foregroundColor(.secondary)
                .fixedSize()
            ExampleFilePill(name: inputName, tint: tint(for: inputExt))
            Text("变为")
                .font(.round(11))
                .foregroundColor(.secondary)
                .fixedSize()
            ExampleFilePill(name: middleTruncated(outputName), tint: tint(for: outputExt ?? inputExt))
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(bgColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private static let extensionTints: [String: Color] = [
        "jpeg": Color(red: 1.0, green: 0.83, blue: 0.0),
        "jpg": Color(red: 1.0, green: 0.83, blue: 0.0),
        "png": .blue,
        "mp4": Color(red: 0.6, green: 0.3, blue: 0.9),
        "webp": Color(red: 0.0, green: 0.7, blue: 0.5),
        "avif": Color(red: 0.0, green: 0.6, blue: 0.9),
        "heic": Color(red: 0.5, green: 0.0, blue: 0.8),
        "m4a": Color(red: 0.2, green: 0.7, blue: 0.3),
        "mp3": Color(red: 0.3, green: 0.6, blue: 1.0),
        "ogg": Color(red: 0.8, green: 0.4, blue: 0.0),
        "mov": Color(red: 0.8, green: 0.1, blue: 0.1),
        "pdf": Color(red: 0.8, green: 0.3, blue: 0.1),
    ]

    private var bgColor: Color {
        adaptiveColor(
            light: Color(white: 0.0).opacity(0.035),
            dark: Color(white: 1.0).opacity(0.06)
        )
    }

    /// Middle-truncate a long output path so the content-sized pill stays around 200px wide, leaving
    /// more room for the template field. The pill uses a 10pt monospaced font (~6px per glyph), so
    /// roughly 32 characters fit; longer strings keep the head and tail with an ellipsis in between.
    private func middleTruncated(_ s: String, maxChars: Int = 32) -> String {
        guard s.count > maxChars else { return s }
        let keep = maxChars - 1
        let head = keep / 2
        let tail = keep - head
        return "\(s.prefix(head))…\(s.suffix(tail))"
    }

    private func tint(for ext: String?) -> Color? {
        guard let ext else { return nil }
        return Self.extensionTints[ext.lowercased()]
    }

}

// MARK: - Adaptive colour helper

/// Returns a colour that picks between `light` and `dark` variants based on the current appearance.
/// Uses NSColor's dynamic provider, which is supported on macOS 13+.
private func adaptiveColor(light: Color, dark: Color) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(dark)
            : NSColor(light)
    })
}

// Adaptive text colours for each format hue: dark/saturated in light mode, bright in dark mode.
private let sourceAdaptive = adaptiveColor(light: Color(red: 0.72, green: 0.12, blue: 0.12), dark: Color(red: 1.0, green: 0.55, blue: 0.55))
private let jpegAdaptive = adaptiveColor(light: Color(red: 0.62, green: 0.44, blue: 0.0), dark: Color(red: 1.0, green: 0.83, blue: 0.35))
private let pngAdaptive = adaptiveColor(light: Color(red: 0.1, green: 0.35, blue: 0.75), dark: Color(red: 0.5, green: 0.75, blue: 1.0))
private let mp4Adaptive = adaptiveColor(light: Color(red: 0.45, green: 0.2, blue: 0.7), dark: Color(red: 0.78, green: 0.6, blue: 1.0))
private let audioAdaptive = adaptiveColor(light: Color(red: 0.12, green: 0.5, blue: 0.22), dark: Color(red: 0.45, green: 0.85, blue: 0.55))
private let orangeAdaptive = adaptiveColor(light: Color(red: 0.65, green: 0.35, blue: 0.0), dark: Color(red: 1.0, green: 0.7, blue: 0.35))

// MARK: - Auto-conversion pills

private struct PillView: View {
    let text: String
    let tint: Color // background tint (the raw hue)
    let textColor: Color // adaptive text colour

    var body: some View {
        Text(text)
            .font(.mono(10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundColor(textColor)
    }
}

private struct AutoConvertPills: View {
    let groups: [FileHandlingSettingsView.ConvertGroup]
    let compatibilityTab: SettingsView.Tabs

    var body: some View {
        if !groups.isEmpty {
            HStack(spacing: 6) {
                Text("转换为:")
                    .round(11)
                    .foregroundColor(.secondary)
                ForEach(groups.indices, id: \.self) { idx in
                    let group = groups[idx]
                    if idx > 0 {
                        Text("|")
                            .font(.mono(10, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    PillView(text: group.sources.joined(separator: ", "), tint: group.sourceTint, textColor: group.sourceTextColor)
                    Text("->")
                        .font(.mono(10, weight: .regular))
                        .foregroundColor(.secondary)
                    PillView(text: group.target, tint: group.targetTint, textColor: group.targetTextColor)
                }
                Spacer(minLength: 0)
                Button {
                    settingsViewManager.tab = compatibilityTab
                    settingsViewManager.scrollToCompatibility = true
                } label: {
                    HStack(spacing: 3) {
                        Text("配置于")
                        Text("兼容性").underline()
                    }
                    .foregroundColor(.secondary.opacity(0.65))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in
                    if h {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .font(.round(11))
            }
        }
    }
}

/// A `Form` that scrolls down to the Section tagged `.id("compatibility")` when the
/// "在「兼容性」中配置" link in File Handling requests it. Drop-in replacement
/// for `Form` in the Video / Audio / Images tabs; per-tab modifiers (formStyle,
/// scrollContentBackground, padding) still reach the form via the environment.
private struct CompatibilityScrollForm<Content: View>: View {
    @ObservedObject var svm = settingsViewManager

    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            Form { content }
                .onAppear { scroll(proxy) }
                .onChange(of: svm.scrollToCompatibility) { _ in scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard svm.scrollToCompatibility else { return }
        // Give the freshly switched-to tab a moment to lay out its sections before scrolling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { proxy.scrollTo("compatibility", anchor: .top) }
            svm.scrollToCompatibility = false
        }
    }
}

/// Scrolls an enclosing scroll container down to the section tagged `.id("automation")` when an
/// assignment pill's "Go to" (clipboard / drop zone) requests it, and on appear for the just-switched
/// tab. Apply to the tab's `Form`/`ScrollView`; tag its Automation section with `.id("automation")`.
private struct ScrollToAutomation: ViewModifier {
    @ObservedObject var svm = settingsViewManager

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear { scroll(proxy) }
                .onChange(of: svm.scrollToAutomation) { _ in scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard svm.scrollToAutomation else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { proxy.scrollTo("automation", anchor: .top) }
            svm.scrollToAutomation = false
        }
    }
}

extension View {
    func scrollsToAutomation() -> some View {
        modifier(ScrollToAutomation())
    }
}

// MARK: - File handling settings tab

struct FileHandlingSettingsView: View {
    // MARK: - Auto-conversion pill groups

    struct ConvertGroup {
        let sources: [String]
        let target: String
        let sourceTint: Color
        let targetTint: Color
        let sourceTextColor: Color
        let targetTextColor: Color
    }

    // Optimised placement
    @Default(.optimisedImageBehaviour) var optimisedImageBehaviour
    @Default(.optimisedVideoBehaviour) var optimisedVideoBehaviour
    @Default(.optimisedAudioBehaviour) var optimisedAudioBehaviour
    @Default(.optimisedPDFBehaviour) var optimisedPDFBehaviour
    @Default(.sameFolderNameTemplateImage) var sameFolderNameTemplateImage
    @Default(.sameFolderNameTemplateVideo) var sameFolderNameTemplateVideo
    @Default(.sameFolderNameTemplateAudio) var sameFolderNameTemplateAudio
    @Default(.sameFolderNameTemplatePDF) var sameFolderNameTemplatePDF
    @Default(.specificFolderNameTemplateImage) var specificFolderNameTemplateImage
    @Default(.specificFolderNameTemplateVideo) var specificFolderNameTemplateVideo
    @Default(.specificFolderNameTemplateAudio) var specificFolderNameTemplateAudio
    @Default(.specificFolderNameTemplatePDF) var specificFolderNameTemplatePDF

    // Auto-conversion placement
    @Default(.convertedImageBehaviour) var convertedImageBehaviour
    @Default(.convertedVideoBehaviour) var convertedVideoBehaviour
    @Default(.convertedAudioBehaviour) var convertedAudioBehaviour

    // Manual conversion placement
    @Default(.manualConvertedImageBehaviour) var manualConvertedImageBehaviour
    @Default(.manualConvertedVideoBehaviour) var manualConvertedVideoBehaviour
    @Default(.manualConvertedAudioBehaviour) var manualConvertedAudioBehaviour

    // Shared conversion templates (used by both auto and manual convert rows)
    @Default(.convertedSameFolderNameTemplateImage) var convertedSameFolderNameTemplateImage
    @Default(.convertedSameFolderNameTemplateVideo) var convertedSameFolderNameTemplateVideo
    @Default(.convertedSameFolderNameTemplateAudio) var convertedSameFolderNameTemplateAudio
    @Default(.convertedSpecificFolderNameTemplateImage) var convertedSpecificFolderNameTemplateImage
    @Default(.convertedSpecificFolderNameTemplateVideo) var convertedSpecificFolderNameTemplateVideo
    @Default(.convertedSpecificFolderNameTemplateAudio) var convertedSpecificFolderNameTemplateAudio

    // Format lists for context text
    @Default(.formatsToConvertToJPEG) var formatsToConvertToJPEG
    @Default(.formatsToConvertToPNG) var formatsToConvertToPNG
    @Default(.formatsToConvertToMP4) var formatsToConvertToMP4
    @Default(.formatsToConvertToAAC) var formatsToConvertToAAC
    @Default(.formatsToConvertToMP3) var formatsToConvertToMP3

    var body: some View {
        Form {
            // MARK: Images

            Section(header: SectionHeader(title: "图像")) {
                // Optimise row: picker + optional template in a single Form row (no divider between them).
                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $optimisedImageBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("优化后文件的存放位置").regular(13)
                            + Text("\n较小的文件保存到哪里,以及是否替换原件").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.images.optimisedImageBehaviour", namesControl: true)
                    if optimisedImageBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .image, template: $sameFolderNameTemplateImage)
                            .searchAnchor("files.images.sameFolderNameTemplateImage")
                    } else if optimisedImageBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .image, template: $specificFolderNameTemplateImage)
                            .searchAnchor("files.images.specificFolderNameTemplateImage")
                    }
                }

                // Auto-convert row: picker + Converts pills + optional template in a single Form row.
                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $convertedImageBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("兼容格式的自动转换行为").regular(13)
                            + Text("\n许多应用难以打开的格式会先自动转换为支持广泛的格式再优化。").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.images.convertedImageBehaviour", namesControl: true)
                    AutoConvertPills(groups: imageAutoConvertGroups, compatibilityTab: .images)
                    if convertedImageBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .image, template: $convertedSameFolderNameTemplateImage, inputExtension: autoImageInputExt, outputExtension: autoImageOutputExt)
                            .searchAnchor("files.images.convertedSameFolderNameTemplateImage")
                    } else if convertedImageBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .image, template: $convertedSpecificFolderNameTemplateImage, inputExtension: autoImageInputExt, outputExtension: autoImageOutputExt)
                            .searchAnchor("files.images.convertedSpecificFolderNameTemplateImage")
                    }
                }

                // Manual-convert row: picker + optional template in a single Form row.
                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $manualConvertedImageBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("手动转换行为").regular(13)
                            + Text("\n通过点按悬浮结果上的扩展名,或右键菜单中的 **转换为...** 子菜单选择新格式。").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.images.manualConvertedImageBehaviour", namesControl: true)
                    if manualConvertedImageBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .image, template: $convertedSameFolderNameTemplateImage, inputExtension: "jpeg", outputExtension: "webp")
                    } else if manualConvertedImageBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .image, template: $convertedSpecificFolderNameTemplateImage, inputExtension: "jpeg", outputExtension: "webp")
                    }
                }

                if imageHasTemplateRow {
                    templateVarsCollapsible(for: .image)
                }
            }

            // MARK: Videos

            Section(header: SectionHeader(title: "视频")) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $optimisedVideoBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("优化后文件的存放位置").regular(13)
                            + Text("\n较小的文件保存到哪里,以及是否替换原件").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.videos.optimisedVideoBehaviour", namesControl: true)
                    if optimisedVideoBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .video, template: $sameFolderNameTemplateVideo)
                            .searchAnchor("files.videos.sameFolderNameTemplateVideo")
                    } else if optimisedVideoBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .video, template: $specificFolderNameTemplateVideo)
                            .searchAnchor("files.videos.specificFolderNameTemplateVideo")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $convertedVideoBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("兼容格式的自动转换行为").regular(13)
                            + Text("\n许多应用难以打开的格式会先自动转换为支持广泛的格式再优化。").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.videos.convertedVideoBehaviour", namesControl: true)
                    AutoConvertPills(groups: videoAutoConvertGroups, compatibilityTab: .video)
                    if convertedVideoBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .video, template: $convertedSameFolderNameTemplateVideo, inputExtension: autoVideoInputExt, outputExtension: "mp4")
                            .searchAnchor("files.videos.convertedSameFolderNameTemplateVideo")
                    } else if convertedVideoBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .video, template: $convertedSpecificFolderNameTemplateVideo, inputExtension: autoVideoInputExt, outputExtension: "mp4")
                            .searchAnchor("files.videos.convertedSpecificFolderNameTemplateVideo")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $manualConvertedVideoBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("手动转换行为").regular(13)
                            + Text("\n通过点按悬浮结果上的扩展名,或右键菜单中的 **转换为...** 子菜单选择新格式。").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.videos.manualConvertedVideoBehaviour", namesControl: true)
                    if manualConvertedVideoBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .video, template: $convertedSameFolderNameTemplateVideo, inputExtension: "mov", outputExtension: "mp4")
                    } else if manualConvertedVideoBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .video, template: $convertedSpecificFolderNameTemplateVideo, inputExtension: "mov", outputExtension: "mp4")
                    }
                }

                if videoHasTemplateRow {
                    templateVarsCollapsible(for: .video)
                }
            }

            // MARK: Audio

            Section(header: SectionHeader(title: "音频")) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $optimisedAudioBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("优化后文件的存放位置").regular(13)
                            + Text("\n较小的文件保存到哪里,以及是否替换原件").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.audio.optimisedAudioBehaviour", namesControl: true)
                    if optimisedAudioBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .audio, template: $sameFolderNameTemplateAudio)
                            .searchAnchor("files.audio.sameFolderNameTemplateAudio")
                    } else if optimisedAudioBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .audio, template: $specificFolderNameTemplateAudio)
                            .searchAnchor("files.audio.specificFolderNameTemplateAudio")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $convertedAudioBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("兼容格式的自动转换行为").regular(13)
                            + Text("\n许多应用难以打开的格式会先自动转换为支持广泛的格式再优化。").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.audio.convertedAudioBehaviour", namesControl: true)
                    AutoConvertPills(groups: audioAutoConvertGroups, compatibilityTab: .audio)
                    if convertedAudioBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .audio, template: $convertedSameFolderNameTemplateAudio, inputExtension: autoAudioInputExt, outputExtension: autoAudioOutputExt)
                            .searchAnchor("files.audio.convertedSameFolderNameTemplateAudio")
                    } else if convertedAudioBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .audio, template: $convertedSpecificFolderNameTemplateAudio, inputExtension: autoAudioInputExt, outputExtension: autoAudioOutputExt)
                            .searchAnchor("files.audio.convertedSpecificFolderNameTemplateAudio")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $manualConvertedAudioBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("手动转换行为").regular(13)
                            + Text("\n通过点按悬浮结果上的扩展名,或右键菜单中的 **转换为...** 子菜单选择新格式。").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.audio.manualConvertedAudioBehaviour", namesControl: true)
                    if manualConvertedAudioBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .audio, template: $convertedSameFolderNameTemplateAudio, inputExtension: "wav", outputExtension: "mp3")
                    } else if manualConvertedAudioBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .audio, template: $convertedSpecificFolderNameTemplateAudio, inputExtension: "wav", outputExtension: "mp3")
                    }
                }

                if audioHasTemplateRow {
                    templateVarsCollapsible(for: .audio)
                }
            }

            // MARK: PDF

            Section(header: SectionHeader(title: "PDF")) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $optimisedPDFBehaviour) {
                        Text("临时文件夹").tag(FileBehaviour.temporary)
                        Text("原位(替换原件)").tag(FileBehaviour.inPlace)
                        Text("与原件同文件夹").tag(FileBehaviour.sameFolder)
                        Text("指定文件夹").tag(FileBehaviour.specificFolder)
                    } label: {
                        Text("优化后文件的存放位置").regular(13)
                            + Text("\n较小的文件保存到哪里,以及是否替换原件").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("files.pdf.optimisedPDFBehaviour", namesControl: true)
                    if optimisedPDFBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .pdf, template: $sameFolderNameTemplatePDF)
                            .searchAnchor("files.pdf.sameFolderNameTemplatePDF")
                    } else if optimisedPDFBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .pdf, template: $specificFolderNameTemplatePDF)
                            .searchAnchor("files.pdf.specificFolderNameTemplatePDF")
                    }
                }

                if pdfHasTemplateRow {
                    templateVarsCollapsible(for: .pdf)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(4)
    }

    @State private var expandedVars: Set<ClopFileType> = []

    // MARK: - Per-section helpers

    // MARK: Dynamic example extensions for auto-convert rows

    /// Image auto-convert: prefer webp->jpeg; fall back to first-of-toJPEG or first-of-toPNG.
    private var autoImageInputExt: String? {
        if formatsToConvertToJPEG.contains(where: { $0.preferredFilenameExtension == "webp" }) {
            return "webp"
        }
        if let first = formatsToConvertToJPEG.compactMap(\.preferredFilenameExtension).sorted().first {
            return first
        }
        return formatsToConvertToPNG.compactMap(\.preferredFilenameExtension).sorted().first
    }

    private var autoImageOutputExt: String? {
        if formatsToConvertToJPEG.contains(where: { $0.preferredFilenameExtension == "webp" }) || !formatsToConvertToJPEG.isEmpty {
            return "jpeg"
        }
        if !formatsToConvertToPNG.isEmpty {
            return "png"
        }
        return nil
    }

    /// Video auto-convert: first extension from formatsToConvertToMP4; output is always mp4.
    private var autoVideoInputExt: String? {
        formatsToConvertToMP4.compactMap(\.preferredFilenameExtension).sorted().first
    }

    /// Audio auto-convert: first source extension across both target sets; output depends on which set it comes from.
    private var autoAudioInputExt: String? {
        let aacExts = formatsToConvertToAAC.compactMap(\.preferredFilenameExtension).sorted()
        let mp3Exts = formatsToConvertToMP3.compactMap(\.preferredFilenameExtension).sorted()
        return (aacExts + mp3Exts).sorted().first
    }

    private var autoAudioOutputExt: String? {
        guard let inputExt = autoAudioInputExt else { return nil }
        let aacExts = formatsToConvertToAAC.compactMap(\.preferredFilenameExtension)
        if aacExts.contains(inputExt) {
            return "m4a"
        }
        let mp3Exts = formatsToConvertToMP3.compactMap(\.preferredFilenameExtension)
        if mp3Exts.contains(inputExt) {
            return "mp3"
        }
        return nil
    }

    private var imageHasTemplateRow: Bool {
        [optimisedImageBehaviour, convertedImageBehaviour, manualConvertedImageBehaviour].contains(where: { $0 == .sameFolder || $0 == .specificFolder })
    }

    private var videoHasTemplateRow: Bool {
        [optimisedVideoBehaviour, convertedVideoBehaviour, manualConvertedVideoBehaviour].contains(where: { $0 == .sameFolder || $0 == .specificFolder })
    }

    private var audioHasTemplateRow: Bool {
        [optimisedAudioBehaviour, convertedAudioBehaviour, manualConvertedAudioBehaviour].contains(where: { $0 == .sameFolder || $0 == .specificFolder })
    }

    private var pdfHasTemplateRow: Bool {
        optimisedPDFBehaviour == .sameFolder || optimisedPDFBehaviour == .specificFolder
    }

    private var imageAutoConvertGroups: [ConvertGroup] {
        var groups: [ConvertGroup] = []
        let toJPEG = formatsToConvertToJPEG.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        if !toJPEG.isEmpty {
            groups.append(ConvertGroup(
                sources: toJPEG,
                target: "JPEG",
                sourceTint: .red,
                targetTint: Color(red: 1.0, green: 0.83, blue: 0.0),
                sourceTextColor: sourceAdaptive,
                targetTextColor: jpegAdaptive
            ))
        }
        let toPNG = formatsToConvertToPNG.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        if !toPNG.isEmpty {
            groups.append(ConvertGroup(
                sources: toPNG,
                target: "PNG",
                sourceTint: Color(red: 1.0, green: 0.5, blue: 0.0),
                targetTint: .blue,
                sourceTextColor: orangeAdaptive,
                targetTextColor: pngAdaptive
            ))
        }
        return groups
    }

    private var videoAutoConvertGroups: [ConvertGroup] {
        let fmts = formatsToConvertToMP4.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        guard !fmts.isEmpty else { return [] }
        return [ConvertGroup(
            sources: fmts,
            target: "MP4",
            sourceTint: .red,
            targetTint: Color(red: 0.6, green: 0.3, blue: 0.9),
            sourceTextColor: sourceAdaptive,
            targetTextColor: mp4Adaptive
        )]
    }

    private var audioAutoConvertGroups: [ConvertGroup] {
        var groups: [ConvertGroup] = []
        let toAAC = formatsToConvertToAAC.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        if !toAAC.isEmpty {
            groups.append(ConvertGroup(
                sources: toAAC,
                target: "AAC (M4A)",
                sourceTint: .red,
                targetTint: Color(red: 0.2, green: 0.8, blue: 0.4),
                sourceTextColor: sourceAdaptive,
                targetTextColor: audioAdaptive
            ))
        }
        let toMP3 = formatsToConvertToMP3.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        if !toMP3.isEmpty {
            groups.append(ConvertGroup(
                sources: toMP3,
                target: "MP3",
                sourceTint: Color(red: 1.0, green: 0.5, blue: 0.0),
                targetTint: .blue,
                sourceTextColor: orangeAdaptive,
                targetTextColor: pngAdaptive
            ))
        }
        return groups
    }

    @ViewBuilder
    private func templateVarsCollapsible(for type: ClopFileType) -> some View {
        let expanded = expandedVars.contains(type)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeOut(duration: 0.15)) {
                if expandedVars.contains(type) {
                    expandedVars.remove(type)
                } else {
                    expandedVars.insert(type)
                }
            }}) {
                HStack(spacing: 5) {
                    SwiftUI.Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.semibold(9)).foregroundColor(.secondary)
                    Text("模板变量").semibold(12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text("""
                        **Date**                | **Time**
                        --------------------|-----------------
                        Year             **%y** | Hour     **%H**
                        Month (numeric)  **%m** | Minutes  **%M**
                        Month (name)     **%n** | Seconds  **%S**
                        Day              **%d** | AM/PM    **%p**
                        Weekday          **%w** |
                        """)
                        Spacer()
                        Text("""
                        Source file path (without name)        **%P**
                        Source file name (without extension)   **%f**
                        Source file extension                  **%e**

                        Random characters                      **%r**
                        Auto-incrementing number               **%i**
                        """)
                    }
                    .font(.mono(11, weight: .light))
                    .foregroundColor(.secondary)
                    .padding(6)
                }
                .padding(.top, 6)
            }
        }
        .padding(.top, 4)
    }

}

struct AudioSettingsView: View {
    @Default(.audioDirs) var audioDirs
    @Default(.audioCoverArt) var audioCoverArt
    @Default(.audioBitrate) var audioBitrate
    @Default(.audioCompression) var audioCompression
    @Default(.audioFormatsToSkip) var audioFormatsToSkip
    @Default(.formatsToConvertToAAC) var formatsToConvertToAAC
    @Default(.formatsToConvertToMP3) var formatsToConvertToMP3
    @Default(.maxAudioSizeMB) var maxAudioSizeMB
    @Default(.minAudioSizeKB) var minAudioSizeKB
    @Default(.maxAudioFileCount) var maxAudioFileCount
    @Default(.enableAutomaticAudioOptimisations) var enableAutomaticAudioOptimisations

    /// Reveals what the abstract percentage maps to in real bitrates (all formats use VBR).
    var audioCompressionCaption: String {
        let aac = audioCompression.audioBitrate(for: .aac) ?? 0
        let mp3 = audioCompression.audioBitrate(for: .mp3) ?? 0
        return "Around \(aac) kbps for AAC, \(mp3) for MP3 (variable bitrate). WAV, AIFF and FLAC are lossless, so the compression factor does not apply to them."
    }

    var body: some View {
        CompatibilityScrollForm {
            Section(header: SectionHeader(title: "监视路径", subtitle: "这些文件夹里出现的音频会被自动优化")) {
                DirListView(fileType: .audio, dirs: $audioDirs, enabled: $enableAutomaticAudioOptimisations)
            }
            .searchAnchor("audio.watchpaths.audioDirs")
            Section(header: SectionHeader(title: "优化规则")) {
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "folder.badge.gearshape")
                    Text("文件去向设置于").foregroundColor(.secondary)
                    Button("文件处理") { settingsViewManager.tab = .files }.buttonStyle(.link)
                }.font(.system(size: 11))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("压缩").regular(13)
                            .searchAnchor("audio.optimisationrules.audioCompression")
                        Slider(
                            value: Binding(
                                get: { Double(audioCompression.factor) },
                                set: { audioCompression.factor = Int($0.rounded()) }
                            ),
                            in: 5 ... 100, step: 1
                        )
                        .accessibilityLabel("压缩")
                        Text("\(audioCompression.factor)%")
                            .mono(11).foregroundColor(.secondary).frame(width: 38, alignment: .trailing)
                    }
                    Text(audioCompressionCaption).round(10, weight: .regular).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: $audioCoverArt) {
                        ForEach(AudioCoverArtBehaviour.allCases, id: \.self) { behaviour in
                            Text(behaviour.name).tag(behaviour)
                        }
                    } label: {
                        Text("封面图").regular(13)
                            .searchAnchor("audio.optimisationrules.audioCoverArt")
                    }
                    .accessibilityLabel("封面图")
                    Text("仅 AAC、MP3、FLAC 等可存储封面的格式会保留封面图,其余格式会丢弃。")
                        .round(10, weight: .regular).foregroundColor(.secondary)
                }
            }
            Section(header: SectionHeader(title: "监视文件过滤", subtitle: "只有在此范围内的文件会被优化")) {
                FileSizeRangeRow(minKB: $minAudioSizeKB, maxMB: $maxAudioSizeMB)
                    .searchAnchor("audio.watchedfilefilters.minAudioSizeKB")
                CountSliderRow(count: $maxAudioFileCount, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "audio file is" : "audio files are") copied or moved at once" })
                    .searchAnchor("audio.watchedfilefilters.maxAudioFileCount")
            }
            Section(header: SectionHeader(title: "兼容性", subtitle: "优化前把兼容性差的格式转换为 AAC 或 MP3;未勾选的格式保持原样")) {
                HStack {
                    (Text("转换为 ").regular(13) + Text("AAC (M4A)").mono(13)).padding(.trailing, 10)
                    Spacer()
                    ForEach(FORMATS_CONVERTIBLE_TO_COMPRESSED_AUDIO, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension ?? format.identifier) {
                            formatsToConvertToAAC.toggle(format)
                            if formatsToConvertToAAC.contains(format) {
                                formatsToConvertToMP3.remove(format)
                            }
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToAAC.contains(format) }))
                            .font(.mono(11))
                    }
                }
                HStack {
                    (Text("转换为 ").regular(13) + Text("MP3").mono(13)).padding(.trailing, 10)
                    Spacer()
                    ForEach(FORMATS_CONVERTIBLE_TO_COMPRESSED_AUDIO, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension ?? format.identifier) {
                            formatsToConvertToMP3.toggle(format)
                            if formatsToConvertToMP3.contains(format) {
                                formatsToConvertToAAC.remove(format)
                            }
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToMP3.contains(format) }))
                            .font(.mono(11))
                    }
                }
            }
            .id("compatibility")
            .searchAnchor("audio.compatibility.formatsToConvertToMP3")
            .searchAnchor("audio.compatibility.formatsToConvertToAAC")
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct ImagesSettingsView: View {
    @Default(.imageDirs) var imageDirs
    @Default(.formatsToConvertToJPEG) var formatsToConvertToJPEG
    @Default(.formatsToConvertToPNG) var formatsToConvertToPNG
    @Default(.maxImageSizeMB) var maxImageSizeMB
    @Default(.minImageSizeKB) var minImageSizeKB
    @Default(.minImageResolution) var minImageResolution
    @Default(.maxImageResolution) var maxImageResolution
    @Default(.imageFormatsToSkip) var imageFormatsToSkip
    @Default(.adaptiveImageSize) var adaptiveImageSize
    @Default(.imageCompression) var imageCompression
    @Default(.convertHDRToSDR) var convertHDRToSDR
    // @Default(.downscaleRetinaImages) var downscaleRetinaImages
    @Default(.maxImageFileCount) var maxImageFileCount
    @Default(.copyImageFilePath) var copyImageFilePath
    @Default(.customNameTemplateForClipboardImages) var customNameTemplateForClipboardImages
    @Default(.useCustomNameTemplateForClipboardImages) var useCustomNameTemplateForClipboardImages
    @Default(.enablePhotosIntegration) var enablePhotosIntegration
    @Default(.maxCopiedPhotosCount) var maxCopiedPhotosCount
    @Default(.maxPhotosLength) var maxPhotosLength
    @Default(.photoCropOrientation) var photoCropOrientation

    @Default(.useAggressiveOptimisationJPEG) var useAggressiveOptimisationJPEG
    @Default(.useAggressiveOptimisationPNG) var useAggressiveOptimisationPNG
    @Default(.useAggressiveOptimisationGIF) var useAggressiveOptimisationGIF
    @Default(.gifFrameDropBehaviour) var gifFrameDropBehaviour
    @Default(.enableAutomaticImageOptimisations) var enableAutomaticImageOptimisations

    var maxPhotosLengthBinding: Binding<String> {
        Binding(
            get: { maxPhotosLength?.description ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Int(trimmed) {
                    maxPhotosLength = val.capped(between: 1, and: 20000)
                } else {
                    maxPhotosLength = nil
                }
            }
        )
    }

    var customNameTemplate: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("自定义命名模板").regular(13)
                + Text("\n复制路径到剪贴板前,按此模板重命名文件").round(11, weight: .regular).foregroundColor(.secondary)

            VStack(alignment: .leading) {
                TextField("", text: $customNameTemplateForClipboardImages, prompt: Text(DEFAULT_NAME_TEMPLATE))
                    .accessibilityLabel("自定义命名模板")
                    .frame(width: TEXT_FIELD_WIDTH, height: 18, alignment: .leading)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.gray.opacity(useCustomNameTemplateForClipboardImages ? 1 : 0.35), lineWidth: 1).scaleEffect(y: TEXT_FIELD_SCALE)
                            .offset(x: TEXT_FIELD_OFFSET)
                    )
                    .disabled(!useCustomNameTemplateForClipboardImages)
                    .searchAnchor("images.main.customNameTemplateForClipboardImages", namesControl: true)
                if useCustomNameTemplateForClipboardImages {
                    Text("结果:" + generateFileName(template: customNameTemplateForClipboardImages ?! DEFAULT_NAME_TEMPLATE, autoIncrementingNumber: &Defaults[.lastAutoIncrementingNumber]))
                        .round(12)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)
                        .offset(x: 6)
                }
            }
            if useCustomNameTemplateForClipboardImages {
                Text("""
                **Date**                | **Time**
                --------------------|-----------------
                Year             **%y** | Hour     **%H**
                Month (numeric)  **%m** | Minutes  **%M**
                Month (name)     **%n** | Seconds  **%S**
                Day              **%d** | AM/PM    **%p**
                Weekday          **%w** |

                Random characters **%r**
                Auto-incrementing number **%i**
                """)
                .mono(12, weight: .light)
                .foregroundColor(.secondary)
                .padding(.top, 6)
            }
        }

    }

    var cropOrientationPicker: some View {
        Picker("方向", selection: $photoCropOrientation) {
            Label("高度", systemImage: "rectangle.portrait").tag(CropOrientation.portrait)
                .help("缩放图像直到高度不大于指定值。")
            Label("最长边", systemImage: "sparkles.rectangle.stack").tag(CropOrientation.adaptive)
                .help("缩放图像直到最长边不大于指定值。")
            Label("宽度", systemImage: "rectangle").tag(CropOrientation.landscape)
                .help("缩放图像直到宽度不大于指定值。")
        }
        .labelsHidden()
        .fixedSize()
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
        .font(.heavy(10))
        .searchAnchor("images.main.photoCropOrientation")
    }

    var body: some View {
        CompatibilityScrollForm {
            Section(header: SectionHeader(title: "监视路径", subtitle: "这些文件夹里出现的图像会被自动优化")) {
                DirListView(fileType: .image, dirs: $imageDirs, enabled: $enableAutomaticImageOptimisations)
            }
            .searchAnchor("images.watchpaths.imageDirs")
            Section(header: SectionHeader(title: "文件名处理")) {
                Toggle(isOn: $copyImageFilePath) {
                    Text("复制图像路径").regular(13)
                        + Text("\n拷贝优化后的图像数据时,同时复制图像文件路径").round(11, weight: .regular).foregroundColor(.secondary)
                }
                .searchAnchor("images.filenamehandling.copyImageFilePath", namesControl: true)
                Toggle(isOn: $useCustomNameTemplateForClipboardImages.animation(.default)) {
                    customNameTemplate
                }.disabled(!copyImageFilePath)
                    .accessibilityLabel("自定义命名模板")
                    .searchAnchor("images.filenamehandling.useCustomNameTemplateForClipboardImages")
            }

            Section(header: SectionHeader(title: "「照片」集成", subtitle: "处理从「照片」应用拷贝的图像")) {
                Toggle(isOn: $enablePhotosIntegration.animation(.spring())) {
                    Text("优化从「照片」应用拷贝的图像").regular(13)
                }
                .searchAnchor("images.photosintegration.enablePhotosIntegration", namesControl: true)

                CountSliderRow(count: $maxCopiedPhotosCount, range: 1 ... 50, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "photo is" : "photos are") copied at once" })
                    .disabled(!enablePhotosIntegration)
                    .searchAnchor("images.photosintegration.maxCopiedPhotosCount")

                HStack(spacing: 6) {
                    Text("缩小到").regular(13).lineLimit(1).fixedSize()
                        .searchAnchor("images.photosintegration.maxPhotosLength")
                    // No .fixedSize() here: it collapses the field to its ideal width, which is ~0
                    // while the value is unset, leaving nothing to click inside the 70pt frame.
                    TextField("", text: maxPhotosLengthBinding)
                        .accessibilityLabel("缩小到")
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70, alignment: .trailing)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.gray, lineWidth: 1).scaleEffect(y: TEXT_FIELD_SCALE).offset(x: TEXT_FIELD_OFFSET))
                    Text("px").mono(13).opacity(maxPhotosLength != nil ? 1 : 0.3).lineLimit(1).fixedSize()
                    Text("on").regular(13).lineLimit(1).fixedSize()
                        .searchAnchor("images.photosintegration.photoCropOrientation")
                    Spacer()
                    cropOrientationPicker
                }
                .disabled(!enablePhotosIntegration)
            }

            Section(header: SectionHeader(title: "优化规则")) {
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "folder.badge.gearshape")
                    Text("文件去向设置于").foregroundColor(.secondary)
                    Button("文件处理") { settingsViewManager.tab = .files }.buttonStyle(.link)
                }.font(.system(size: 11))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("压缩").regular(13)
                            .searchAnchor("images.optimisationrules.imageCompression")
                        Slider(
                            value: Binding(
                                get: { Double(imageCompression.factor) },
                                set: { imageCompression.factor = Int($0.rounded()) }
                            ),
                            in: 5 ... 100, step: 1
                        )
                        .accessibilityLabel("压缩")
                        .disabled(imageCompression.tier == .adaptive)
                        Text("\(imageCompression.factor)%")
                            .mono(11).foregroundColor(.secondary)
                            .opacity(imageCompression.tier == .adaptive ? 0.2 : 1)
                            .frame(width: 38, alignment: .trailing)
                        Button("自适应") {
                            imageCompression.tier = imageCompression.tier == .adaptive ? .custom : .adaptive
                        }
                        .buttonStyle(ToggleButton(isOn: .oneway { imageCompression.tier == .adaptive }))
                        .font(.mono(11))
                        .help("细节丰富的图像转为 JPEG、低细节的转为 PNG,忽略压缩系数所指的格式")
                    }
                    if imageCompression.tier == .adaptive {
                        Text("Clop 会根据图像信息量自动在 JPEG 和 PNG 之间选择,并自适应地选取合适的压缩系数")
                            .round(10, weight: .regular).foregroundColor(.secondary)
                    }
                }
                Picker(selection: $gifFrameDropBehaviour) {
                    Text("加速播放").tag(GIFFrameDropBehaviour.playFaster)
                    Text("保持时长(动作更卡顿)").tag(GIFFrameDropBehaviour.keepDuration)
                } label: {
                    Text("GIF 丢帧").regular(13)
                        + Text("\n压缩系数高于 80% 时,动图 GIF 会每 4、3 或 2 帧丢 1 帧:可让动画用剩余帧播得更快,也可保持时长、每帧显示更久").round(
                            11,
                            weight: .regular
                        ).foregroundColor(.secondary)
                }
                .searchAnchor("images.optimisationrules.gifFrameDropBehaviour", namesControl: true)
                Toggle(isOn: $convertHDRToSDR) {
                    Text("将 HDR 转换为 SDR").regular(13)
                }
                .searchAnchor("images.optimisationrules.convertHDRToSDR", namesControl: true)
                // Toggle(isOn: $downscaleRetinaImages) {
                //     Text("将 HiDPI 图像降采样到 72 DPI").regular(13)
                //         + Text("\n把 HiDPI 屏幕拍摄的图像缩到网页标准 DPI(如 Retina 降到 1x)").round(11, weight: .regular).foregroundColor(.secondary)
                // }

            }
            Section(header: SectionHeader(title: "监视文件过滤", subtitle: "只有在此范围内的文件会被优化")) {
                FileSizeRangeRow(minKB: $minImageSizeKB, maxMB: $maxImageSizeMB)
                    .searchAnchor("images.watchedfilefilters.minImageSizeKB")
                ResolutionRangeRow(label: "Resolution", minRes: $minImageResolution, maxRes: $maxImageResolution)
                    .searchAnchor("images.watchedfilefilters.minImageResolution")
                CountSliderRow(count: $maxImageFileCount, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "image is" : "images are") copied or moved at once" })
                    .searchAnchor("images.watchedfilefilters.maxImageFileCount")
                HStack {
                    Text("忽略这些扩展名的图像").regular(13).padding(.trailing, 10)
                        .searchAnchor("images.watchedfilefilters.imageFormatsToSkip")
                    Spacer()

                    ForEach(IMAGE_FORMATS, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            imageFormatsToSkip.toggle(format)
                        }.buttonStyle(ToggleButton(isOn: .oneway { imageFormatsToSkip.contains(format) }))
                            .font(.mono(11))
                    }
                }
            }
            Section(header: SectionHeader(title: "兼容性", subtitle: "优化前把小众格式转换为更兼容的格式")) {
                HStack {
                    (Text("转换为 ").regular(13) + Text("jpeg").mono(13)).padding(.trailing, 10)
                        .searchAnchor("images.compatibility.formatsToConvertToJPEG")
                    Spacer()

                    ForEach(FORMATS_CONVERTIBLE_TO_JPEG, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            formatsToConvertToJPEG.toggle(format)
                            if formatsToConvertToJPEG.contains(format) {
                                formatsToConvertToPNG.remove(format)
                            }
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToJPEG.contains(format) }))
                            .font(.mono(11))
                    }
                }
                HStack {
                    (Text("转换为 ").regular(13) + Text("png").mono(13)).padding(.trailing, 10)
                        .searchAnchor("images.compatibility.formatsToConvertToPNG")
                    Spacer()

                    ForEach(FORMATS_CONVERTIBLE_TO_PNG, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            formatsToConvertToPNG.toggle(format)
                            if formatsToConvertToPNG.contains(format) {
                                formatsToConvertToJPEG.remove(format)
                            }
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToPNG.contains(format) }))
                            .font(.mono(11))
                    }
                }
            }
            .id("compatibility")

        }
        .scrollContentBackground(.hidden)
        .padding(4)
    }
}

class BoundFormatter: Formatter {
    init(min: Int, max: Int) {
        self.max = max
        self.min = min
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    var min = 0
    var max = 0

    override func string(for obj: Any?) -> String? {
        guard let number = obj as? Int else {
            return nil
        }
        return String(number.capped(between: min, and: max))

    }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard let number = Int(string) else {
            return false
        }

        obj?.pointee = number.capped(between: min, and: max) as AnyObject

        return true
    }
}

let RESIZE_KEYS = SauceKey.NUMBER_KEYS.suffix(from: 1).arr

let keyEnv = EnvState()
struct KeysSettingsView: View {
    @Default(.enabledKeys) var enabledKeys
    @Default(.quickResizeKeys) var quickResizeKeys
    @Default(.keyComboModifiers) var keyComboModifiers

    var resizeKeys: some View {
        ForEach(RESIZE_KEYS, id: \.QWERTYKeyCode) { key in
            let number = key.character
            VStack(spacing: 1) {
                Button(number) {
                    quickResizeKeys = quickResizeKeys.contains(key)
                        ? quickResizeKeys.without(key)
                        : quickResizeKeys.with(key)
                }
                .buttonStyle(
                    ToggleButton(isOn: .oneway { quickResizeKeys.contains(key) })
                )
                Text("\(number)0%")
                    .mono(10)
                    .foregroundColor(.secondary)
            }
        }
    }

    var body: some View {
        Form {
            Section(header: SectionHeader(title: "触发键")) {
                DirectionalModifierView(triggerKeys: $keyComboModifiers, showFnCaps: false, allowShiftAlone: false)
            }
            .searchAnchor("keys.triggerkeys.keyComboModifiers")
            Section(header: SectionHeader(title: "操作键")) {
                keyToggle(.minus, actionName: "Downscale", description: "降低最近图像或视频的分辨率")
                keyToggle(.x, actionName: "Speed up video", description: "丢帧加速视频播放")
                keyToggle(.delete, actionName: "停止并关闭", description: "停止上一个操作并关闭悬浮结果")
                keyToggle(.escape, actionName: "停止并全部清空", description: "停止正在运行的优化并清空全部悬浮结果")
                keyToggle(.equal, actionName: "Bring Back", description: "找回上个被移除的悬浮结果")
                keyToggle(.space, actionName: "QuickLook", description: "预览最近的图像或视频")
                keyToggle(.r, actionName: "Rename", description: "重命名最近的图像或视频")
                keyToggle(.z, actionName: "Restore original", description: "撤销对最近图像或视频的优化与缩放")
                keyToggle(.p, actionName: "暂停优化", description: "暂停或停止自动优化")
                keyToggle(.c, actionName: "优化当前剪贴板", description: "对拷贝的图像、URL 或路径执行优化")
                keyToggle(.a, actionName: "激进优化", description: "对拷贝的图像、URL 或路径执行激进优化")
            }.padding(.leading, 20)
                .searchAnchor("keys.actionkeys.enabledKeys")
            Section(header: SectionHeader(title: "缩放键")) {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("按住触发键并").round(12, weight: .regular)
                        Text("按数字键缩放到").mono(10).foregroundColor(.secondary)
                    }
                    VStack(spacing: 1) {
                        triggerKeyCap
                        // Kept for vertical alignment with the number keys' percentage labels, but hidden.
                        Text("按住").mono(10).foregroundColor(.secondary).hidden()
                    }
                    resizeKeys
                }.fixedSize()
            }.padding(.leading, 20)
                .searchAnchor("keys.resizekeys.quickResizeKeys")
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity)
        .environmentObject(keyEnv)
    }

    /// A static key-cap rendering of the configured trigger modifiers, one separate cap per modifier (e.g.
    /// ⌃ ⇧), shown to the left of each action/resize key so it's obvious those modifiers must be held
    /// together with that key. Styled lighter than the action keys (secondary text, fainter fill) so it
    /// reads as the held prefix, not the key itself.
    var triggerKeyCap: some View {
        HStack(spacing: 3) {
            ForEach(keyComboModifiers) { key in
                Text(key.str)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
        }
    }

    @ViewBuilder
    func keyToggle(_ key: SauceKey, actionName: String, description: String) -> some View {
        let binding = Binding(
            get: { enabledKeys.contains(key) },
            set: { enabledKeys = $0 ? enabledKeys.with(key) : enabledKeys.without(key) }
        )
        Toggle(isOn: binding, label: {
            HStack {
                triggerKeyCap
                DynamicKey(key: .constant(key))
                    .font(.mono(15, weight: SauceKey.ALPHANUMERIC_KEYS.contains(key) ? .medium : .heavy))
                VStack(alignment: .leading, spacing: -1) {
                    Text(actionName)
                    Text(description).mono(10)
                }
            }
        })
        .accessibilityLabel(actionName)
        .accessibilityHint(description)
    }

}

import LowtechIndie
import LowtechPro
import LowtechProSentry

struct MadeBy: View {
    var body: some View {
        HStack(spacing: 6) {
            SwiftUI.Image("lowtech")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .opacity(0.7)
            Text("按")
            Link("The low-tech guys", destination: "https://lowtechguys.com/".url!)
                .bold()
                .foregroundColor(.primary)
                .underline()
        }
        .font(.mono(12, weight: .regular))
        .kerning(-0.5)
    }
}

struct LicenseUpdatesSettingsView: View {
    @ObservedObject var um: UpdateManager = UM
    @ObservedObject var pm: ProManager = PM

    var body: some View {
        if let pro = pm.pro, let updater = um.updater {
            Form {
                LicenseAndUpdatesView(pro: pro, updater: updater, appName: "Clop", changelogURL: URL(string: "https://files.lowtechguys.com/clop/changelog.html"))
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } else {
            ProgressView()
                .fill()
        }
    }
}

struct AboutSettingsView: View {
    @ObservedObject var um: UpdateManager = UM
    @ObservedObject var pm: ProManager = PM

    var body: some View {
        AboutView(
            appName: "Clop",
            pro: pm.pro,
            updater: um.updater,
            websiteURL: URL(string: "https://lowtechguys.com/clop"),
            contactURL: URL(string: "https://lowtechguys.com/contact?app=Clop"),
            discordURL: URL(string: "https://discord.gg/YeTuy6adXk"),
            sourceURL: URL(string: "https://github.com/FuzzyIdeas/Clop"),
            changelogURL: URL(string: "https://files.lowtechguys.com/clop/changelog.html")
        )
        .fill()
    }
}

import SymbolPicker

struct IconPickerView: View {
    @Binding var icon: String

    var body: some View {
        Button {
            iconPickerPresented = true
        } label: {
            SwiftUI.Image(systemName: icon)
        }
        .accessibilityLabel("图标")
        .sheet(isPresented: $iconPickerPresented) {
            // Keeps the category this picker has always opened on: the default became `all` in
            // SymbolPicker 2.1.0.
            SymbolPicker(symbol: $icon, initialCategories: ["cameraandphotos"])
        }
    }

    @State private var iconPickerPresented = false

}

struct DropZoneSettingsView: View {
    @Default(.enableDragAndDrop) var enableDragAndDrop
    @Default(.onlyShowDropZoneOnOption) var onlyShowDropZoneOnOption
    @Default(.autoCopyToClipboard) var autoCopyToClipboard
    @Default(.floatingResultsCorner) var floatingResultsCorner
    @Default(.useBatchModeForFolders) var useBatchModeForFolders
    @Default(.batchModeFileCountThreshold) var batchModeFileCountThreshold

    var toggles: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "投放区", subtitle: "把文件、路径和 URL 拖到全局投放区即可优化")
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $enableDragAndDrop) {
                    Text("启用投放区").regular(13)
                        + Text("\n允许把文件、路径和 URL 拖到全局投放区进行优化").round(11, weight: .regular).foregroundColor(.secondary)
                }
                .searchAnchor("dropzone.dropzone.enableDragAndDrop")
                Toggle(isOn: $onlyShowDropZoneOnOption) {
                    Text("需要按住 ⌥ Option 才显示投放区").regular(13)
                        + Text("\n默认隐藏投放区,拖文件时不打扰;按一次 ⌥ Option 手动显示").round(11, weight: .regular).foregroundColor(.secondary)
                }
                .padding(.leading, 20)
                .disabled(!enableDragAndDrop)
                .searchAnchor("dropzone.dropzone.onlyShowDropZoneOnOption")
                Toggle(isOn: $autoCopyToClipboard) {
                    Text("自动将优化后的文件复制到剪贴板").regular(13)
                        + Text("\n复制投放区或文件夹监视优化产生的文件,\n优化结束后即可直接粘贴").round(11, weight: .regular).foregroundColor(.secondary)
                }
                .searchAnchor("dropzone.dropzone.autoCopyToClipboard")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    var preview: some View {
        VStack(spacing: 8) {
            DropZoneView()
                .disabled(!enableDragAndDrop)
                .saturation(enableDragAndDrop ? 1 : 0.5)
                .preview(true)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.gray.opacity(0.2), lineWidth: 2))
                .fixedSize()

            Text("把文件拖到投放区即可优化")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 24) {
                    toggles
                    Spacer()
                    preview
                }
                .frame(height: 250)
                .padding(.horizontal)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "批量模式", subtitle: "大量拖入时在原生窗口中快速处理,而非每个文件一个悬浮结果")
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $useBatchModeForFolders) {
                            Text("大量拖入时使用批量模式").regular(13)
                                + Text("\n一次拖入大量文件(或含大量文件的文件夹)会打开一个批量窗口统一高效优化。原件会先备份,可随时恢复。").round(
                                    11,
                                    weight: .regular
                                ).foregroundColor(.secondary)
                        }
                        .searchAnchor("dropzone.batchmode.useBatchModeForFolders")
                        HStack {
                            Text("拖入超过此数量时切换为批量模式").regular(13)
                            Spacer()
                            TextField("", value: $batchModeFileCountThreshold, format: .number)
                                .accessibilityLabel("拖入超过此数量时切换为批量模式")
                                .multilineTextAlignment(.center)
                                .font(.mono(12))
                                .frame(width: 60)
                                .searchAnchor("dropzone.batchmode.batchModeFileCountThreshold", namesControl: true)
                            Text("个文件").regular(13)
                        }
                        .disabled(!useBatchModeForFolders)
                        .opacity(useBatchModeForFolders ? 1 : 0.6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "自动化", subtitle: "对拖到这里 的文件执行操作:转换、裁剪、复制、重命名等")
                    SourceAutomationsSection(source: .dropZone)
                        .disabled(!enableDragAndDrop)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
                .id("automation")
            }
            .padding(.top)
        }
        .hfill()
        .scrollsToAutomation()
    }
}

struct PresetZonesSettingsView: View {
    @Default(.enableDragAndDrop) var enableDragAndDrop
    @Default(.onlyShowPresetZonesOnControlTapped) var onlyShowPresetZonesOnControlTapped
    @Default(.presetZones) var presetZones

    @ObservedObject var svm = settingsViewManager

    var previews: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 14) {
            GridRow {
                zonePreview(.image)
                zonePreview(.video)
            }
            GridRow {
                zonePreview(.audio)
                zonePreview(.pdf)
            }
        }
        .hfill()
        .padding(.vertical, 4)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section(header: SectionHeader(title: "预设区显示方式", subtitle: "预设区在投放区上的呈现方式")) {
                    Picker("按住或点按 **⌃ Control** 键显示预设区", selection: $onlyShowPresetZonesOnControlTapped) {
                        Text("按住").tag(false)
                        Text("点按").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .searchAnchor("presetZones.showingpresetzones.onlyShowPresetZonesOnControlTapped")
                }

                Section(header: SectionHeader(title: "预设区", subtitle: "点按预设区可指派或新建管线;把文件拖到预设区即运行其操作。")) {
                    previews

                    if let id = svm.editingPresetZoneID, let zone = presetZones.first(where: { $0.id == id }) {
                        PresetZoneRow(zone: zone) { svm.editingPresetZoneID = nil }
                            .id("editor-\(id)")
                            .padding(.top, 6)
                    }
                }
                .searchAnchor("presetZones.presetzones.presetZones")
            }
            .padding(4)
            .disabled(!enableDragAndDrop)
            .saturation(enableDragAndDrop ? 1 : 0.5)
            .onChange(of: svm.editingPresetZoneID) { id in
                guard let id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { proxy.scrollTo("editor-\(id)", anchor: .center) }
                }
            }
        }
        .hfill()
    }

    func zonePreview(_ type: ClopFileType) -> some View {
        VStack(spacing: 6) {
            DropZoneView(presetFileType: type)
                .preview(true)
            HStack(spacing: 4) {
                SwiftUI.Image(systemName: type.symbolName)
                Text(typeName(type))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(type.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(type.color.opacity(0.15)))
            .padding(.top, 1)
        }
    }

    func typeName(_ t: ClopFileType) -> String {
        t == .pdf ? "PDF" : t.description.capitalized
    }

}

struct FloatingSettingsView: View {
    @Default(.enableFloatingResults) var enableFloatingResults
    @Default(.showCompactImages) var showCompactImages
    @Default(.autoHideFloatingResults) var autoHideFloatingResults
    @Default(.autoHideFloatingResultsAfter) var autoHideFloatingResultsAfter
    @Default(.autoHideClipboardResultAfter) var autoHideClipboardResultAfter
    @Default(.autoClearAllCompactResultsAfter) var autoClearAllCompactResultsAfter
    @Default(.floatingResultsCorner) var floatingResultsCorner
    @Default(.alwaysShowCompactResults) var alwaysShowCompactResults
    @Default(.hideFloatingResultTooltips) var hideFloatingResultTooltips
    @Default(.floatingResultActions) var floatingResultActions
    @Default(.compactResultActions) var compactResultActions
    @Default(.formatPickerStyle) var formatPickerStyle
    @Default(.followCursorScreen) var followCursorScreen
    @Default(.showCopyClearButtons) var showCopyClearButtons

    @Default(.dismissFloatingResultOnDrop) var dismissFloatingResultOnDrop
    @Default(.dismissFloatingResultOnUpload) var dismissFloatingResultOnUpload
    @Default(.dismissCompactResultOnDrop) var dismissCompactResultOnDrop
    @Default(.dismissCompactResultOnUpload) var dismissCompactResultOnUpload

    @State var compact = SWIFTUI_PREVIEW

    var settings: some View {
        Form {
            Toggle(isOn: $enableFloatingResults) {
                Text("显示悬浮结果").regular(13)
                    + Text("\n\n关闭后 Clop 将以无界面模式运行,但仍会在后台优化文件。投放区可在「投放区」标签页单独关闭")
                    .round(10, weight: .regular)
                    .foregroundColor(.secondary)
            }
            .searchAnchor("floating.main.enableFloatingResults", namesControl: true)
            Section(header: SectionHeader(title: "布局")) {
                Picker("屏幕位置", selection: $floatingResultsCorner) {
                    Text("右下").tag(ScreenCorner.bottomRight)
                    Text("左下").tag(ScreenCorner.bottomLeft)
                    Text("右上").tag(ScreenCorner.topRight)
                    Text("左上").tag(ScreenCorner.topLeft)
                }
                .searchAnchor("floating.layout.floatingResultsCorner", namesControl: true)
                Toggle(isOn: $followCursorScreen) {
                    Text("跟随光标跨屏幕移动").regular(13)
                        + Text("\n\n光标在另一块屏幕停留几秒后,结果会自动移过去")
                        .round(10, weight: .regular)
                        .foregroundColor(.secondary)
                }
                .searchAnchor("floating.layout.followCursorScreen", namesControl: true)
                Toggle(isOn: $hideFloatingResultTooltips) {
                    Text("隐藏按钮提示").regular(13)
                        + Text("\n\n悬停结果按钮上时不弹出操作名称标签")
                        .round(10, weight: .regular)
                        .foregroundColor(.secondary)
                }
                .searchAnchor("floating.layout.hideFloatingResultTooltips", namesControl: true)
                Toggle(isOn: $alwaysShowCompactResults) {
                    Text("始终使用紧凑布局").regular(13)
                        + Text("\n\n默认情况下,屏幕上结果超过 5 个时自动切换为紧凑布局")
                        .round(10, weight: .regular)
                        .foregroundColor(.secondary)
                }
                .searchAnchor("floating.layout.alwaysShowCompactResults", namesControl: true)
            }.disabled(!enableFloatingResults)

            Section(header: SectionHeader(title: "完整布局")) {
                // Subtitle sits under both the label and the picker so it can wrap across the whole
                // row width instead of being squeezed into the label column by the picker.
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: $formatPickerStyle) {
                        Text("底部格式栏").tag(FormatPickerStyle.bar)
                        Text("悬停在扩展名上").tag(FormatPickerStyle.extensionHover)
                    } label: {
                        Text("切换格式的方式").regular(13)
                    }
                    .searchAnchor("floating.fulllayout.formatPickerStyle", namesControl: true)
                    Text("格式栏把所有可转换格式作为一键分段显示在结果底部;扩展名标签悬停时弹出格式列表")
                        .round(10, weight: .regular)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("显示「全部复制 / 全部清空」按钮", isOn: $showCopyClearButtons)
                    .searchAnchor("floating.fulllayout.showCopyClearButtons", namesControl: true)
                Text("结果消失时间")
                Toggle("拖到外部时", isOn: $dismissFloatingResultOnDrop).padding(.leading, 20)
                    .searchAnchor("floating.fulllayout.dismissFloatingResultOnDrop", namesControl: true)
                Toggle("上传到 Dropshare", isOn: $dismissFloatingResultOnUpload).padding(.leading, 20)
                    .searchAnchor("floating.fulllayout.dismissFloatingResultOnUpload", namesControl: true)

                Toggle("自动隐藏", isOn: $autoHideFloatingResults)
                    .searchAnchor("floating.fulllayout.autoHideFloatingResults", namesControl: true)
                Picker("个文件后", selection: $autoHideFloatingResultsAfter) {
                    Text("5 秒").tag(5)
                    Text("10 秒").tag(10)
                    Text("15 秒").tag(15)
                    Text("30 秒").tag(30)
                    Text("1 分钟").tag(60)
                    Text("2 分钟").tag(120)
                    Text("5 分钟").tag(300)
                    Text("10 分钟").tag(600)
                    Text("从不").tag(0)
                }.disabled(!autoHideFloatingResults).padding(.leading, 20)
                    .searchAnchor("floating.fulllayout.autoHideFloatingResultsAfter", namesControl: true)
                Picker("剪贴板新内容后", selection: $autoHideClipboardResultAfter) {
                    Text("1 秒").tag(1)
                    Text("2 秒").tag(2)
                    Text("3 秒").tag(3)
                    Text("4 秒").tag(4)
                    Text("5 秒").tag(5)
                    Text("10 秒").tag(10)
                    Text("30 秒").tag(30)
                    Text("与常规优化相同").tag(-1)
                    Text("从不").tag(0)
                }.disabled(!autoHideFloatingResults).padding(.leading, 20)
                    .searchAnchor("floating.fulllayout.autoHideClipboardResultAfter", namesControl: true)
            }.disabled(!enableFloatingResults)

            Section(header: SectionHeader(title: "紧凑布局")) {
                Toggle("显示图像", isOn: $showCompactImages)
                    .searchAnchor("floating.compactlayout.showCompactImages", namesControl: true)
                Text("结果消失时间")
                Toggle("拖到外部时", isOn: $dismissCompactResultOnDrop).padding(.leading, 20)
                    .searchAnchor("floating.compactlayout.dismissCompactResultOnDrop", namesControl: true)
                Toggle("上传到 Dropshare", isOn: $dismissCompactResultOnUpload).padding(.leading, 20)
                    .searchAnchor("floating.compactlayout.dismissCompactResultOnUpload", namesControl: true)

                Picker("全部清空时间", selection: $autoClearAllCompactResultsAfter) {
                    Text("5 秒").tag(5)
                    Text("10 秒").tag(10)
                    Text("15 秒").tag(15)
                    Text("30 秒").tag(30)
                    Text("1 分钟").tag(60)
                    Text("2 分钟").tag(120)
                    Text("5 分钟").tag(300)
                    Text("10 分钟").tag(600)
                    Text("30 分钟").tag(1800)
                    Text("从不").tag(0)
                }
                .searchAnchor("floating.compactlayout.autoClearAllCompactResultsAfter", namesControl: true)
            }.disabled(!enableFloatingResults)

        }
        .scrollContentBackground(.hidden)
        // idealWidth keeps the window's fit-to-content width at the old 380pt: without it, the long
        // multiline labels report their unwrapped single-line width as ideal and the pane demands
        // ~1100px. No minWidth so a narrow window squeezes the form instead of clipping it.
        .frame(idealWidth: 380, maxWidth: .infinity)
    }

    var body: some View {
        HStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                settings
            }

            VStack {
                if compact {
                    CompactPreview()
                        .frame(width: THUMB_SIZE.width + 60, height: 550, alignment: .center)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.gray.opacity(0.2), lineWidth: 2))
                        .disabled(!enableFloatingResults)
                        .saturation(enableFloatingResults ? 1 : 0.5)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                FloatingPreview()
                                // Anchor pinned to the very bottom of the list so we can scroll the
                                // "Clear all" / "Copy all" buttons into view by default.
                                Color.clear.frame(height: 1).id("previewBottom")
                            }
                        }
                        .frame(width: THUMB_SIZE.width + 60, height: 550)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.gray.opacity(0.2), lineWidth: 2))
                        .disabled(!enableFloatingResults)
                        .saturation(enableFloatingResults ? 1 : 0.5)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo("previewBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                Picker("布局", selection: $compact) {
                    Text("紧凑").tag(true)
                    Text("完整").tag(false)
                }.pickerStyle(.segmented).frame(width: 200)
                    .labelsHidden()
                Text("仅用于预览")
                    .round(10)
                    .foregroundColor(.secondary)

                Divider().frame(width: 100).padding(.vertical, 4)

                if compact {
                    ActionListPicker(label: "Side actions", vertical: false, actions: $compactResultActions)
                        .searchAnchor("floating.main.compactResultActions")
                } else {
                    FloatingActionGridPicker(actions: $floatingResultActions)
                }
            }
            // The flexible form eats all leftover width, so the preview column needs its own
            // breathing room from the window's right edge.
            .padding(.trailing)
        }
        .hfill()
        .padding(.top)
        .onAppear {
            compact = alwaysShowCompactResults
            // Materialise the preview sample files only now that this tab is on screen.
            FloatingPreview.materializeSamples()
            CompactPreview.materializeSamples()
        }
        .onChange(of: alwaysShowCompactResults) { value in
            compact = value
        }
    }
}
/// One row of the "Edit with external app" settings: shows the chosen app (icon + name) for a file
/// type, or a "Choose app…" button. Any app can be picked; nothing is filtered.
struct EditorAppRow: View {
    let label: String
    let systemImage: String
    let key: Defaults.Key<String>

    var body: some View {
        HStack {
            SwiftUI.Image(systemName: systemImage).foregroundColor(.secondary).frame(width: 20)
            Text(label)
            Spacer()
            if !appPath.isEmpty, FileManager.default.fileExists(atPath: appPath) {
                let url = URL(fileURLWithPath: appPath)
                Button(action: pick) {
                    SwiftUI.Image(nsImage: appIcon(url))
                    Text(appName(url))
                }
                Button(action: clear) {
                    SwiftUI.Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("移除")
                .accessibilityLabel("移除")
            } else {
                Button("选择应用…", action: pick)
            }
        }
        .onAppear { appPath = Defaults[key].resolvedPath }
    }

    @State private var appPath = ""

    private func appIcon(_ url: URL) -> NSImage {
        let i = NSWorkspace.shared.icon(forFile: url.path)
        i.size = NSSize(width: 16, height: 16)
        return i
    }

    private func appName(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.deletingPathExtension().lastPathComponent
    }

    private func clear() {
        appPath = ""
        Defaults[key] = ""
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose an app to edit \(label.lowercased()) with"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            appPath = url.path
            Defaults[key] = url.path.portablePath
        }
    }
}

struct ClipboardSettingsView: View {
    @Default(.optimiseTIFF) var optimiseTIFF
    @Default(.optimiseHEICAVIFClipboard) var optimiseHEICAVIFClipboard
    @Default(.optimiseVideoClipboard) var optimiseVideoClipboard
    @Default(.optimiseAudioClipboard) var optimiseAudioClipboard
    @Default(.optimisePDFClipboard) var optimisePDFClipboard
    @Default(.optimiseImagePathClipboard) var optimiseImagePathClipboard
    @Default(.enableClipboardOptimiser) var enableClipboardOptimiser
    @Default(.clipboardIgnoredAppBundleIds) var clipboardIgnoredAppBundleIds
    @Default(.appendClipboardResults) var appendClipboardResults
    @Default(.copyConsecutiveClipboardImages) var copyConsecutiveClipboardImages
    @Default(.clipboardAccumulationTimeout) var clipboardAccumulationTimeout

    var disabledClipboardTypes: Set<ClopFileType> {
        guard enableClipboardOptimiser else { return Set(ClopFileType.allCases) }
        var disabled: Set<ClopFileType> = []
        if !optimiseVideoClipboard {
            disabled.insert(.video)
        }
        if !optimiseAudioClipboard {
            disabled.insert(.audio)
        }
        if !optimisePDFClipboard {
            disabled.insert(.pdf)
        }
        return disabled
    }

    var body: some View {
        Form {
            Section(header: SectionHeader(title: "剪贴板", subtitle: "监视拷贝的数据并自动优化")) {
                Toggle(isOn: $enableClipboardOptimiser) {
                    Text("启用剪贴板优化器").regular(13)
                        + Text("\n监视拷贝的数据并自动优化").round(11, weight: .regular).foregroundColor(.secondary)
                }
                .searchAnchor("clipboard.clipboard.enableClipboardOptimiser", namesControl: true)
                Group {
                    Toggle(isOn: .constant(true)) {
                        Text("图像数据").regular(13)
                            + Text("\n拷贝的图像数据(如截屏)").round(11, weight: .regular).foregroundColor(.secondary)
                    }.disabled(true)
                        .accessibilityLabel("图像数据")
                    Toggle(isOn: $optimiseTIFF) {
                        Text("TIFF 数据").regular(13)
                            + Text("\n通常来自设计类应用,有时保持原样更好").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("clipboard.clipboard.optimiseTIFF", namesControl: true)
                    Toggle(isOn: $optimiseHEICAVIFClipboard) {
                        Text("HEIC 与 AVIF 数据").regular(13)
                    }
                    .searchAnchor("clipboard.clipboard.optimiseHEICAVIFClipboard", namesControl: true)
                    Toggle(isOn: $optimiseImagePathClipboard) {
                        Text("图像文件").regular(13)
                            + Text("\n从访达拷贝图像时,得到的是文件路径而非图像数据").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("clipboard.clipboard.optimiseImagePathClipboard", namesControl: true)
                    Toggle(isOn: $optimiseVideoClipboard) {
                        Text("视频文件").regular(13)
                            + Text("\n优化拷贝的视频文件路径").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("clipboard.clipboard.optimiseVideoClipboard", namesControl: true)
                    Toggle(isOn: $optimiseAudioClipboard) {
                        Text("音频文件").regular(13)
                            + Text("\n优化拷贝的音频文件路径").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("clipboard.clipboard.optimiseAudioClipboard", namesControl: true)
                    Toggle(isOn: $optimisePDFClipboard) {
                        Text("PDF 文件").regular(13)
                            + Text("\n优化拷贝的 PDF 文件路径").round(11, weight: .regular).foregroundColor(.secondary)
                    }
                    .searchAnchor("clipboard.clipboard.optimisePDFClipboard", namesControl: true)
                }
                .disabled(!enableClipboardOptimiser)
                .padding(.leading, 20)

                Toggle(isOn: $appendClipboardResults) {
                    Text("保留全部剪贴板结果").regular(13)
                        + Text("\n每次剪贴板优化都单独显示一个结果,而非替换上一个").round(11, weight: .regular).foregroundColor(.secondary)
                }.disabled(!enableClipboardOptimiser)
                    .searchAnchor("clipboard.clipboard.appendClipboardResults", namesControl: true)
                if appendClipboardResults {
                    Toggle(isOn: $copyConsecutiveClipboardImages) {
                        Text("在剪贴板中累积优化后的图像").regular(13)
                            + Text("\n每张新优化的图像都会加入剪贴板中的文件列表,可在 Pixelmator、Affinity 等图像编辑器或笔记里一次性全部粘贴").round(11, weight: .regular)
                            .foregroundColor(.secondary)
                    }
                    .disabled(!enableClipboardOptimiser)
                    .padding(.leading, 20)
                    .searchAnchor("clipboard.clipboard.copyConsecutiveClipboardImages", namesControl: true)

                    HStack {
                        Text("重置时间").regular(13)
                        Picker("重置时间", selection: $clipboardAccumulationTimeout) {
                            Text("10 秒").tag(10)
                            Text("30 秒").tag(30)
                            Text("1 分钟").tag(60)
                            Text("2 分钟").tag(120)
                            Text("5 分钟").tag(300)
                            Text("从不").tag(0)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .searchAnchor("clipboard.clipboard.clipboardAccumulationTimeout")
                        Text("无操作后").regular(13)
                    }
                    .padding(.leading, 20)
                }
            }

            Section(header: SectionHeader(title: "忽略的应用", subtitle: "这些应用在前台时跳过剪贴板优化")) {
                VStack(alignment: .leading, spacing: 4) {
                    IgnoredAppsPicker(bundleIds: $clipboardIgnoredAppBundleIds, enabled: enableClipboardOptimiser)
                        .padding(.top, 2)
                        .searchAnchor("clipboard.ignoredapps.clipboardIgnoredAppBundleIds")
                }
                .disabled(!enableClipboardOptimiser)
                .opacity(enableClipboardOptimiser ? 1 : 0.6)
            }
            .searchAnchor("clipboard.ignoredapps.clipboardIgnoredAppBundleIds")

            Section(header: SectionHeader(title: "自动化", subtitle: "对拷贝的每个文件自动执行操作")) {
                SourceAutomationsSection(source: .clipboard, disabledTypes: disabledClipboardTypes)
            }
            .id("automation")
        }
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 50)
        .padding(.vertical, 20)
        .scrollsToAutomation()
    }
}

struct GeneralSettingsView: View {
    enum MenubarIconStyle { case new, geometric, classic, hidden }

    static let menubarIconNew = templatedMenubarIcon("MenubarIcon")
    static let menubarIconGeometric = templatedMenubarIcon("MenubarIconGeometric")
    static let menubarIconClassic = templatedMenubarIcon("MenubarIconClassic")

    @Default(.showMenubarIcon) var showMenubarIcon
    @Default(.useClassicMenubarIcon) var useClassicMenubarIcon
    @Default(.useGeometricMenubarIcon) var useGeometricMenubarIcon
    @Default(.defaultLinkExpiration) var defaultLinkExpiration
    @Default(.stripMetadata) var stripMetadata
    @Default(.preserveColorMetadata) var preserveColorMetadata
    @Default(.preserveDates) var preserveDates
    @Default(.syncSettingsCloud) var syncSettingsCloud
    @Default(.optimisedFileProtectionMs) var optimisedFileProtectionMs

    @Default(.workdir) var workdir
    @Default(.workdirCleanupInterval) var workdirCleanupInterval

    var workdirBinding: Binding<String> {
        Binding(
            get: { workdir.shellString },
            set: { value in
                guard !value.isEmpty, let path = value.resolvedPath.existingFilePath else {
                    return
                }
                workdir = path.portablePath
            }
        )
    }

    /// Maps the four-way picker onto the stored bools: the icon choice only touches the
    /// style bools so the new/geometric/classic preference is remembered while hidden.
    /// `useGeometricMenubarIcon` takes precedence over `useClassicMenubarIcon`.
    var menubarIconStyle: Binding<MenubarIconStyle> {
        Binding(
            get: {
                guard showMenubarIcon else { return .hidden }
                if useGeometricMenubarIcon {
                    return .geometric
                }
                return useClassicMenubarIcon ? .classic : .new
            },
            set: { style in
                showMenubarIcon = style != .hidden
                if style != .hidden {
                    useClassicMenubarIcon = style == .classic
                    useGeometricMenubarIcon = style == .geometric
                }
            }
        )
    }

    var body: some View {
        Form {
            HStack {
                Text("菜单栏图标")
                    .searchAnchor("general.main.showMenubarIcon")
                Spacer()
                menubarIconButton(.new) { SwiftUI.Image(nsImage: Self.menubarIconNew).resizable() }
                menubarIconButton(.geometric) { SwiftUI.Image(nsImage: Self.menubarIconGeometric).resizable() }
                menubarIconButton(.classic) { SwiftUI.Image(nsImage: Self.menubarIconClassic).resizable() }
                menubarIconButton(.hidden) { SwiftUI.Image(systemName: "eye.slash").resizable() }
            }
            LaunchAtLogin.Toggle()
                .accessibilityLabel("登录时启动")
            Toggle("通过 iCloud 在多台 Mac 间同步设置", isOn: $syncSettingsCloud)
                .searchAnchor("general.main.syncSettingsCloud", namesControl: true)
            HStack {
                Text("安全发送链接有效期")
                Spacer()
                Picker("安全发送链接有效期", selection: $defaultLinkExpiration) {
                    ForEach(LINK_EXPIRATION_PRESETS, id: \.self) { preset in
                        Text(expirationDurationLabel(preset)).tag(preset)
                    }
                    Divider()
                    Text("从不").tag(LINK_EXPIRATION_NEVER)
                }
                .labelsHidden()
                .frame(width: 150)
                .searchAnchor("general.main.defaultLinkExpiration")
            }

            Section(header: SectionHeader(title: "用外部应用编辑", subtitle: "按 ⌘E 或通过右键菜单把优化后的文件交给自选编辑器")) {
                EditorAppRow(label: "Images", systemImage: "photo", key: .editorAppImage)
                    .searchAnchor("general.editwithexternalapp.editorAppImage")
                EditorAppRow(label: "Videos", systemImage: "video", key: .editorAppVideo)
                    .searchAnchor("general.editwithexternalapp.editorAppVideo")
                EditorAppRow(label: "Audio", systemImage: "waveform", key: .editorAppAudio)
                    .searchAnchor("general.editwithexternalapp.editorAppAudio")
                EditorAppRow(label: "PDFs", systemImage: "doc", key: .editorAppPDF)
                    .searchAnchor("general.editwithexternalapp.editorAppPDF")
            }

            Section(header: SectionHeader(title: "工作目录", subtitle: "临时文件、备份与优化后文件的存放位置")) {
                HStack {
                    Text("路径").regular(13).padding(.trailing, 10)
                        .searchAnchor("general.workingdirectory.workdir")
                    TextField("", text: workdirBinding)
                        .accessibilityLabel("工作目录")
                        .multilineTextAlignment(.center)
                        .font(.mono(12))
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.gray, lineWidth: 1).scaleEffect(y: TEXT_FIELD_SCALE).offset(x: TEXT_FIELD_OFFSET))
                    Button("重置") {
                        workdir = Defaults.Keys.workdir.defaultValue
                    }
                    .buttonStyle(.bordered)
                    .font(.regular(11))
                }

                Picker("定期清理早于此时间的文件", selection: $workdirCleanupInterval) {
                    Text("10 分钟").tag(CleanupInterval.every10Minutes)
                    Text("1 小时").tag(CleanupInterval.hourly)
                    Text("12 小时").tag(CleanupInterval.every12Hours)
                    Text("1 天").tag(CleanupInterval.daily)
                    Text("3 天").tag(CleanupInterval.every3Days)
                    Text("1 周").tag(CleanupInterval.weekly)
                    Text("1 个月").tag(CleanupInterval.monthly)
                    Text("从不清理").tag(CleanupInterval.never)
                }
                .searchAnchor("general.workingdirectory.workdirCleanupInterval", namesControl: true)
            }

            Section(header: SectionHeader(title: "优化")) {
                Toggle(isOn: $stripMetadata) {
                    Text("去除 EXIF 元数据").regular(13)
                        + Text("\n删除文件中可识别的元数据(如拍摄设备、位置、日期时间等)").round(11, weight: .regular).foregroundColor(.secondary)
                }
                .searchAnchor("general.optimisation.stripMetadata", namesControl: true)
                Toggle(isOn: $preserveColorMetadata) {
                    Text("保留色彩配置元数据").regular(13)
                        + Text("\n去除 EXIF 元数据时不改动色彩配置标签").round(11, weight: .regular).foregroundColor(.secondary)
                }
                .padding(.leading, 20)
                .disabled(!stripMetadata)
                .searchAnchor("general.optimisation.preserveColorMetadata", namesControl: true)

                Toggle(isOn: $preserveDates) {
                    Text("保留文件的创建与修改时间").regular(13)
                        + Text("\n优化后的文件将保留与原件相同的创建和修改时间").round(11, weight: .regular).foregroundColor(.secondary)
                }
                .searchAnchor("general.optimisation.preserveDates", namesControl: true)

                Picker(selection: $optimisedFileProtectionMs) {
                    Text("3 秒").tag(3000)
                    Text("10 秒").tag(10000)
                    Text("30 秒").tag(30000)
                    Text("60 秒").tag(60000)
                } label: {
                    Text("重复优化检测窗口").regular(13)
                        + Text("\n如果 iCloud Drive 上的文件被重复优化,调大此项").round(11, weight: .regular).foregroundColor(.secondary)
                }
                .searchAnchor("general.optimisation.optimisedFileProtectionMs", namesControl: true)
            }

            Section(header: SectionHeader(title: "隐私")) {
                SentryToggleRow(
                    title: "发送错误报告",
                    subtitle: "向开发者发送匿名崩溃与错误报告,帮助改进 Clop"
                )
            }
        }
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 50)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    func menubarIconButton(_ style: MenubarIconStyle, @ViewBuilder icon: () -> some View) -> some View {
        let selected = menubarIconStyle.wrappedValue == style
        Button {
            menubarIconStyle.wrappedValue = style
        } label: {
            icon()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .frame(width: 46, height: 28)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.clear : Color.primary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel({
            switch style {
            case .hidden: "Hidden"
            case .classic: "Classic"
            case .geometric: "Geometric"
            case .new: "New"
            }
        }())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help({
            switch style {
            case .hidden: "隐藏菜单栏图标"
            case .classic: "Use the classic menubar icon"
            case .geometric: "Use the geometric menubar icon"
            case .new: "Use the new menubar icon"
            }
        }())
    }

    /// Copy the menubar asset, mark it as a template and size it down so it tints and fits the picker buttons.
    static func templatedMenubarIcon(_ name: String) -> NSImage {
        guard let icon = NSImage(named: name)?.copy() as? NSImage else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        icon.isTemplate = true
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

}

struct HighlightedFolderRequest: Equatable {
    let fileType: ClopFileType
    let folder: String
}

class SettingsViewManager: ObservableObject {
    @Published var tab: SettingsView.Tabs = SWIFTUI_PREVIEW ? .floating : .general
    @Published var searchQuery = ""
    /// The entry id a search result asked to jump to. See `SettingsSearchAnchor`.
    @Published var highlightedEntry: String? = nil
    @Published var windowOpen = false
    @Published var scrollToFileType: ClopFileType?
    /// Set by the "在「兼容性」中配置" link in File Handling to scroll the destination
    /// tab down to its Compatibility section. Cleared once that section has reacted.
    @Published var scrollToCompatibility = false
    /// Set by an assignment pill's "Go to" (clipboard / drop zone) to scroll the destination tab down
    /// to its Automation section. Cleared once that section has reacted.
    @Published var scrollToAutomation = false
    @Published var highlightFolder: HighlightedFolderRequest?
    /// Set by a preset-zone menu in the inline preview to open (and scroll to) that zone's editor row in
    /// the same Preset Zones tab. Cleared once the row has reacted.
    @Published var editingPresetZoneID: String?
    /// Set by a floating result's "Pipeline: …" context-menu entry to open the Pipelines tab, scroll to
    /// the saved pipeline that ran on it and flash a highlight border. Cleared once the row has reacted.
    @Published var highlightPipelineID: String?
}

let settingsViewManager = SettingsViewManager()

struct HideSidebarToggleIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

struct SettingsSidebarRow: View {
    let tab: SettingsView.Tabs

    var body: some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.title)
            } icon: {
                SidebarIcon(symbol: tab.symbol, hue: tab.hue)
            }
        }
        .accessibilityIdentifier("settings.sidebar.\(tab)")
    }
}

struct SettingsView: View {
    enum Tabs: Int, Hashable, CaseIterable, Identifiable {
        case general, clipboard, files, video, audio, images, pdf, dropzone, presetZones, floating, keys, pipelines, automation, mcp, licenseUpdates, about

        var id: Int {
            rawValue
        }

        var next: Tabs {
            Tabs(rawValue: rawValue + 1) ?? .general
        }

        var previous: Tabs {
            Tabs(rawValue: rawValue - 1) ?? .about
        }

        var title: String {
            switch self {
            case .general: "General"
            case .clipboard: "Clipboard"
            case .files: "File handling"
            case .video: "Video"
            case .audio: "Audio"
            case .images: "Images"
            case .pdf: "PDF"
            case .dropzone: "Drop Zone"
            case .presetZones: "Preset Zones"
            case .floating: "Floating Results"
            case .keys: "键盘快捷键"
            case .pipelines: "Pipelines"
            case .automation: "Automation"
            case .mcp: "MCP"
            case .licenseUpdates: "License & updates"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .clipboard: "doc.on.clipboard"
            case .files: "folder.badge.gearshape"
            case .video: "video"
            case .audio: "waveform"
            case .images: "photo"
            case .pdf: "doc"
            case .dropzone: "square.stack.3d.up"
            case .presetZones: "square.grid.2x2"
            case .floating: "rectangle.stack"
            case .keys: "command.square"
            case .pipelines: "arrow.triangle.branch"
            case .automation: "hammer"
            case .mcp: "sparkles"
            case .licenseUpdates: "key"
            case .about: "info.circle"
            }
        }

        var hue: SidebarHue {
            switch self {
            case .general: .stone
            case .clipboard: .dustyBlue
            case .files: .skin
            case .video: .periwinkle
            case .audio: .plum
            case .images: .sage
            case .pdf: .terracotta
            case .dropzone: .mutedTeal
            case .presetZones: .ochre
            case .floating: .dustyRose
            case .keys: .clay
            case .pipelines: .periwinkle
            case .automation: .sage
            case .mcp: .mutedTeal
            case .licenseUpdates: .ochre
            case .about: .dustyRose
            }
        }
    }

    static let topTabs: [Tabs] = [.general, .clipboard, .files]
    static let fileTypeTabs: [Tabs] = [.video, .audio, .images, .pdf]
    static let dropTabs: [Tabs] = [.dropzone, .presetZones, .floating]
    static let automationTabs: [Tabs] = [.keys, .pipelines, .automation, .mcp]
    static let supportTabs: [Tabs] = [.licenseUpdates, .about]

    @ObservedObject var svm = settingsViewManager

    @FocusState var searchFocused: Bool

    var body: some View {
        if svm.windowOpen {
            settings
        }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            Group {
                if svm.searchQuery.isEmpty {
                    tabList
                } else {
                    searchResults
                }
            }
            .listStyle(.sidebar)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        .modifier(HideSidebarToggleIfAvailable())
    }

    /// Clop's own field instead of `.searchable`, so `⌘F` can put the cursor in it: focusing a
    /// `.searchable` field from code needs macOS 15 and Clop runs on 13. rcmd's Settings window has
    /// the same field for the same reason.
    var searchField: some View {
        HStack(spacing: 6) {
            // `SwiftUI.Image` qualified: Clop has its own `Image` type for optimisable files.
            SwiftUI.Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索设置", text: $svm.searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // The placeholder is not a name: without this the field is announced as nothing.
                .accessibilityLabel("搜索设置")
            if !svm.searchQuery.isEmpty {
                Button { svm.searchQuery = "" } label: {
                    SwiftUI.Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary))
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .onExitCommand { svm.searchQuery = "" }
    }

    /// What the search field finds, in place of the tab list.
    ///
    /// The row carries its pane and section so the answer is often readable without going anywhere,
    /// and selecting it opens that pane. The index behind this is the same one the MCP server reads,
    /// so a question typed here and a question asked of an agent land on the same row.
    @ViewBuilder var searchResults: some View {
        let results = SettingsSearchIndex.search(svm.searchQuery)
        if results.isEmpty {
            List {
                Text("没有与「\(svm.searchQuery)」匹配的内容")
                    .round(12)
                    .foregroundColor(.secondary)
            }
        } else {
            List {
                ForEach(results) { entry in
                    Button(action: { svm.jump(to: entry) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).medium(12)
                            if !entry.subtitle.isEmpty {
                                Text(entry.subtitle)
                                    .round(10)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Text([entry.tab.title, entry.section].filter { !$0.isEmpty }.joined(separator: " › "))
                                .round(9)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("复制深链") {
                            let link = SettingsURL.link(to: entry)
                            withGeneralPasteboard { pb in
                                pb.clearContents()
                                pb.setString(link, forType: .string)
                            }
                        }
                    }
                }
            }
        }
    }

    var tabList: some View {
        List(selection: $svm.tab) {
            ForEach(Self.topTabs, id: \.self) { tab in
                SettingsSidebarRow(tab: tab)
            }
            Section("文件类型") {
                ForEach(Self.fileTypeTabs, id: \.self) { tab in
                    SettingsSidebarRow(tab: tab)
                }
            }
            Section("投放与结果") {
                ForEach(Self.dropTabs, id: \.self) { tab in
                    SettingsSidebarRow(tab: tab)
                }
            }
            Section("快捷指令与自动化") {
                ForEach(Self.automationTabs, id: \.self) { tab in
                    SettingsSidebarRow(tab: tab)
                }
            }
            Section("支持") {
                ForEach(Self.supportTabs, id: \.self) { tab in
                    SettingsSidebarRow(tab: tab)
                }
            }
        }
    }

    var settings: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            SettingsPaneScroller { detailView }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Keep the window's title as "Settings" so it exists for the Window menu,
                // accessibility and Mission Control. `.windowStyle(.hiddenTitleBar)` keeps it
                // from being drawn in the titlebar. Using the tab name here (as before) leaked
                // the selected tab into the window title.
                .navigationTitle("设置")
                .background(PreventSidebarCollapse())
        }
        .navigationSplitViewStyle(.balanced)
        .formStyle(.grouped)
        .background {
            // ⌘F puts the cursor in the sidebar's search field from anywhere in Settings. A hidden
            // button is how a shortcut reaches a `@FocusState` without a menu command.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notif in
            guard !SWIFTUI_PREVIEW, let window = notif.object as? NSWindow else { return }
            if window.isSettingsWindow {
                log.debug("Starting settings tab key monitor")
                tabKeyMonitor.start()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notif in
            guard !SWIFTUI_PREVIEW, let window = notif.object as? NSWindow else { return }
            if window.isSettingsWindow {
                log.debug("Stopping settings tab key monitor")
                tabKeyMonitor.stop()
            }
        }
    }

    private struct PreventSidebarCollapse: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            DisablingView()
        }
        func updateNSView(_ nsView: NSView, context: Context) {}

        // `navigationSplitViewColumnWidth(min:)` only limits live resizing: dragging past
        // the minimum still snaps the sidebar closed, and without a sidebar toggle there is
        // no way to bring it back. SwiftUI has no API for this, so forbid collapsing on the
        // underlying `NSSplitViewController` and expand a sidebar that is already collapsed
        // (e.g. persisted from a previous session). Lives on the detail column: a collapsed
        // sidebar's view is out of the hierarchy, so a sidebar-attached helper would never run.
        private final class DisablingView: NSView {
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard window != nil else { return }
                DispatchQueue.main.async { [weak self] in self?.disableSidebarCollapse() }
            }

            override func layout() {
                super.layout()
                disableSidebarCollapse()
            }

            private func disableSidebarCollapse() {
                var view = superview
                while let v = view, !(v is NSSplitView) {
                    view = v.superview
                }
                guard let splitView = view as? NSSplitView,
                      let controller = splitView.delegate as? NSSplitViewController else { return }
                for item in controller.splitViewItems {
                    item.canCollapse = false
                    if item.isCollapsed {
                        item.isCollapsed = false
                    }
                }
            }
        }

    }

    @ViewBuilder
    private var detailView: some View {
        switch svm.tab {
        case .general: GeneralSettingsView()
        case .clipboard: ClipboardSettingsView()
        case .files: FileHandlingSettingsView()
        case .video: VideoSettingsView()
        case .audio: AudioSettingsView()
        case .images: ImagesSettingsView()
        case .pdf: PDFSettingsView()
        case .dropzone: DropZoneSettingsView()
        case .presetZones: PresetZonesSettingsView()
        case .floating: FloatingSettingsView()
        case .keys: KeysSettingsView()
        case .pipelines: PipelinesSettingsView()
        case .automation: AutomationSettingsView()
        case .mcp: MCPSettingsView()
        case .licenseUpdates: LicenseUpdatesSettingsView()
        case .about:
            AboutSettingsView()
                .overlay(alignment: .bottomTrailing) {
                    MadeBy().offset(x: -6, y: 0)
                }
        }
    }

}

@MainActor var tabKeyMonitor = LocalEventMonitor(mask: .keyDown) { event in
    guard let combo = event.keyCombo else { return event }

    if combo.modifierFlags == [.command, .shift] {
        switch combo.key {
        case .leftBracket:
            settingsViewManager.tab = settingsViewManager.tab.previous
        case .rightBracket:
            settingsViewManager.tab = settingsViewManager.tab.next
        default:
            return event
        }
        return nil
    }

    if combo.modifierFlags == [.command], let num = combo.key.character.i, let tab = SettingsView.Tabs(rawValue: num - 1) {
        settingsViewManager.tab = tab
        return nil
    }
    return event
}

// MARK: - Skip-rule sliders

/// Human-readable file size for slider labels (KB / MB / GB).
func formatSkipFileSize(_ bytes: Double) -> String {
    if bytes >= 1_000_000_000 {
        String(format: "%.1f GB", bytes / 1_000_000_000)
    } else if bytes >= 1_000_000 {
        String(format: "%.0f MB", bytes / 1_000_000)
    } else {
        String(format: "%.0f KB", bytes / 1000)
    }
}

struct SkipSliderKnob: View {
    var body: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }
}

/// Two-knob range slider operating on normalised fractions (0...1). The left knob is clamped
/// to never pass the right knob and vice versa. Callers map fractions to/from their domain.
struct DualKnobSlider: View {
    @Binding var low: Double
    @Binding var high: Double

    /// Name for the two stand-in accessibility sliders ("File size minimum", "File size maximum").
    var label = ""

    var onChanged: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let usable = max(1, w - thumb)
            let lowX = thumb / 2 + CGFloat(low) * usable
            let highX = thumb / 2 + CGFloat(high) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: track)
                Capsule().fill(Color.accentColor.opacity(0.7))
                    .frame(width: max(0, highX - lowX), height: track)
                    .position(x: (lowX + highX) / 2, y: thumb / 2)
                SkipSliderKnob().frame(width: thumb, height: thumb).position(x: lowX, y: thumb / 2)
                    .gesture(knobDrag(usable: usable, lower: true))
                    .accessibilitySlider("\(label) minimum", position: Binding(
                        get: { low },
                        set: { low = Swift.min(high, Swift.max(0, $0)); onChanged() }
                    ))
                SkipSliderKnob().frame(width: thumb, height: thumb).position(x: highX, y: thumb / 2)
                    .gesture(knobDrag(usable: usable, lower: false))
                    .accessibilitySlider("\(label) maximum", position: Binding(
                        get: { high },
                        set: { high = Swift.max(low, Swift.min(1, $0)); onChanged() }
                    ))
            }
            .frame(width: w, height: thumb)
            .coordinateSpace(name: space)
        }
        .frame(height: thumb)
    }

    private let thumb: CGFloat = 16
    private let track: CGFloat = 4
    private let space = "dualKnobSlider"

    private func knobDrag(usable: CGFloat, lower: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { v in
                let f = Double((v.location.x - thumb / 2) / usable)
                if lower {
                    low = Swift.min(high, Swift.max(0, f))
                } else {
                    high = Swift.max(low, Swift.min(1, f))
                }
            }
            .onEnded { _ in onChanged() }
    }
}

/// One-knob slider on normalised fractions (0...1); click or drag anywhere on the track.
struct SingleKnobSlider: View {
    @Binding var value: Double

    /// Name of the stand-in accessibility slider: the track is a drag gesture, invisible to it.
    var label = ""

    var onChanged: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let usable = max(1, w - thumb)
            let x = thumb / 2 + CGFloat(value) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: track)
                Capsule().fill(Color.accentColor.opacity(0.7))
                    .frame(width: max(0, x - thumb / 2), height: track)
                    .position(x: (thumb / 2 + x) / 2, y: thumb / 2)
                SkipSliderKnob().frame(width: thumb, height: thumb).position(x: x, y: thumb / 2)
            }
            .frame(width: w, height: thumb)
            .coordinateSpace(name: space)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                    .onChanged { v in
                        value = Swift.min(1, Swift.max(0, Double((v.location.x - thumb / 2) / usable)))
                    }
                    .onEnded { _ in onChanged() }
            )
        }
        .frame(height: thumb)
        .accessibilitySlider(label, position: Binding(
            get: { value },
            set: { value = Swift.min(1, Swift.max(0, $0)); onChanged() }
        ))
    }

    private let thumb: CGFloat = 16
    private let track: CGFloat = 4
    private let space = "singleKnobSlider"

}

/// File size skip range. min is stored in KB, max in MB; 0 disables that bound. Log-scaled.
struct FileSizeRangeRow: View {
    var label = "File size"

    @Binding var minKB: Int
    @Binding var maxMB: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).regular(13)
                Spacer()
                Text("\(minKB == 0 ? "0" : formatSkipFileSize(Double(minKB) * 1000)) - \(maxMB == 0 ? "∞" : formatSkipFileSize(Double(maxMB) * 1_000_000))")
                    .mono(11).foregroundColor(.secondary)
            }
            DualKnobSlider(
                low: Binding(get: { minKB == 0 ? 0 : frac(Double(minKB) * 1000) }, set: setLow),
                high: Binding(get: { maxMB == 0 ? 1 : frac(Double(maxMB) * 1_000_000) }, set: setHigh),
                label: label
            )
            Text(caption).round(10, weight: .regular).foregroundColor(.secondary)
        }
    }

    private let lo = 1000.0 // 1 KB
    private let hi = 10_000_000_000.0 // 10 GB

    private var caption: String {
        let minS = formatSkipFileSize(Double(minKB) * 1000)
        let maxS = formatSkipFileSize(Double(maxMB) * 1_000_000)
        return switch (minKB > 0, maxMB > 0) {
        case (true, true): "Only optimises files between \(minS) and \(maxS)"
        case (true, false): "Only optimises files larger than \(minS)"
        case (false, true): "Only optimises files smaller than \(maxS)"
        case (false, false): "Optimises files of any size"
        }
    }

    private func frac(_ bytes: Double) -> Double {
        let b = Swift.max(lo, Swift.min(hi, bytes))
        return (log2(b) - log2(lo)) / (log2(hi) - log2(lo))
    }

    private func bytes(_ f: Double) -> Double {
        lo * pow(hi / lo, f)
    }
    private func setLow(_ f: Double) {
        minKB = f <= 0 ? 0 : Int((bytes(f) / 1000).rounded())
    }
    private func setHigh(_ f: Double) {
        maxMB = f >= 1 ? 0 : Swift.max(1, Int((bytes(f) / 1_000_000).rounded()))
    }
}

/// Resolution skip range (px on either side). 0 disables that bound. Linear scale to 8000px.
struct ResolutionRangeRow: View {
    var label = "Resolution"

    @Binding var minRes: Int
    @Binding var maxRes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).regular(13)
                Spacer()
                Text("\(minRes == 0 ? "0" : "\(minRes)") - \(maxRes == 0 ? "∞" : "\(maxRes)") px")
                    .mono(11).foregroundColor(.secondary)
            }
            DualKnobSlider(
                low: Binding(get: { minRes == 0 ? 0 : frac(Double(minRes)) }, set: setLow),
                high: Binding(get: { maxRes == 0 ? 1 : frac(Double(maxRes)) }, set: setHigh),
                label: label
            )
            Text(caption).round(10, weight: .regular).foregroundColor(.secondary)
        }
    }

    private let lo = 16.0
    private let hi = 30000.0

    private var caption: String {
        switch (minRes > 0, maxRes > 0) {
        case (true, true): "Only optimises files with width and height between \(minRes) and \(maxRes)px"
        case (true, false): "Only optimises files with width and height over \(minRes)px"
        case (false, true): "Only optimises files with width and height under \(maxRes)px"
        case (false, false): "Optimises files of any resolution"
        }
    }

    private func frac(_ px: Double) -> Double {
        let p = Swift.max(lo, Swift.min(hi, px))
        return (log2(p) - log2(lo)) / (log2(hi) - log2(lo))
    }

    private func pixels(_ f: Double) -> Double {
        lo * pow(hi / lo, f)
    }
    /// Round to nicer steps: 10px under 1000, 50px above, where the slider gets coarse.
    private func snap(_ f: Double) -> Int {
        let px = pixels(f)
        let step = px < 1000 ? 10.0 : 50.0
        return Int((px / step).rounded()) * Int(step)
    }

    private func setLow(_ f: Double) {
        minRes = f <= 0 ? 0 : snap(f)
    }
    private func setHigh(_ f: Double) {
        maxRes = f >= 1 ? 0 : Swift.max(10, snap(f))
    }
}

/// One-knob stepped slider for integer counts.
struct CountSliderRow: View {
    var label = "File count"
    @Binding var count: Int

    var range: ClosedRange<Int> = 1 ... 100
    var caption: (Int) -> String = { _ in "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).regular(13)
                Spacer()
                Text("\(count)").mono(11).foregroundColor(.secondary)
            }
            SingleKnobSlider(value: Binding(
                get: { Double(count - range.lowerBound) / Double(range.upperBound - range.lowerBound) },
                set: { count = range.lowerBound + Int(($0 * Double(range.upperBound - range.lowerBound)).rounded()) }
            ), label: label)
            if !caption(count).isEmpty {
                Text(caption(count)).round(10, weight: .regular).foregroundColor(.secondary)
            }
        }
    }
}

struct SkipSliderPreview: View {
    @State var minKB = 100
    @State var maxMB = 500
    @State var minRes = 100
    @State var maxRes = 4000
    @State var count = 4

    var body: some View {
        Form {
            Section(header: Text("跳过规则预览")) {
                FileSizeRangeRow(minKB: $minKB, maxMB: $maxMB)
                ResolutionRangeRow(minRes: $minRes, maxRes: $maxRes)
                CountSliderRow(count: $count, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "image is" : "images are") copied or moved at once" })
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 420)
    }
}

#Preview { SkipSliderPreview() }

struct FloatingSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        FloatingSettingsView()
            .formStyle(.grouped)
            .frame(width: WINDOW_MIN_SIZE.width, height: WINDOW_MIN_SIZE.height, alignment: .topLeading)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let _ = (settingsViewManager.windowOpen = true)
        SettingsView()
            .frame(minWidth: WINDOW_MIN_SIZE.width, maxWidth: .infinity, minHeight: WINDOW_MIN_SIZE.height, maxHeight: .infinity)
    }
}
