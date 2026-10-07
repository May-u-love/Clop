import Defaults
import Foundation
import Lowtech
import os
import SwiftUI
import System

private let log = Logger(subsystem: LOG_SUBSYSTEM, category: "Automation")

extension Defaults.Keys {
    static let shortcutToRunOnImage = Key<[String: Shortcut]>("shortcutToRunOnImage", default: [:])
    static let shortcutToRunOnVideo = Key<[String: Shortcut]>("shortcutToRunOnVideo", default: [:])
    static let shortcutToRunOnPdf = Key<[String: Shortcut]>("shortcutToRunOnPdf", default: [:])

    static let pipelinesToRunOnImage = Key<[String: [Pipeline]]>("pipelinesToRunOnImage", default: [:])
    static let pipelinesToRunOnVideo = Key<[String: [Pipeline]]>("pipelinesToRunOnVideo", default: [:])
    static let pipelinesToRunOnPdf = Key<[String: [Pipeline]]>("pipelinesToRunOnPdf", default: [:])
    static let pipelinesToRunOnAudio = Key<[String: [Pipeline]]>("pipelinesToRunOnAudio", default: [:])
    static let pipelinesMigrated = Key<Bool>("pipelinesMigrated", default: false)
    static let savedScriptPaths = Key<[String: String]>("savedScriptPaths", default: [:])
    static let savedPipelines = Key<[Pipeline]>("savedPipelines", default: [])
    static let builtinPipelinesSeededVersion = Key<Int>("builtinPipelinesSeededVersion", default: 0)
}

extension Optimiser {
    nonisolated func runShortcut(_ shortcut: Shortcut, outFile: FilePath, url: URL) -> Process? {
        guard let proc = runShortcutProcess(shortcut, url.path, outFile: outFile.string) else {
            return nil
        }

        mainActor { [weak self] in
            self?.running = true
            self?.progress = Progress()
            self?.operation = "❯ \(shortcut.name)"
            self?.processes = [proc]
        }
        return proc
    }
}

// MARK: - Pipeline Migration

func migrateShortcutsToPipelines() {
    guard !Defaults[.pipelinesMigrated] else { return }

    var imagePipelines = Defaults[.pipelinesToRunOnImage]
    for (source, shortcut) in Defaults[.shortcutToRunOnImage] {
        imagePipelines[source, default: []].append(Pipeline(steps: [.runShortcut(shortcut)]))
    }
    if !imagePipelines.isEmpty {
        Defaults[.pipelinesToRunOnImage] = imagePipelines
    }

    var videoPipelines = Defaults[.pipelinesToRunOnVideo]
    for (source, shortcut) in Defaults[.shortcutToRunOnVideo] {
        videoPipelines[source, default: []].append(Pipeline(steps: [.runShortcut(shortcut)]))
    }
    if !videoPipelines.isEmpty {
        Defaults[.pipelinesToRunOnVideo] = videoPipelines
    }

    var pdfPipelines = Defaults[.pipelinesToRunOnPdf]
    for (source, shortcut) in Defaults[.shortcutToRunOnPdf] {
        pdfPipelines[source, default: []].append(Pipeline(steps: [.runShortcut(shortcut)]))
    }
    if !pdfPipelines.isEmpty {
        Defaults[.pipelinesToRunOnPdf] = pdfPipelines
    }

    Defaults[.pipelinesMigrated] = true
    log.debug("Migrated shortcuts to pipelines: images=\(imagePipelines.count), videos=\(videoPipelines.count), pdfs=\(pdfPipelines.count)")
}

// MARK: - Step Catalog

struct ParamTemplate {
    let name: String
    let description: String
    let suggestions: [String]
    let freeText: Bool
    var needsQuotes = false
    var valueDescriptions: [String: String] = [:]
    var valueDescriptionsForType: [ClopFileType: [String: String]] = [:]
    var suggestionsForType: [ClopFileType: [String]] = [:]
    /// When set, the param is only suggested for these file types. nil means it
    /// applies to every file type (and to "any-type" library pipelines).
    var applicableTypes: Set<ClopFileType>?

    func suggestions(for fileType: ClopFileType?) -> [String] {
        guard let fileType else { return suggestions }
        return suggestionsForType[fileType] ?? suggestions
    }

    func valueDescriptions(for fileType: ClopFileType?) -> [String: String] {
        guard let fileType else { return valueDescriptions }
        return valueDescriptionsForType[fileType] ?? valueDescriptions
    }

    func applies(to fileType: ClopFileType?) -> Bool {
        guard let applicableTypes else { return true }
        guard let fileType else { return true }
        return applicableTypes.contains(fileType)
    }
}

struct StepTemplate {
    let name: String
    let description: String
    let mandatoryParams: [ParamTemplate]
    let optionalParams: [ParamTemplate]
    let applicableTypes: Set<ClopFileType>
    let create: () -> PipelineStep
}

struct InstalledAppsInfo {
    let names: [String]
    let descriptions: [String: String]
}

private var _installedAppsCache: InstalledAppsInfo?

private func installedApps() -> InstalledAppsInfo {
    if let cache = _installedAppsCache {
        return cache
    }

    var descriptions = [String: String]()
    let fm = FileManager.default
    let searchPaths = ["/Applications", "\(NSHomeDirectory())/Applications"]

    for base in searchPaths {
        guard let enumerator = fm.enumerator(atPath: base) else { continue }
        while let path = enumerator.nextObject() as? String {
            guard path.hasSuffix(".app") else { continue }
            enumerator.skipDescendants()
            let fullPath = "\(base)/\(path)"
            guard isAppPathRelevant(fullPath) else { continue }
            guard let bundle = Bundle(path: fullPath) else { continue }
            let name = bundle.name
            let bundleID = bundle.bundleIdentifier ?? "unknown"
            descriptions[name] = "\(name) (\(bundleID))"
        }
    }

    let result = InstalledAppsInfo(names: descriptions.keys.sorted(), descriptions: descriptions)
    _installedAppsCache = result
    return result
}

let ALL_STEP_TEMPLATES: [StepTemplate] = [
    StepTemplate(
        name: "optimise", description: "优化文件体积",
        mandatoryParams: [],
        optionalParams: [
            ParamTemplate(
                name: "encoder",
                description: "compression quality preset",
                suggestions: ["aggressive", "medium", "lossless"],
                freeText: false,
                valueDescriptions: ["aggressive": "最小文件体积", "medium": "画质/体积均衡", "lossless": "无损"],
                valueDescriptionsForType: [
                    .video: ["fast": "硬件编码,快且省电", "slowHighQuality": "slow software encoder, smaller files", "visuallyLossless": "无可感知画质损失(CRF 17)"],
                    .pdf: [
                        "aggressive": "lossy + downsample images to 100 DPI",
                        "medium": "自适应降采样:按 PDF 内嵌图像分辨率选择 DPI",
                        "lossless": "不降采样,保留内嵌图像分辨率",
                    ],
                ],
                suggestionsForType: [
                    .video: ["fast", "slowHighQuality", "visuallyLossless"],
                ]
            ),
            ParamTemplate(
                name: "compression",
                description: "how hard to compress, 5 (best quality) to 100 (smallest file)",
                suggestions: ["30", "50", "64", "75", "90", "adaptive"],
                freeText: true,
                valueDescriptions: [
                    "30": "Clop's normal setting",
                    "64": "aggressive",
                    "adaptive": "let Clop pick per file",
                ]
            ),
            ParamTemplate(
                name: "adaptive",
                description: "自动选最佳格式",
                suggestions: ["true", "false"],
                freeText: false,
                valueDescriptions: ["true": "可能更改扩展名", "false": "保留原格式"],
                applicableTypes: [.image]
            ),
            ParamTemplate(
                name: "dpi",
                description: "PDF only: image resolution, overrides encoder choice (300 = no downsampling)",
                suggestions: ["300", "250", "200", "150", "100", "72", "48"],
                freeText: true,
                valueDescriptions: [
                    "300": "不降采样,保留内嵌图像分辨率",
                    "250": "轻度降采样,接近打印质量",
                    "200": "轻度降采样,适合屏幕阅读",
                    "150": "为屏幕阅读降采样",
                    "100": "更小,可读但明显劣化",
                    "72": "screen quality",
                    "48": "最小,画质很低",
                ],
                applicableTypes: [.pdf]
            ),
            ParamTemplate(
                name: "location",
                description: "结果保存位置",
                suggestions: ["inPlace", "sameFolder", "temporaryFolder", "template"],
                freeText: true,
                valueDescriptions: [
                    "inPlace": "替换原始文件",
                    "sameFolder": "存到原件旁",
                    "temporaryFolder": "存到临时文件夹",
                    "template": "custom path with %f (filename), %y (year), etc. Output extension is added automatically",
                ]
            ),
        ],
        applicableTypes: [.image, .video, .pdf, .audio],
        create: { .optimise() }
    ),
    StepTemplate(
        name: "downscale", description: "按系数缩小,始终保持宽高比(音频降低码率)",
        mandatoryParams: [
            ParamTemplate(name: "factor", description: "0.0 to 1.0 (e.g. 0.5 = half size, 0.75 = 75%)", suggestions: ["0.5", "0.75", "0.25"], freeText: true),
        ],
        optionalParams: [
            ParamTemplate(
                name: "location",
                description: "结果保存位置",
                suggestions: ["inPlace", "sameFolder", "temporaryFolder", "template"],
                freeText: true,
                valueDescriptions: [
                    "inPlace": "替换原始文件",
                    "sameFolder": "存到原件旁",
                    "temporaryFolder": "存到临时文件夹",
                    "template": "custom path with %f (filename), %y (year), etc. Output extension is added automatically",
                ]
            ),
        ],
        applicableTypes: [.image, .video, .audio],
        create: { .downscale(factor: 0.5) }
    ),
    StepTemplate(
        name: "lowerBitrate", description: "Lower the audio bitrate (never upscales, snaps to allowed bitrates)",
        mandatoryParams: [
            ParamTemplate(name: "kbps", description: "目标码率(kbps)", suggestions: ["192", "160", "128", "96", "64"], freeText: true),
        ],
        optionalParams: [
            ParamTemplate(
                name: "location",
                description: "结果保存位置",
                suggestions: ["inPlace", "sameFolder", "temporaryFolder", "template"],
                freeText: true,
                valueDescriptions: [
                    "inPlace": "替换原始文件",
                    "sameFolder": "存到原件旁",
                    "temporaryFolder": "存到临时文件夹",
                    "template": "custom path with %f (filename), %y (year), etc. Output extension is added automatically",
                ]
            ),
        ],
        applicableTypes: [.audio],
        create: { .lowerBitrate(kbps: 128) }
    ),
    StepTemplate(
        name: "convert", description: "转换为其他格式",
        mandatoryParams: [
            ParamTemplate(
                name: "to", description: "目标格式扩展名",
                suggestions: ["webp", "avif", "heic", "jxl", "jpeg", "png", "gif", "mp4", "webm", "m4a", "mp3", "ogg", "flac"],
                freeText: true,
                valueDescriptions: [
                    "webp": "WebP 图像格式",
                    "avif": "AV1 图像格式",
                    "heic": "HEIC 图像格式",
                    "jxl": "JPEG XL 图像格式",
                    "jpeg": "JPEG 图像格式",
                    "png": "PNG 图像格式",
                    "gif": "animated GIF",
                    "webm": "WebM 视频(VP9)",
                    "hevc": "HEVC/H.265 硬件编码的 MP4(快,省电)",
                    "x265": "x265 软件编码的 MP4(压缩更好,较慢)",
                    "av1": "AV1 视频(libsvtav1)",
                    "mp4": "MP4 视频(H.264)",
                    "m4a": "AAC audio",
                    "mp3": "MP3 audio",
                    "ogg": "Ogg Vorbis 音频",
                    "flac": "FLAC 无损音频",
                    "wav": "WAV 未压缩音频",
                    "aiff": "AIFF 未压缩音频",
                ],
                suggestionsForType: [
                    .image: ["webp", "avif", "heic", "jxl", "jpeg", "png", "gif"],
                    .video: ["gif", "webm", "hevc", "x265", "av1"],
                    .audio: ["m4a", "mp3", "ogg", "flac", "wav", "aiff"],
                ]
            ),
        ],
        optionalParams: [
            ParamTemplate(
                name: "location",
                description: "结果保存位置",
                suggestions: ["sameFolder", "inPlace", "temporaryFolder", "template"],
                freeText: true,
                valueDescriptions: [
                    "sameFolder": "存到原件旁",
                    "inPlace": "替换原始文件",
                    "temporaryFolder": "存到临时文件夹",
                    "template": "custom path with %f (filename), %y (year), etc. Output extension is added automatically",
                ]
            ),
        ],
        applicableTypes: [.image, .video, .audio],
        create: { .convert(to: "webp") }
    ),
    StepTemplate(
        name: "crop", description: "缩放到精确像素尺寸",
        mandatoryParams: [
            ParamTemplate(name: "width", description: "最大宽度(像素);不设则自动算高", suggestions: ["1920", "1600", "1280", "1024", "96"], freeText: true),
        ],
        optionalParams: [
            ParamTemplate(name: "height", description: "最大高度(像素);不设则自动算宽", suggestions: ["1080", "900", "720", "1024", "96"], freeText: true),
            ParamTemplate(name: "longEdge", description: "最长边的目标尺寸(代替宽/高)", suggestions: ["1920", "1600", "1280", "1024", "512"], freeText: true),
            ParamTemplate(
                name: "aspectRatio",
                description: "按形状裁剪而非像素尺寸(代替宽/高)",
                suggestions: ["16:9", "4:3", "3:2", "1:1", "9:16"],
                freeText: true,
                valueDescriptions: [
                    "16:9": "widescreen",
                    "4:3": "classic",
                    "3:2": "35mm photo",
                    "1:1": "square",
                    "9:16": "vertical video",
                ]
            ),
            ParamTemplate(
                name: "smartCrop",
                description: "保留画面最有趣的部分而非中心",
                suggestions: ["true", "false"],
                freeText: false
            ),
            ParamTemplate(
                name: "location",
                description: "结果保存位置",
                suggestions: ["inPlace", "sameFolder", "temporaryFolder", "template"],
                freeText: true,
                valueDescriptions: [
                    "inPlace": "替换原始文件",
                    "sameFolder": "存到原件旁",
                    "temporaryFolder": "存到临时文件夹",
                    "template": "custom path with %f (filename), %y (year), etc. Output extension is added automatically",
                ]
            ),
        ],
        applicableTypes: [.image, .video],
        create: { .crop(width: 1920) }
    ),
    StepTemplate(
        name: "extractPagesAsImages", description: "将 PDF 页面导出为图像",
        mandatoryParams: [],
        optionalParams: [
            ParamTemplate(
                name: "format",
                description: "提取页面的图像格式",
                suggestions: ["jpeg", "png"],
                freeText: false,
                valueDescriptions: ["jpeg": "JPEG(更小,白底)", "png": "PNG(保留透明)"]
            ),
            ParamTemplate(
                name: "quality",
                description: "渲染分辨率",
                suggestions: ["low", "medium", "high"],
                freeText: false,
                valueDescriptions: ["low": "1x scale (72 DPI)", "medium": "2x scale (144 DPI)", "high": "3x scale (216 DPI)"]
            ),
            ParamTemplate(
                name: "location",
                description: "提取图像的保存位置",
                suggestions: ["sameFolder", "temporaryFolder", "template"],
                freeText: true,
                valueDescriptions: [
                    "sameFolder": "存到原件旁",
                    "temporaryFolder": "存到临时文件夹",
                    "template": "custom path with %f (filename), %y (year), etc.",
                ]
            ),
        ],
        applicableTypes: [.pdf],
        create: { .extractPagesAsImages() }
    ),
    StepTemplate(
        name: "targetSize", description: "压缩直到文件低于体积上限(Discord 10MB、邮件 25MB 等)",
        mandatoryParams: [
            ParamTemplate(
                name: "size",
                description: "体积上限,如 10MB、500KB",
                suggestions: ["240KB", "1MB", "5MB", "8MB", "10MB", "16MB", "25MB"],
                freeText: true,
                valueDescriptions: [
                    "240KB": "US visa photo limit",
                    "5MB": "Notion 免费版",
                    "8MB": "Google Play 截图",
                    "10MB": "Discord 免费、GitHub 附件",
                    "16MB": "WhatsApp media",
                    "25MB": "Gmail 附件",
                ]
            ),
        ],
        optionalParams: [
            ParamTemplate(
                name: "location",
                description: "结果保存位置",
                suggestions: ["inPlace", "sameFolder", "temporaryFolder", "template"],
                freeText: true,
                valueDescriptions: [
                    "inPlace": "替换原始文件",
                    "sameFolder": "存到原件旁",
                    "temporaryFolder": "存到临时文件夹",
                    "template": "custom path with %f (filename), %y (year), etc. Output extension is added automatically",
                ]
            ),
        ],
        applicableTypes: [.image, .video, .pdf, .audio],
        create: { .targetSize(bytes: 10_000_000) }
    ),
    StepTemplate(
        name: "stripExif", description: "移除 EXIF 与 GPS 元数据(分享前保护隐私)",
        mandatoryParams: [],
        optionalParams: [],
        applicableTypes: [.image, .video],
        create: { .stripExif }
    ),
    StepTemplate(
        name: "watermark", description: "叠加水印图片",
        mandatoryParams: [
            ParamTemplate(name: "image", description: "水印图片路径(最好用带透明的 PNG)", suggestions: [], freeText: true, needsQuotes: true),
        ],
        optionalParams: [
            ParamTemplate(
                name: "position",
                description: "角落或居中放置",
                suggestions: ["bottomRight", "bottomLeft", "topRight", "topLeft", "center"],
                freeText: false
            ),
            ParamTemplate(name: "opacity", description: "0.0 to 1.0", suggestions: ["1.0", "0.5", "0.3"], freeText: true),
            ParamTemplate(name: "scale", description: "水印宽度占文件宽度的比例", suggestions: ["0.15", "0.1", "0.25", "0.5"], freeText: true),
            ParamTemplate(
                name: "location",
                description: "结果保存位置",
                suggestions: ["inPlace", "sameFolder", "temporaryFolder", "template"],
                freeText: true,
                valueDescriptions: [
                    "inPlace": "替换原始文件",
                    "sameFolder": "存到原件旁",
                    "temporaryFolder": "存到临时文件夹",
                    "template": "custom path with %f (filename), %y (year), etc. Output extension is added automatically",
                ]
            ),
        ],
        applicableTypes: [.image, .video],
        create: { .watermark(image: "") }
    ),
    StepTemplate(
        name: "capFps", description: "限制视频帧率",
        mandatoryParams: [
            ParamTemplate(name: "fps", description: "最大帧率", suggestions: ["60", "30", "24", "15", "10"], freeText: true),
        ],
        optionalParams: [],
        applicableTypes: [.video],
        create: { .capFps(fps: 30) }
    ),
    StepTemplate(
        name: "normalize", description: "Normalize audio loudness",
        mandatoryParams: [],
        optionalParams: [
            ParamTemplate(
                name: "lufs",
                description: "目标综合响度",
                suggestions: ["-14", "-16", "-23"],
                freeText: true,
                valueDescriptions: [
                    "-14": "Spotify / YouTube",
                    "-16": "Apple Podcasts",
                    "-23": "EBU broadcast",
                ]
            ),
        ],
        applicableTypes: [.audio],
        create: { .normalize() }
    ),
    StepTemplate(
        name: "copy", description: "复制文件到指定路径",
        mandatoryParams: [
            ParamTemplate(name: "to", description: "destination path, supports sourceFolder, sourceFileName, $1, $2", suggestions: [], freeText: true, needsQuotes: true),
        ],
        optionalParams: [],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .copy(to: "") }
    ),
    StepTemplate(
        name: "move", description: "Move file to a path",
        mandatoryParams: [
            ParamTemplate(name: "to", description: "destination path, supports sourceFolder, sourceFileName, $1, $2", suggestions: [], freeText: true, needsQuotes: true),
        ],
        optionalParams: [],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .move(to: "") }
    ),
    StepTemplate(
        name: "rename", description: "重命名文件",
        mandatoryParams: [
            ParamTemplate(name: "to", description: "new name, supports sourceFileName, $1, $2", suggestions: [], freeText: true, needsQuotes: true),
        ],
        optionalParams: [],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .rename(to: "") }
    ),
    StepTemplate(
        name: "delete", description: "Delete a file",
        mandatoryParams: [
            ParamTemplate(name: "path", description: "path to delete, supports %P, %f, %e and other template tokens", suggestions: [], freeText: true, needsQuotes: true),
        ],
        optionalParams: [],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .delete(path: "") }
    ),
    StepTemplate(
        name: "if", description: "仅当条件匹配时继续管线",
        mandatoryParams: [],
        optionalParams: [
            ParamTemplate(name: "regex", description: "pattern matched against filename (smart case), capture groups as $1, $2", suggestions: [], freeText: true, needsQuotes: true),
            ParamTemplate(name: "types", description: "space-separated UTTypes: jpeg png webp heic", suggestions: [], freeText: true),
            ParamTemplate(name: "nameContains", description: "不区分大小写的子串匹配", suggestions: [], freeText: true, needsQuotes: true),
            ParamTemplate(name: "nameIs", description: "精确文件名匹配", suggestions: [], freeText: true, needsQuotes: true),
            ParamTemplate(name: "fileSizeGreaterThan", description: "最小文件大小(字节)", suggestions: [], freeText: true),
            ParamTemplate(name: "fileSizeLowerThan", description: "最大文件大小(字节)", suggestions: [], freeText: true),
            ParamTemplate(name: "widthGreaterThan", description: "最小宽度(像素)", suggestions: [], freeText: true, applicableTypes: [.image]),
            ParamTemplate(name: "widthLowerThan", description: "最大宽度(像素)", suggestions: [], freeText: true, applicableTypes: [.image]),
            ParamTemplate(name: "heightGreaterThan", description: "最小高度(像素)", suggestions: [], freeText: true, applicableTypes: [.image]),
            ParamTemplate(name: "heightLowerThan", description: "最大高度(像素)", suggestions: [], freeText: true, applicableTypes: [.image]),
            ParamTemplate(name: "dpiGreaterThan", description: "最小 DPI(图像和 PDF)", suggestions: ["72", "150", "300"], freeText: true, applicableTypes: [.image, .pdf]),
            ParamTemplate(name: "dpiLowerThan", description: "最大 DPI(图像和 PDF)", suggestions: ["72", "150", "300"], freeText: true, applicableTypes: [.image, .pdf]),
            ParamTemplate(name: "minFileSize", description: "最小文件大小,如 100kb 或 2mb", suggestions: ["100kb", "1mb"], freeText: true),
            ParamTemplate(name: "minResolution", description: "最小宽高(像素),如 100x100", suggestions: ["100x100", "640x480"], freeText: true, applicableTypes: [.image]),
            ParamTemplate(name: "copiedBy", description: "拷贝来源应用(仅剪贴板),模糊匹配应用名或 bundle id", suggestions: [], freeText: true, needsQuotes: true),
        ],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .filterIf(FilterCondition(regex: "")) }
    ),
    StepTemplate(
        name: "ifNot", description: "仅当条件不匹配时继续管线",
        mandatoryParams: [],
        optionalParams: [
            ParamTemplate(name: "regex", description: "按文件名匹配的模式(智能大小写)", suggestions: [], freeText: true, needsQuotes: true),
            ParamTemplate(name: "types", description: "空格分隔的 UTType 排除列表", suggestions: [], freeText: true),
            ParamTemplate(name: "nameContains", description: "不区分大小写的排除子串", suggestions: [], freeText: true, needsQuotes: true),
            ParamTemplate(name: "nameIs", description: "精确排除的文件名", suggestions: [], freeText: true, needsQuotes: true),
            ParamTemplate(name: "copiedBy", description: "此应用拷贝时排除(仅剪贴板),模糊匹配应用名或 bundle id", suggestions: [], freeText: true, needsQuotes: true),
        ],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .filterIfNot(FilterCondition(regex: "")) }
    ),
    StepTemplate(
        name: "removeAudio", description: "移除音轨",
        mandatoryParams: [],
        optionalParams: [],
        applicableTypes: [.video],
        create: { .removeAudio }
    ),
    StepTemplate(
        name: "changeSpeed", description: "更改播放速度",
        mandatoryParams: [
            ParamTemplate(name: "factor", description: "speed multiplier (e.g. 2.0 = 2x, 0.5 = half speed)", suggestions: ["1.5", "2.0", "0.5", "0.75"], freeText: true),
        ],
        optionalParams: [
            ParamTemplate(name: "frames", description: "keep (smoother, higher fps) or drop (smaller file). Unset follows Settings > Video", suggestions: ["keep", "drop"], freeText: false, applicableTypes: [.video]),
        ],
        applicableTypes: [.video, .audio],
        create: { .changeSpeed(factor: 1.5) }
    ),
    StepTemplate(
        name: "runScript",
        description: "Run a script file, executable, or inline shell code. Input file is passed as $1 and CLOP_INPUT_FILE; Clop's bundled tools (ffmpeg, gs, gifski…) are in $CLOP_BIN; print a file path to stdout to swap the file the pipeline carries forward",
        mandatoryParams: [],
        optionalParams: [
            ParamTemplate(name: "path", description: "脚本文件或可执行文件的路径", suggestions: [], freeText: true, needsQuotes: true),
            ParamTemplate(name: "code", description: "通过 zsh -c 运行的内联 shell 代码(代替路径)", suggestions: [], freeText: true, needsQuotes: true),
        ],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .runScript(path: "") }
    ),
    StepTemplate(
        name: "runShortcut", description: "运行快捷指令",
        mandatoryParams: [
            ParamTemplate(name: "name", description: "shortcut name as shown in Shortcuts.app", suggestions: [], freeText: true, needsQuotes: true),
        ],
        optionalParams: [],
        applicableTypes: [.image, .video, .pdf],
        create: { .runShortcut(Shortcut(name: "", identifier: "")) }
    ),
    StepTemplate(
        name: "copyToClipboard", description: "复制文件引用到剪贴板",
        mandatoryParams: [],
        optionalParams: [
            ParamTemplate(
                name: "format",
                description: "剪贴板内容格式",
                suggestions: ["path", "imageData", "markdown"],
                freeText: false,
                valueDescriptions: ["path": "文件路径(设置了 relativeTo 则为相对路径)", "imageData": "raw image data", "markdown": "Markdown 链接(设置了 relativeTo 则为相对路径)"],
                suggestionsForType: [
                    .video: ["path", "markdown"],
                    .audio: ["path", "markdown"],
                    .pdf: ["path", "markdown"],
                ]
            ),
            ParamTemplate(name: "relativeTo", description: "base path, makes output relative (e.g. ~/Projects/blog)", suggestions: [], freeText: true, needsQuotes: true),
        ],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .copyToClipboard() }
    ),
    StepTemplate(
        name: "copyLinkForSending", description: "安全发送文件并复制分享链接到剪贴板",
        mandatoryParams: [],
        optionalParams: [
            ParamTemplate(
                name: "expiration",
                description: "auto-stop the link after this long (1m–3d, or never). Defaults to the setting in Preferences",
                suggestions: ["1m", "15m", "1h", "6h", "1d", "3d", "never"],
                freeText: true
            ),
        ],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .copyLinkForSending() }
    ),
    StepTemplate(
        name: "fork", description: "同时把当前结果作为第二张可拖动卡片显示,然后继续处理",
        mandatoryParams: [],
        optionalParams: [
            ParamTemplate(
                name: "location",
                description: "where to save the forked card's file (defaults to a temp file you can drag out)",
                suggestions: ["sameFolder", "temporaryFolder"],
                freeText: true
            ),
        ],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .fork() }
    ),
    StepTemplate(
        name: "shelveWith", description: "发送文件到暂存区应用",
        mandatoryParams: [
            ParamTemplate(
                name: "app",
                description: "shelf app to send to",
                suggestions: SHELVE_WITH_APPS.map(\.key),
                freeText: false,
                valueDescriptions: Dictionary(uniqueKeysWithValues: SHELVE_WITH_APPS.map { ($0.key, $0.value) })
            ),
        ],
        optionalParams: [],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .shelveWith(app: "yoink") }
    ),
    StepTemplate(
        name: "uploadWith", description: "通过上传应用上传文件",
        mandatoryParams: [
            ParamTemplate(
                name: "app",
                description: "upload app to use",
                suggestions: ["dropshare"],
                freeText: false,
                valueDescriptions: [
                    "dropshare": "Dropshare file upload service",
                ]
            ),
        ],
        optionalParams: [],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .uploadWith(app: "dropshare") }
    ),
    StepTemplate(
        name: "openWith", description: "用指定应用打开文件",
        mandatoryParams: [
            {
                let apps = installedApps()
                return ParamTemplate(
                    name: "app",
                    description: "应用名(如 Preview、Pixelmator Pro)",
                    suggestions: apps.names,
                    freeText: true,
                    needsQuotes: false,
                    valueDescriptions: apps.descriptions
                )
            }(),
        ],
        optionalParams: [],
        applicableTypes: [.image, .video, .audio, .pdf],
        create: { .openWith(app: "") }
    ),
]

func stepTemplates(for fileType: ClopFileType?) -> [StepTemplate] {
    guard let fileType else { return ALL_STEP_TEMPLATES }
    return ALL_STEP_TEMPLATES.filter { $0.applicableTypes.contains(fileType) }
}

// MARK: - Pipeline Step Parsing

func parsePipelineStep(_ text: String) -> PipelineStep? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)

    // Handle no-param steps
    if trimmed == "removeAudio" {
        return .removeAudio
    }
    if trimmed == "copyLinkForSending" {
        return .copyLinkForSending()
    }
    if trimmed == "fork" {
        return .fork()
    }
    if trimmed == "copyToClipboard" {
        return .copyToClipboard()
    }
    if trimmed == "stripExif" {
        return .stripExif
    }
    if trimmed == "normalize" {
        return .normalize()
    }

    // Parse name(params) format
    guard let nameRegex = try? NSRegularExpression(pattern: #"^(\w+)(?:\((.*)\))?$"#),
          let match = nameRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
          let nameRange = Range(match.range(at: 1), in: trimmed)
    else { return nil }

    let name = String(trimmed[nameRange])
    let paramsStr = if match.range(at: 2).location != NSNotFound, let r = Range(match.range(at: 2), in: trimmed) {
        String(trimmed[r])
    } else {
        ""
    }

    // Parse comma-separated params, handling key: value and bare values
    let params = parseParams(paramsStr)

    switch name {
    case "optimise":
        let encoderStr = params["encoder"] ?? "medium"
        let adaptive = params["adaptive"] == "true"
        let dpi = params["dpi"].flatMap { Int($0) }
        let location = params["location"] ?? "inPlace"
        // Same grammar as the CLI's `--compression`, see `parseCompressionValue`.
        let compression = parseCompressionValue(params["compression"])
        if let videoEncoder = VideoEncoder(rawValue: encoderStr) {
            return .optimise(adaptive: adaptive, videoEncoder: videoEncoder, dpi: dpi, location: location, compression: compression)
        }
        return .optimise(encoder: EncoderQuality(rawValue: encoderStr) ?? .medium, adaptive: adaptive, dpi: dpi, location: location, compression: compression)

    case "downscale":
        guard let factor = params["factor"].flatMap({ Double($0) }), factor > 0, factor <= 1 else { return nil }
        let location = params["location"] ?? "inPlace"
        return .downscale(factor: factor, location: location)

    case "lowerBitrate":
        guard let kbps = params["kbps"].flatMap({ Int($0) }), kbps > 0 else { return nil }
        let location = params["location"] ?? "inPlace"
        return .lowerBitrate(kbps: kbps, location: location)

    case "convert":
        guard let to = params["to"], !to.isEmpty else { return nil }
        let location = params["location"] ?? "sameFolder"
        return .convert(to: to, location: location)

    case "crop":
        let width = params["width"].flatMap { Int($0) }
        let height = params["height"].flatMap { Int($0) }
        let longEdge = params["longEdge"].flatMap { Int($0) }
        // Only accept a ratio the parser understands, so a typo fails the step instead of silently
        // falling back to an unbounded crop.
        let aspectRatio = params["aspectRatio"].flatMap { CropSize(aspectRatio: $0) == nil ? nil : $0 }
        guard width != nil || height != nil || longEdge != nil || aspectRatio != nil else { return nil }
        let smartCrop = params["smartCrop"] == "true"
        let location = params["location"] ?? "inPlace"
        return .crop(width: width, height: height, longEdge: longEdge, aspectRatio: aspectRatio, smartCrop: smartCrop, location: location)

    case "copy":
        guard let to = params["to"], !to.isEmpty else { return nil }
        return .copy(to: to)

    case "move":
        guard let to = params["to"], !to.isEmpty else { return nil }
        return .move(to: to)

    case "rename":
        guard let to = params["to"], !to.isEmpty else { return nil }
        return .rename(to: to)

    case "delete":
        guard let path = params["path"], !path.isEmpty else { return nil }
        return .delete(path: path)

    case "extractPagesAsImages":
        let format = params["format"] ?? "jpeg"
        let quality = params["quality"] ?? "medium"
        let location = params["location"] ?? "sameFolder"
        return .extractPagesAsImages(format: format, quality: quality, location: location)

    case "targetSize":
        guard let sizeStr = params["size"], let bytes = parseByteSize(sizeStr), bytes > 0 else { return nil }
        return .targetSize(bytes: bytes, location: params["location"] ?? "inPlace")

    case "stripExif":
        return .stripExif

    case "watermark":
        guard let image = params["image"], !image.isEmpty else { return nil }
        return .watermark(
            image: image,
            position: params["position"] ?? "bottomRight",
            opacity: params["opacity"].flatMap { Double($0) } ?? 1.0,
            scale: params["scale"].flatMap { Double($0) } ?? 0.15,
            location: params["location"] ?? "inPlace"
        )

    case "capFps":
        guard let fps = params["fps"].flatMap({ Int($0) }), fps > 0 else { return nil }
        return .capFps(fps: fps)

    case "normalize":
        return .normalize(lufs: params["lufs"].flatMap { Double($0) } ?? -16)

    case "if":
        let condition = parseFilterCondition(params)
        guard !condition.isEmpty else { return nil }
        return .filterIf(condition)

    case "ifNot":
        let condition = parseFilterCondition(params)
        guard !condition.isEmpty else { return nil }
        return .filterIfNot(condition)

    case "changeSpeed":
        guard let factor = params["factor"].flatMap({ Double($0) }) else { return nil }
        // A word the parser doesn't know fails the step, instead of silently following the global
        // setting the pipeline was written to override.
        var frames: PlaybackSpeedFrameBehaviour?
        if let word = params["frames"] {
            guard let parsed = PlaybackSpeedFrameBehaviour(dslValue: word) else { return nil }
            frames = parsed
        }
        return .changeSpeed(factor: factor, frames: frames)

    case "runScript":
        if let code = params["code"], !code.isEmpty {
            return .runScript(code: code)
        }
        guard let scriptPath = params["path"], !scriptPath.isEmpty else { return nil }
        return .runScript(path: scriptPath)

    case "runShortcut":
        guard let shortcutName = params["name"], !shortcutName.isEmpty else { return nil }
        let shortcuts = SHM.shortcuts
        let shortcut = shortcuts.first(where: { $0.name == shortcutName }) ?? Shortcut(name: shortcutName, identifier: shortcutName)
        return .runShortcut(shortcut)

    case "copyToClipboard":
        let format = ClipboardCopyFormat(rawValue: params["format"] ?? "path") ?? .path
        let relativeTo = params["relativeTo"]
        return .copyToClipboard(format: format, relativeTo: relativeTo)

    case "copyLinkForSending":
        let expiration = params["expiration"].flatMap { parseExpirationDuration($0) }
        return .copyLinkForSending(expiration: expiration)

    case "fork":
        return .fork(location: params["location"])

    case "shelveWith":
        guard let app = params["app"], SHELVE_WITH_APPS.contains(where: { $0.key == app.lowercased() }) else { return nil }
        return .shelveWith(app: app.lowercased())

    case "uploadWith":
        guard let app = params["app"], ["dropshare"].contains(app.lowercased()) else { return nil }
        return .uploadWith(app: app.lowercased())

    case "openWith":
        guard let app = params["app"], !app.isEmpty else { return nil }
        return .openWith(app: app)

    default:
        return nil
    }
}

private func parseParams(_ str: String) -> [String: String] {
    guard !str.isEmpty else { return [:] }
    var result: [String: String] = [:]
    for part in splitOutsideQuotes(str, on: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
        let kv = part.split(separator: ":", maxSplits: 1)
        guard kv.count == 2 else { continue }
        let key = kv[0].trimmingCharacters(in: .whitespaces)
        let value = kv[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        result[key] = value
    }
    return result
}

/// Split on a separator, ignoring separators inside single or double quotes so that
/// values like `regex: "\d{2,4}"` survive parameter parsing.
private func splitOutsideQuotes(_ str: String, on separator: Character) -> [String] {
    var parts: [String] = []
    var current = ""
    var quoteChar: Character?
    for ch in str {
        if ch == "\"" || ch == "'" {
            if quoteChar == ch {
                quoteChar = nil
            } else if quoteChar == nil {
                quoteChar = ch
            }
            current.append(ch)
        } else if ch == separator, quoteChar == nil {
            parts.append(current)
            current = ""
        } else {
            current.append(ch)
        }
    }
    parts.append(current)
    return parts
}

private func parseFilterCondition(_ params: [String: String]) -> FilterCondition {
    FilterCondition(
        types: params["types"]?.split(separator: " ").map(String.init),
        regex: params["regex"],
        nameContains: params["nameContains"],
        nameIs: params["nameIs"],
        fileSizeGreaterThan: params["fileSizeGreaterThan"].flatMap { Int($0) },
        fileSizeLowerThan: params["fileSizeLowerThan"].flatMap { Int($0) },
        widthGreaterThan: params["widthGreaterThan"].flatMap { Int($0) },
        widthLowerThan: params["widthLowerThan"].flatMap { Int($0) },
        heightGreaterThan: params["heightGreaterThan"].flatMap { Int($0) },
        heightLowerThan: params["heightLowerThan"].flatMap { Int($0) },
        dpiGreaterThan: params["dpiGreaterThan"].flatMap { Int($0) },
        dpiLowerThan: params["dpiLowerThan"].flatMap { Int($0) },
        minFileSize: params["minFileSize"].flatMap { parseByteSize($0) },
        minResolution: params["minResolution"].flatMap { parseResolution($0) },
        copiedBy: params["copiedBy"]
    )
}

/// Parse a human-friendly byte size like "100kb", "2mb", "1.5MiB" or a raw byte count.
private func parseByteSize(_ str: String) -> Int? {
    let s = str.trimmingCharacters(in: .whitespaces).lowercased()
    if let n = Int(s) {
        return n
    }
    // Longer suffixes first so "kib"/"mib" win over "kb"/"mb".
    let multipliers: [(String, Double)] = [
        ("gib", 1_073_741_824), ("gb", 1_000_000_000),
        ("mib", 1_048_576), ("mb", 1_000_000),
        ("kib", 1024), ("kb", 1000), ("b", 1),
    ]
    for (suffix, mult) in multipliers where s.hasSuffix(suffix) {
        if let num = Double(s.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)) {
            return Int(num * mult)
        }
    }
    return nil
}

/// Parse a resolution like "100" or "100x100" into a single minimum-edge value (the first number).
private func parseResolution(_ str: String) -> Int? {
    let parts = str.lowercased().split(whereSeparator: { $0 == "x" || $0 == "×" })
    guard let first = parts.first, let n = Int(first.trimmingCharacters(in: .whitespaces)) else { return nil }
    return n
}

// MARK: - Pipeline Text Completions

struct CompletionSuggestion: Identifiable {
    let id = UUID()
    let insertText: String
    let displayText: String
    let details: String
    let color: Color
    let opensParens: Bool
    var needsQuotes = false
    var isTemplateVar = false
    var closesParens = false
}

struct TemplateVariable {
    let token: String
    let name: String
    let description: String
}

let TEMPLATE_VARIABLES: [TemplateVariable] = [
    TemplateVariable(token: "%f", name: "filename", description: "不含扩展名的源文件名"),
    TemplateVariable(token: "%e", name: "extension", description: "不含点的源文件扩展名(输出扩展名总是自动添加)"),
    TemplateVariable(token: "%P", name: "path", description: "源文件所在目录路径"),
    TemplateVariable(token: "%F", name: "fullPath", description: "完整源文件路径(含文件名)"),
    TemplateVariable(token: "%y", name: "year", description: "当前年份(如 2026)"),
    TemplateVariable(token: "%m", name: "month", description: "月(01-12)"),
    TemplateVariable(token: "%n", name: "monthName", description: "月份名(如 March)"),
    TemplateVariable(token: "%d", name: "day", description: "日(01-31)"),
    TemplateVariable(token: "%w", name: "weekday", description: "星期几(如 Friday)"),
    TemplateVariable(token: "%H", name: "hour", description: "hour (00-23)"),
    TemplateVariable(token: "%M", name: "minutes", description: "分(00-59)"),
    TemplateVariable(token: "%S", name: "seconds", description: "秒(00-59)"),
    TemplateVariable(token: "%p", name: "amPm", description: "AM or PM"),
    TemplateVariable(token: "%r", name: "random", description: "随机字符"),
    TemplateVariable(token: "%i", name: "counter", description: "自增编号"),
]

/// Determines context from the prefix and returns appropriate suggestions.
/// - Step name context: shows step names with descriptions
/// - Param list context: shows param names with descriptions
/// - Param value context: shows values for the specific param
func pipelineSuggestions(prefix: String, fileType: ClopFileType?) -> [CompletionSuggestion] {
    let templates = stepTemplates(for: fileType)
    let trimmed = prefix.trimmingCharacters(in: .whitespaces)

    // Inside parentheses -> show param suggestions
    if let openParen = trimmed.firstIndex(of: "(") {
        let stepName = String(trimmed[..<openParen])
        guard let template = templates.first(where: { $0.name == stepName }) else { return [] }

        let step = template.create()
        let afterParen = String(trimmed[trimmed.index(after: openParen)...])
        let parts = afterParen.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let lastPart = parts.last ?? ""

        // Already-used param names
        let usedNames = Set(parts.dropLast().compactMap { p in
            p.contains(":") ? String(p.split(separator: ":")[0]).trimmingCharacters(in: .whitespaces) : nil
        })
        // Also include the current part if it has a colon and a value
        let allParams = (template.mandatoryParams + template.optionalParams).filter { $0.applies(to: fileType) }

        if lastPart.contains(":") {
            // User typed "paramName:" or "paramName: val" -> show values for this param
            let colonIdx = lastPart.firstIndex(of: ":")!
            let paramName = String(lastPart[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let typedValue = String(lastPart[lastPart.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            guard let param = allParams.first(where: { $0.name == paramName }) else { return [] }

            // Inside quotes -> show template variables when empty or after % so the
            // user discovers available tokens without having to know about them first.
            let insideQuotes = typedValue.hasPrefix("\"")
            let unquotedValue = insideQuotes ? String(typedValue.dropFirst()) : typedValue
            if insideQuotes, unquotedValue.isEmpty || unquotedValue.contains("%") {
                let afterPercent = unquotedValue.lastIndex(of: "%").map { String(unquotedValue.suffix(from: $0).dropFirst()) } ?? ""
                return TEMPLATE_VARIABLES
                    .filter { afterPercent.isEmpty || $0.token.dropFirst().hasPrefix(afterPercent) || $0.name.lowercased().hasPrefix(afterPercent.lowercased()) }
                    .map { tv in
                        CompletionSuggestion(
                            insertText: tv.token,
                            displayText: tv.token,
                            details: tv.description,
                            color: step.category.swiftUIColor,
                            opensParens: false,
                            isTemplateVar: true
                        )
                    }
            }

            let paramSuggestions = param.suggestions(for: fileType)
            let filledNames = usedNames.union([paramName])
            let remainingParams = allParams.filter { !filledNames.contains($0.name) }
            let isLastParam = remainingParams.isEmpty
            let suggestions = paramSuggestions
                .filter { typedValue.isEmpty || $0.lowercased().hasPrefix(typedValue.lowercased()) }
                .map { value in
                    CompletionSuggestion(
                        insertText: value,
                        displayText: value,
                        details: param.valueDescriptions(for: fileType)[value] ?? param.description,
                        color: step.category.swiftUIColor,
                        opensParens: false,
                        needsQuotes: value == "template",
                        closesParens: isLastParam
                    )
                }

            if suggestions.isEmpty, paramSuggestions.isEmpty {
                return []
            }
            return suggestions
        } else {
            // Show available param names, filtered by what user is typing
            return allParams
                .filter { !usedNames.contains($0.name) }
                .filter { lastPart.isEmpty || $0.name.lowercased().hasPrefix(lastPart.lowercased()) || $0.name.lowercased().contains(lastPart.lowercased()) }
                .map { param in
                    CompletionSuggestion(
                        insertText: "\(param.name): ",
                        displayText: param.name,
                        details: param.description,
                        color: step.category.swiftUIColor,
                        opensParens: false,
                        needsQuotes: param.needsQuotes
                    )
                }
        }
    }

    // Typing step name (or empty)
    let lowered = trimmed.lowercased()
    return templates
        .filter { lowered.isEmpty || $0.name.lowercased().hasPrefix(lowered) || $0.name.lowercased().contains(lowered) }
        .map { template in
            let step = template.create()
            let hasParams = !template.mandatoryParams.isEmpty || !template.optionalParams.isEmpty
            // For steps with a single mandatory param, auto-include the param name
            let singleMandatory = template.mandatoryParams.count == 1 && template.optionalParams.isEmpty
            let quotes = singleMandatory && template.mandatoryParams[0].needsQuotes
            let insertText = if singleMandatory {
                "\(template.name)(\(template.mandatoryParams[0].name): " + (quotes ? "\"" : "")
            } else {
                template.name
            }
            return CompletionSuggestion(
                insertText: insertText,
                displayText: template.name,
                details: template.description,
                color: step.category.swiftUIColor,
                opensParens: hasParams && !singleMandatory,
                needsQuotes: quotes
            )
        }
}

extension StepCategory {
    /// SwiftUI accent matching the pipeline editor theme (resolves per light/dark appearance).
    var swiftUIColor: Color {
        PipelineTheme.categoryColor(self)
    }
}

// MARK: - Step Action Grid

struct StepActionGrid: View {
    let fileType: ClopFileType?
    let onSelect: (String) -> Void

    var templates: [StepTemplate] {
        stepTemplates(for: fileType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("可用操作")
                .dimmed(9, weight: .medium)
            FlowLayout(spacing: 4) {
                ForEach(templates, id: \.name) { template in
                    let color = colorForCategory(template)
                    Button(action: {
                        let hasParams = !template.mandatoryParams.isEmpty || !template.optionalParams.isEmpty
                        let singleMandatory = template.mandatoryParams.count == 1 && template.optionalParams.isEmpty
                        let text = if singleMandatory {
                            "\(template.name)(\(template.mandatoryParams[0].name): "
                        } else if hasParams {
                            "\(template.name)("
                        } else {
                            template.create().displayString
                        }
                        onSelect(text)
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(color)
                                .frame(width: 6, height: 6)
                            Text(template.name)
                                .mono(10, weight: .medium)
                        }
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(template.description)
                }
            }
        }
    }

    func colorForCategory(_ template: StepTemplate) -> Color {
        template.create().category.swiftUIColor
    }
}

/// A simple flow layout that wraps items to the next line when they exceed the available width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight + (i > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
