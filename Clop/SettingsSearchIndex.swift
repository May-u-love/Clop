import Foundation

// MARK: - SettingEntry

/// One row of the Settings window, described in the words the user reads.
///
/// The index exists twice over: it backs the search field in Settings, and it is what an agent reads
/// through MCP. Both need the same wording, so a row is described once here rather than once for
/// people and once for machines.
///
/// `keys` names the `Defaults` keys the row writes, in the order the row shows them. A row that hosts
/// no single key (a folder list, a preset gallery, a permissions block) carries none, and still
/// appears so a search can point at the pane.
struct SettingEntry: Identifiable, Hashable {
    let id: String
    let keys: [String]
    let title: String
    let subtitle: String
    /// Words a person would search for that the title and subtitle do not already contain. The point
    /// is the vocabulary mismatch: someone types "mov" or "替换原件", the row says
    /// "Auto-conversion behaviour".
    let keywords: [String]
    let tab: SettingsView.Tabs
    let section: String

    /// The words of each field, kept apart so a hit in the title can outrank one buried in a subtitle.
    var searchFields: [(weight: Double, words: [String])] {
        [
            (3.0, SettingsSearchIndex.words(title)),
            (2.5, keywords.flatMap { SettingsSearchIndex.words($0) }),
            (1.0, SettingsSearchIndex.words(subtitle)),
            (0.6, SettingsSearchIndex.words(section) + SettingsSearchIndex.words(tab.title)),
        ]
    }

    /// The same fields unsplit, for the subsequence pass. It runs across word boundaries, so it needs
    /// the text rather than the words: "autoconv" is nowhere in `searchFields` and sits right there in
    /// "Auto-conversion behaviour".
    var searchTexts: [(weight: Double, text: String)] {
        [
            (3.0, title.lowercased()),
            (2.5, keywords.joined(separator: " ").lowercased()),
            (1.0, subtitle.lowercased()),
            (0.6, "\(section) \(tab.title)".lowercased()),
        ]
    }
}

// MARK: - SettingsSearchIndex

enum SettingsSearchIndex {
    /// Every user-facing row. Hand-maintained; `Scripts/settings-index-audit.py` fails the commit when
    /// a key named here stops existing, or a key gains a control and never gets an entry.
    static let all: [SettingEntry] = [
        SettingEntry(
            id: "general.main.syncSettingsCloud", keys: ["syncSettingsCloud"],
            title: "通过 iCloud 在多台 Mac 间同步设置",
            subtitle: "",
            keywords: ["icloud", "sync", "other macs", "settings"], tab: .general, section: ""
        ),
        SettingEntry(
            id: "general.main.defaultLinkExpiration", keys: ["defaultLinkExpiration"],
            title: "默认链接有效期",
            subtitle: "安全发送链接的存续时长",
            keywords: [], tab: .general, section: ""
        ),
        SettingEntry(
            id: "general.workingdirectory.workdirCleanupInterval", keys: ["workdirCleanupInterval"],
            title: "工作目录清理",
            subtitle: "定期从 Clop 工作目录删除早于此时间的文件",
            keywords: [], tab: .general, section: "Working directory"
        ),
        SettingEntry(
            id: "general.optimisation.stripMetadata", keys: ["stripMetadata"],
            title: "去除 EXIF 元数据",
            subtitle: "删除文件中可识别的元数据(如拍摄设备、位置、日期时间等)",
            keywords: ["exif", "metadata", "gps", "location", "privacy", "camera"], tab: .general, section: "Optimisation"
        ),
        SettingEntry(
            id: "general.optimisation.preserveColorMetadata", keys: ["preserveColorMetadata"],
            title: "保留色彩配置元数据",
            subtitle: "去除 EXIF 时不改动色彩配置标签",
            keywords: [], tab: .general, section: "Optimisation"
        ),
        SettingEntry(
            id: "general.optimisation.preserveDates", keys: ["preserveDates"],
            title: "保留文件的创建与修改时间",
            subtitle: "优化后的文件保留与原件相同的创建和修改时间",
            keywords: ["timestamp", "created", "modified", "date", "mtime"], tab: .general, section: "Optimisation"
        ),
        SettingEntry(
            id: "general.optimisation.optimisedFileProtectionMs", keys: ["optimisedFileProtectionMs"],
            title: "重复优化检测窗口",
            subtitle: "如果 iCloud Drive 文件被重复优化,调大此项",
            keywords: [], tab: .general, section: "Optimisation"
        ),

        SettingEntry(
            id: "clipboard.clipboard.enableClipboardOptimiser", keys: ["enableClipboardOptimiser"],
            title: "启用剪贴板优化器",
            subtitle: "监视拷贝的数据并自动优化",
            keywords: ["clipboard", "copy", "paste", "watch", "automatic"], tab: .clipboard, section: "Clipboard"
        ),
        SettingEntry(
            id: "clipboard.clipboard.optimiseTIFF", keys: ["optimiseTIFF"],
            title: "TIFF 数据",
            subtitle: "通常来自设计类应用,有时保持原样更好",
            keywords: [], tab: .clipboard, section: "Clipboard"
        ),
        SettingEntry(
            id: "clipboard.clipboard.optimiseHEICAVIFClipboard", keys: ["optimiseHEICAVIFClipboard"],
            title: "HEIC 与 AVIF 数据",
            subtitle: "",
            keywords: ["heic", "heif", "avif", "iphone", "photos", "hdr", "copied photo"], tab: .clipboard, section: "Clipboard"
        ),
        SettingEntry(
            id: "clipboard.clipboard.optimiseImagePathClipboard", keys: ["optimiseImagePathClipboard"],
            title: "图像文件",
            subtitle: "从访达拷贝图像时,得到的是文件路径而非图像数据",
            keywords: [], tab: .clipboard, section: "Clipboard"
        ),
        SettingEntry(
            id: "clipboard.clipboard.optimiseVideoClipboard", keys: ["optimiseVideoClipboard"],
            title: "视频文件",
            subtitle: "优化拷贝的视频文件路径",
            keywords: [], tab: .clipboard, section: "Clipboard"
        ),
        SettingEntry(
            id: "clipboard.clipboard.optimiseAudioClipboard", keys: ["optimiseAudioClipboard"],
            title: "音频文件",
            subtitle: "优化拷贝的音频文件路径",
            keywords: [], tab: .clipboard, section: "Clipboard"
        ),
        SettingEntry(
            id: "clipboard.clipboard.optimisePDFClipboard", keys: ["optimisePDFClipboard"],
            title: "PDF 文件",
            subtitle: "优化拷贝的 PDF 文件路径",
            keywords: [], tab: .clipboard, section: "Clipboard"
        ),
        SettingEntry(
            id: "clipboard.clipboard.appendClipboardResults", keys: ["appendClipboardResults"],
            title: "保留全部剪贴板结果",
            subtitle: "每次剪贴板优化单独显示一个结果,而非替换上一个",
            keywords: [], tab: .clipboard, section: "Clipboard"
        ),
        SettingEntry(
            id: "clipboard.clipboard.copyConsecutiveClipboardImages", keys: ["copyConsecutiveClipboardImages"],
            title: "在剪贴板中累积优化后的图像",
            subtitle: "每张新优化的图像都会加入剪贴板的文件列表,可在 Pixelmator、Affinity 等编辑器或笔记中一次性全部粘贴",
            keywords: [], tab: .clipboard, section: "Clipboard"
        ),
        SettingEntry(
            id: "clipboard.clipboard.clipboardAccumulationTimeout", keys: ["clipboardAccumulationTimeout"],
            title: "累积超时",
            subtitle: "连续拷贝的图像在多久内累积进同一文件列表",
            keywords: [], tab: .clipboard, section: "Clipboard"
        ),

        SettingEntry(
            id: "files.images.optimisedImageBehaviour", keys: ["optimisedImageBehaviour"],
            title: "优化后文件的存放位置",
            subtitle: "较小的文件保存到哪里,以及是否替换原件",
            keywords: ["placement", "where", "save", "saved", "replace", "original", "in place", "copy", "same folder", "指定文件夹", "overwrite", "output"], tab: .files, section: "Images"
        ),
        SettingEntry(
            id: "files.images.convertedImageBehaviour", keys: ["convertedImageBehaviour"],
            title: "兼容格式的自动转换行为",
            subtitle: "许多应用难以打开的格式会在优化前自动转换为支持广泛的格式。",
            keywords: ["webp", "avif", "heic", "bmp", "png", "jpeg", "convert", "conversion", "replace", "original", "in place", "copy", "keep", "beside", "automatic", "compatibility"], tab: .files, section: "Images"
        ),
        SettingEntry(
            id: "files.images.manualConvertedImageBehaviour", keys: ["manualConvertedImageBehaviour"],
            title: "手动转换行为",
            subtitle: "通过点按悬浮结果上的扩展名,或右键菜单中的 **转换为...** 子菜单选择新格式。",
            keywords: ["convert to", "manual", "right click", "extension", "click", "replace", "original", "in place", "copy"], tab: .files, section: "Images"
        ),
        SettingEntry(
            id: "files.videos.optimisedVideoBehaviour", keys: ["optimisedVideoBehaviour"],
            title: "优化后文件的存放位置",
            subtitle: "较小的文件保存到哪里,以及是否替换原件",
            keywords: ["placement", "where", "save", "saved", "replace", "original", "in place", "copy", "same folder", "指定文件夹", "overwrite", "output"], tab: .files, section: "Videos"
        ),
        SettingEntry(
            id: "files.videos.convertedVideoBehaviour", keys: ["convertedVideoBehaviour"],
            title: "兼容格式的自动转换行为",
            subtitle: "许多应用难以打开的格式会在优化前自动转换为支持广泛的格式。",
            keywords: ["mov", "mkv", "webm", "mp4", "convert", "conversion", "replace", "original", "in place", "copy", "keep", "leftover", "beside", "automatic", "compatibility"], tab: .files, section: "Videos"
        ),
        SettingEntry(
            id: "files.videos.manualConvertedVideoBehaviour", keys: ["manualConvertedVideoBehaviour"],
            title: "手动转换行为",
            subtitle: "通过点按悬浮结果上的扩展名,或右键菜单中的 **转换为...** 子菜单选择新格式。",
            keywords: ["convert to", "manual", "right click", "extension", "click", "replace", "original", "in place", "copy"], tab: .files, section: "Videos"
        ),
        SettingEntry(
            id: "files.audio.optimisedAudioBehaviour", keys: ["optimisedAudioBehaviour"],
            title: "优化后文件的存放位置",
            subtitle: "较小的文件保存到哪里,以及是否替换原件",
            keywords: ["placement", "where", "save", "saved", "replace", "original", "in place", "copy", "same folder", "指定文件夹", "overwrite", "output"], tab: .files, section: "Audio"
        ),
        SettingEntry(
            id: "files.audio.convertedAudioBehaviour", keys: ["convertedAudioBehaviour"],
            title: "兼容格式的自动转换行为",
            subtitle: "许多应用难以打开的格式会在优化前自动转换为支持广泛的格式。",
            keywords: ["wav", "aiff", "flac", "aac", "mp3", "convert", "conversion", "replace", "original", "in place", "copy", "keep", "beside", "automatic", "compatibility"], tab: .files, section: "Audio"
        ),
        SettingEntry(
            id: "files.audio.manualConvertedAudioBehaviour", keys: ["manualConvertedAudioBehaviour"],
            title: "手动转换行为",
            subtitle: "通过点按悬浮结果上的扩展名,或右键菜单中的 **转换为...** 子菜单选择新格式。",
            keywords: ["convert to", "manual", "right click", "extension", "click", "replace", "original", "in place", "copy"], tab: .files, section: "Audio"
        ),
        SettingEntry(
            id: "files.pdf.optimisedPDFBehaviour", keys: ["optimisedPDFBehaviour"],
            title: "优化后文件的存放位置",
            subtitle: "较小的文件保存到哪里,以及是否替换原件",
            keywords: ["placement", "where", "save", "saved", "replace", "original", "in place", "copy", "same folder", "指定文件夹", "overwrite", "output"], tab: .files, section: "PDF"
        ),

        SettingEntry(
            id: "video.optimisationrules.removeAudioFromVideos", keys: ["removeAudioFromVideos"],
            title: "移除优化后视频的音轨",
            subtitle: "",
            keywords: ["mute", "silent", "sound", "audio track", "strip"], tab: .video, section: "Optimisation rules"
        ),
        SettingEntry(
            id: "video.optimisationrules.capVideoFPS", keys: ["capVideoFPS", "targetVideoFPS"],
            title: "限制帧率",
            subtitle: "",
            keywords: ["fps", "frame rate", "帧率", "30fps", "60fps", "smooth", "slow", "half", "quarter", "1/2 of source", "1/4 of source", "choppy", "screen recording", "stuttering"], tab: .video,
            section: "Optimisation rules"
        ),
        SettingEntry(
            id: "video.optimisationrules.playbackSpeedFrameBehaviour", keys: ["playbackSpeedFrameBehaviour"],
            title: "播放速度调整",
            subtitle: "变速时是丢帧还是重新计时",
            keywords: [], tab: .video, section: "Optimisation rules"
        ),
        SettingEntry(
            id: "video.compatibility.convertAudioToAAC", keys: ["convertAudioToAAC"],
            title: "将音频转换为 AAC",
            subtitle: "把视频音轨重编码为 AAC 以提升兼容性",
            keywords: [], tab: .video, section: "Compatibility"
        ),

        SettingEntry(
            id: "audio.optimisationrules.audioCoverArt", keys: ["audioCoverArt"],
            title: "封面图",
            subtitle: "仅 AAC、MP3、FLAC 等可存储封面的格式会保留封面图,其余格式会丢弃。",
            keywords: ["artwork", "thumbnail", "picture", "embedded", "id3", "m4a", "strip", "remove", "metadata", "tag", "album"], tab: .audio, section: "Optimisation rules"
        ),

        SettingEntry(
            id: "images.main.customNameTemplateForClipboardImages", keys: ["customNameTemplateForClipboardImages"],
            title: "剪贴板图像的命名模板",
            subtitle: "剪贴板图像的保存命名规则",
            keywords: [], tab: .images, section: ""
        ),
        SettingEntry(
            id: "images.main.photoCropOrientation", keys: ["photoCropOrientation"],
            title: "照片裁剪方向",
            subtitle: "来自「照片」应用的图像裁剪方式",
            keywords: [], tab: .images, section: ""
        ),
        SettingEntry(
            id: "images.filenamehandling.copyImageFilePath", keys: ["copyImageFilePath"],
            title: "复制图像路径",
            subtitle: "拷贝优化后的图像数据时,同时复制图像文件路径",
            keywords: [], tab: .images, section: "File name handling"
        ),
        SettingEntry(
            id: "images.filenamehandling.useCustomNameTemplateForClipboardImages", keys: ["useCustomNameTemplateForClipboardImages"],
            title: "为剪贴板图像使用命名模板",
            subtitle: "",
            keywords: [], tab: .images, section: "File name handling"
        ),
        SettingEntry(
            id: "images.photosintegration.enablePhotosIntegration", keys: ["enablePhotosIntegration"],
            title: "优化从「照片」应用拷贝的图像",
            subtitle: "",
            keywords: [], tab: .images, section: "Photos integration"
        ),
        SettingEntry(
            id: "images.optimisationrules.gifFrameDropBehaviour", keys: ["gifFrameDropBehaviour"],
            title: "GIF 丢帧",
            subtitle: "压缩系数高于 80% 时,动图 GIF 会每 4、3 或 2 帧丢 1 帧:可让动画用剩余帧播得更快,也可保持时长、每帧显示更久",
            keywords: ["gif", "animation", "frames", "drop", "choppy", "smooth"], tab: .images, section: "Optimisation rules"
        ),
        SettingEntry(
            id: "images.optimisationrules.convertHDRToSDR", keys: ["convertHDRToSDR"],
            title: "将 HDR 转换为 SDR",
            subtitle: "",
            keywords: ["hdr", "sdr", "gain map", "xdr", "highlights", "brightness", "tone mapping", "file size"], tab: .images, section: "Optimisation rules"
        ),

        SettingEntry(
            id: "dropzone.dropzone.enableDragAndDrop", keys: ["enableDragAndDrop"],
            title: "启用投放区",
            subtitle: "允许把文件、路径和 URL 拖到全局投放区进行优化",
            keywords: ["drop zone", "drag", "drop"], tab: .dropzone, section: "Drop zone"
        ),
        SettingEntry(
            id: "dropzone.dropzone.onlyShowDropZoneOnOption", keys: ["onlyShowDropZoneOnOption"],
            title: "需要按住 ⌥ Option 才显示投放区",
            subtitle: "默认隐藏投放区,拖文件时不打扰;按一次 ⌥ Option 手动显示",
            keywords: [], tab: .dropzone, section: "Drop zone"
        ),
        SettingEntry(
            id: "dropzone.dropzone.autoCopyToClipboard", keys: ["autoCopyToClipboard"],
            title: "自动将优化后的文件复制到剪贴板",
            subtitle: "复制投放区或文件夹监视优化产生的文件,优化结束后即可直接粘贴",
            keywords: [], tab: .dropzone, section: "Drop zone"
        ),
        SettingEntry(
            id: "dropzone.batchmode.useBatchModeForFolders", keys: ["useBatchModeForFolders"],
            title: "大量拖入时使用批量模式",
            subtitle: "一次拖入大量文件(或含大量文件的文件夹)会打开一个批量窗口统一高效优化;原件先备份,可恢复。",
            keywords: [], tab: .dropzone, section: "Batch mode"
        ),
        SettingEntry(
            id: "dropzone.batchmode.batchModeFileCountThreshold", keys: ["batchModeFileCountThreshold"],
            title: "批量模式文件数阈值",
            subtitle: "拖入文件数超过此值时使用批量模式",
            keywords: [], tab: .dropzone, section: "Batch mode"
        ),

        SettingEntry(
            id: "presetZones.showingpresetzones.onlyShowPresetZonesOnControlTapped", keys: ["onlyShowPresetZonesOnControlTapped"],
            title: "按住或点按 Control 键显示预设区",
            subtitle: "按住时显示,松开消失;点按则保持显示",
            keywords: [], tab: .presetZones, section: "Showing preset zones"
        ),

        SettingEntry(
            id: "floating.main.enableFloatingResults", keys: ["enableFloatingResults"],
            title: "显示悬浮结果",
            subtitle: "关闭后 Clop 将以无界面模式运行,但仍会在后台优化文件。投放区可在「投放区」标签页单独关闭",
            keywords: [], tab: .floating, section: ""
        ),
        SettingEntry(
            id: "floating.layout.floatingResultsCorner", keys: ["floatingResultsCorner"],
            title: "屏幕位置",
            subtitle: "悬浮结果出现在哪个角落",
            keywords: [], tab: .floating, section: "Layout"
        ),
        SettingEntry(
            id: "floating.layout.followCursorScreen", keys: ["followCursorScreen"],
            title: "跟随光标跨屏幕移动",
            subtitle: "光标在另一块屏幕停留几秒后,结果会自动移过去",
            keywords: [], tab: .floating, section: "Layout"
        ),
        SettingEntry(
            id: "floating.layout.hideFloatingResultTooltips", keys: ["hideFloatingResultTooltips"],
            title: "隐藏按钮提示",
            subtitle: "悬停结果按钮上时不显示操作名称标签",
            keywords: [], tab: .floating, section: "Layout"
        ),
        SettingEntry(
            id: "floating.layout.alwaysShowCompactResults", keys: ["alwaysShowCompactResults"],
            title: "始终使用紧凑布局",
            subtitle: "默认情况下,屏幕上结果超过 5 个时自动切换为紧凑布局",
            keywords: [], tab: .floating, section: "Layout"
        ),
        SettingEntry(
            id: "floating.fulllayout.formatPickerStyle", keys: ["formatPickerStyle"],
            title: "切换格式的方式",
            subtitle: "悬浮结果上格式控件的交互方式",
            keywords: [], tab: .floating, section: "Full layout"
        ),
        SettingEntry(
            id: "floating.fulllayout.showCopyClearButtons", keys: ["showCopyClearButtons"],
            title: "显示「全部复制」和「全部清空」按钮",
            subtitle: "",
            keywords: [], tab: .floating, section: "Full layout"
        ),
        SettingEntry(
            id: "floating.fulllayout.dismissFloatingResultOnDrop", keys: ["dismissFloatingResultOnDrop"],
            title: "拖到外部时关闭结果",
            subtitle: "",
            keywords: [], tab: .floating, section: "Full layout"
        ),
        SettingEntry(
            id: "floating.fulllayout.dismissFloatingResultOnUpload", keys: ["dismissFloatingResultOnUpload"],
            title: "上传到 Dropshare 时关闭结果",
            subtitle: "",
            keywords: [], tab: .floating, section: "Full layout"
        ),
        SettingEntry(
            id: "floating.fulllayout.autoHideFloatingResults", keys: ["autoHideFloatingResults"],
            title: "自动隐藏悬浮结果",
            subtitle: "",
            keywords: [], tab: .floating, section: "Full layout"
        ),
        SettingEntry(
            id: "floating.fulllayout.autoHideFloatingResultsAfter", keys: ["autoHideFloatingResultsAfter"],
            title: "文件结果自动隐藏时间",
            subtitle: "文件结果消失前的秒数",
            keywords: [], tab: .floating, section: "Full layout"
        ),
        SettingEntry(
            id: "floating.fulllayout.autoHideClipboardResultAfter", keys: ["autoHideClipboardResultAfter"],
            title: "剪贴板结果自动隐藏时间",
            subtitle: "剪贴板结果消失前的秒数",
            keywords: [], tab: .floating, section: "Full layout"
        ),
        SettingEntry(
            id: "floating.compactlayout.showCompactImages", keys: ["showCompactImages"],
            title: "紧凑结果中显示图像",
            subtitle: "",
            keywords: [], tab: .floating, section: "Compact layout"
        ),
        SettingEntry(
            id: "floating.compactlayout.dismissCompactResultOnDrop", keys: ["dismissCompactResultOnDrop"],
            title: "拖到外部时关闭紧凑结果",
            subtitle: "",
            keywords: [], tab: .floating, section: "Compact layout"
        ),
        SettingEntry(
            id: "floating.compactlayout.dismissCompactResultOnUpload", keys: ["dismissCompactResultOnUpload"],
            title: "上传到 Dropshare 时关闭紧凑结果",
            subtitle: "",
            keywords: [], tab: .floating, section: "Compact layout"
        ),
        SettingEntry(
            id: "floating.compactlayout.autoClearAllCompactResultsAfter", keys: ["autoClearAllCompactResultsAfter"],
            title: "紧凑结果全部清空时间",
            subtitle: "全部紧凑结果清空前的秒数",
            keywords: [], tab: .floating, section: "Compact layout"
        ),

        SettingEntry(
            id: "mcp.main.mcpEnabled", keys: ["mcpEnabled"],
            title: "接受智能体的修改",
            subtitle: "允许优化文件、修改设置、保存管线;无论开关,读取设置与管线始终允许",
            keywords: ["mcp", "agent", "ai", "claude", "cursor", "llm", "automation"], tab: .mcp, section: ""
        ),
        SettingEntry(
            id: "mcp.main.mcpAllowScriptSteps", keys: ["mcpAllowScriptSteps"],
            title: "允许智能体写入脚本步骤",
            subtitle: "脚本步骤会执行任意代码。关闭时,Clop 会拒绝包含脚本步骤的智能体管线并指出该步骤;你自己编写的脚本不受影响",
            keywords: ["mcp", "agent", "script", "shell", "code", "pipeline", "dangerous"], tab: .mcp, section: ""
        ),

        // MARK: added from the domain sweep

        SettingEntry(
            id: "video.watchpaths.videoDirs", keys: [],
            title: "监视路径",
            subtitle: "这些文件夹里出现的视频会被自动优化",
            keywords: ["directory", "desktop", "downloads", "monitor", "automatic", "add", "clopignore", "ignore rules", "not picking up", "nothing happens", "unwatched"], tab: .video, section: "Watch paths"
        ),
        SettingEntry(
            id: "video.watchpaths.enableAutomaticVideoOptimisations", keys: ["enableAutomaticVideoOptimisations"],
            title: "启用视频自动优化",
            subtitle: "",
            keywords: ["watch", "folders", "background", "monitor", "stopped working", "disabled", "paused", "desktop", "nothing happens", "turn off"], tab: .video, section: "Watch paths"
        ),
        SettingEntry(
            id: "video.optimisationrules.videoCompression", keys: ["videoCompression"],
            title: "压缩",
            subtitle: "",
            keywords: ["encoder", "hardware", "software", "adaptive", "视觉无损", "quality", "crf", "bitrate", "factor", "auto", "slower", "cpu", "battery", "smaller size", "better quality"], tab: .video,
            section: "Optimisation rules"
        ),
        SettingEntry(
            id: "video.optimisationrules.minVideoFPS", keys: ["minVideoFPS"],
            title: "但不低于",
            subtitle: "",
            keywords: ["fps", "minimum", "floor", "10fps", "24fps", "30fps", "60fps", "1/2 of source", "1/4 of source", "fraction", "frame rate", "too slow", "choppy", "stuttering"], tab: .video, section: "Optimisation rules"
        ),
        SettingEntry(
            id: "video.watchedfilefilters.minVideoSizeKB", keys: ["minVideoSizeKB", "maxVideoSizeMB"],
            title: "文件大小",
            subtitle: "只优化介于设定大小之间的文件",
            keywords: ["mb", "kb", "gb", "skipped", "ignored", "too big", "too large", "too small", "threshold", "limit", "range", "untouched"], tab: .video, section: "Watched file filters"
        ),
        SettingEntry(
            id: "video.watchedfilefilters.minVideoResolution", keys: ["minVideoResolution", "maxVideoResolution"],
            title: "分辨率",
            subtitle: "只优化宽高介于设定值之间的文件",
            keywords: ["px", "pixels", "4k", "1080p", "tiny", "thumbnail", "upscaled", "skipped", "ignored", "threshold", "limit", "range", "dimensions"], tab: .video, section: "Watched file filters"
        ),
        SettingEntry(
            id: "video.watchedfilefilters.maxVideoFileCount", keys: ["maxVideoFileCount"],
            title: "文件数量",
            subtitle: "一次拷贝/移动的视频超过此数量时跳过优化",
            keywords: ["batch", "bulk", "drag", "import", "multiple", "dozens", "threshold", "limit", "nothing happens", "ignored"], tab: .video, section: "Watched file filters"
        ),
        SettingEntry(
            id: "video.watchedfilefilters.videoFormatsToSkip", keys: ["videoFormatsToSkip"],
            title: "忽略这些扩展名的视频",
            subtitle: "",
            keywords: ["mkv", "m4v", "avi", "webm", "mov", "mp4", "mpeg", "skip", "exclude", "deny list", "format", "untouched", "left alone"], tab: .video, section: "Watched file filters"
        ),
        SettingEntry(
            id: "video.compatibility.formatsToConvertToMP4", keys: ["formatsToConvertToMP4"],
            title: "转换为 mp4",
            subtitle: "",
            keywords: ["mov", "webm", "mkv", "avi", "mpeg", "m4v", "quicktime", "container", "remux", "incompatible", "cannot open", "unsupported", "automatic"], tab: .video, section: "Compatibility"
        ),
        SettingEntry(
            id: "general.editwithexternalapp.editorAppVideo", keys: ["editorAppVideo"],
            title: "视频",
            subtitle: "",
            keywords: ["editor", "external app", "open with", "capcut", "final cut", "premiere", "davinci", "cmd e", "right click", "choose app", "bundle path"], tab: .general, section: "Edit with external app"
        ),
        SettingEntry(
            id: "files.videos.sameFolderNameTemplateVideo", keys: ["sameFolderNameTemplateVideo"],
            title: "存到同文件夹的优化视频命名模板",
            subtitle: "",
            keywords: ["pattern", "rename", "filename", "suffix", "counter", "date", "clop", "placeholder", "token", "variables"], tab: .files, section: "Videos"
        ),
        SettingEntry(
            id: "files.videos.specificFolderNameTemplateVideo", keys: ["specificFolderNameTemplateVideo"],
            title: "存到指定文件夹的优化视频路径模板",
            subtitle: "",
            keywords: ["destination", "输出目录", "subfolder", "pattern", "rename", "filename", "where", "placeholder", "token", "location"], tab: .files, section: "Videos"
        ),
        SettingEntry(
            id: "files.videos.convertedSameFolderNameTemplateVideo", keys: ["convertedSameFolderNameTemplateVideo"],
            title: "存到同文件夹的转换视频命名模板",
            subtitle: "",
            keywords: ["mp4", "mov", "pattern", "rename", "filename", "suffix", "leftover", "duplicate", "placeholder", "token"], tab: .files, section: "Videos"
        ),
        SettingEntry(
            id: "files.videos.convertedSpecificFolderNameTemplateVideo", keys: ["convertedSpecificFolderNameTemplateVideo"],
            title: "存到指定文件夹的转换视频路径模板",
            subtitle: "",
            keywords: ["mp4", "mov", "destination", "输出目录", "subfolder", "pattern", "where", "placeholder", "token", "location"], tab: .files, section: "Videos"
        ),
        SettingEntry(
            id: "images.watchpaths.imageDirs", keys: [],
            title: "监视路径",
            subtitle: "这些文件夹里出现的图像会被自动优化",
            keywords: ["directories", "desktop", "downloads", "screenshots", "monitor", "automatic", "clopignore", "ignore rules", "per-folder", "add", "remove"], tab: .images, section: "Watch paths"
        ),
        SettingEntry(
            id: "images.watchpaths.enableAutomaticImageOptimisations", keys: ["enableAutomaticImageOptimisations"],
            title: "启用图像自动优化",
            subtitle: "",
            keywords: ["watch", "folder", "background", "screenshots", "stopped working", "nothing happens", "turn off", "pause", "monitor", "checkbox"], tab: .images, section: "Watch paths"
        ),
        SettingEntry(
            id: "images.photosintegration.maxCopiedPhotosCount", keys: ["maxCopiedPhotosCount"],
            title: "文件数量",
            subtitle: "",
            keywords: ["photos", "photos.app", "copied at once", "batch", "bulk", "how many", "limit", "threshold", "skip", "albums"], tab: .images, section: "Photos integration"
        ),
        SettingEntry(
            id: "images.photosintegration.maxPhotosLength", keys: ["maxPhotosLength"],
            title: "缩小到",
            subtitle: "",
            keywords: ["photos", "px", "pixels", "resize", "longest edge", "shrink", "huge", "crop", "empty", "unlimited"], tab: .images, section: "Photos integration"
        ),
        SettingEntry(
            id: "images.optimisationrules.imageCompression", keys: ["imageCompression"],
            title: "压缩",
            subtitle: "",
            keywords: ["quality", "factor", "percent", "slider", "adaptive", "lossy", "aggressive", "smaller", "blurry", "artifacts", "entropy", "jpeg", "png", "file size"], tab: .images, section: "Optimisation rules"
        ),
        SettingEntry(
            id: "images.watchedfilefilters.minImageSizeKB", keys: ["minImageSizeKB", "maxImageSizeMB"],
            title: "文件大小",
            subtitle: "",
            keywords: ["skip", "limit", "range", "kb", "mb", "bytes", "megabytes", "too small", "too large", "threshold", "ignore", "not optimised"], tab: .images, section: "Watched file filters"
        ),
        SettingEntry(
            id: "images.watchedfilefilters.minImageResolution", keys: ["minImageResolution", "maxImageResolution"],
            title: "分辨率",
            subtitle: "",
            keywords: ["pixels", "px", "width", "height", "dimensions", "skip", "limit", "range", "icons", "thumbnails", "huge", "ignore"], tab: .images, section: "Watched file filters"
        ),
        SettingEntry(
            id: "images.watchedfilefilters.maxImageFileCount", keys: ["maxImageFileCount"],
            title: "文件数量",
            subtitle: "",
            keywords: ["batch", "bulk", "how many", "at once", "copied at once", "moved at once", "limit", "threshold", "skip", "mass copy"], tab: .images, section: "Watched file filters"
        ),
        SettingEntry(
            id: "images.watchedfilefilters.imageFormatsToSkip", keys: ["imageFormatsToSkip"],
            title: "忽略这些扩展名的图像",
            subtitle: "",
            keywords: ["tiff", "psd", "raw", "skip", "exclude", "never optimise", "leave alone", "format", "blacklist", "deny list"], tab: .images, section: "Watched file filters"
        ),
        SettingEntry(
            id: "images.compatibility.formatsToConvertToJPEG", keys: ["formatsToConvertToJPEG"],
            title: "转换为 jpeg",
            subtitle: "",
            keywords: ["webp", "avif", "heic", "bmp", "jxl", "tiff", "compatibility", "cannot open", "unsupported", "automatic", "before optimisation"], tab: .images, section: "Compatibility"
        ),
        SettingEntry(
            id: "images.compatibility.formatsToConvertToPNG", keys: ["formatsToConvertToPNG"],
            title: "转换为 png",
            subtitle: "",
            keywords: ["tiff", "bmp", "webp", "avif", "heic", "jxl", "transparency", "alpha", "lossless", "compatibility", "unsupported", "cannot open"], tab: .images, section: "Compatibility"
        ),
        SettingEntry(
            id: "files.images.sameFolderNameTemplateImage", keys: ["sameFolderNameTemplateImage"],
            title: "「与原件同文件夹」的命名模板",
            subtitle: "",
            keywords: ["%f", "suffix", "optimised", "rename", "naming", "filename", "variables", "date", "counter", "overwrite"], tab: .files, section: "Images"
        ),
        SettingEntry(
            id: "files.images.specificFolderNameTemplateImage", keys: ["specificFolderNameTemplateImage"],
            title: "「指定文件夹」的路径模板",
            subtitle: "",
            keywords: ["%P", "%f", "folder", "destination", "output path", "where", "naming", "pattern", "subfolder", "variables"], tab: .files, section: "Images"
        ),
        SettingEntry(
            id: "files.images.convertedSameFolderNameTemplateImage", keys: ["convertedSameFolderNameTemplateImage"],
            title: "「与原件同文件夹」时转换后文件的命名模板",
            subtitle: "",
            keywords: ["%f", "webp", "heic", "jpeg", "conversion", "rename", "naming", "pattern", "leftover", "variables", "manual convert"], tab: .files, section: "Images"
        ),
        SettingEntry(
            id: "files.images.convertedSpecificFolderNameTemplateImage", keys: ["convertedSpecificFolderNameTemplateImage"],
            title: "「指定文件夹」时转换后文件的路径模板",
            subtitle: "",
            keywords: ["%P", "%f", "webp", "heic", "jpeg", "conversion", "destination", "output path", "subfolder", "naming", "manual convert"], tab: .files, section: "Images"
        ),
        SettingEntry(
            id: "general.editwithexternalapp.editorAppImage", keys: ["editorAppImage"],
            title: "图像",
            subtitle: "",
            keywords: ["editor", "external app", "open with", "photoshop", "pixelmator", "affinity", "preview", "edit with", "⌘e", "cmd e", "choose app"], tab: .general, section: "Edit with external app"
        ),
        SettingEntry(
            id: "audio.watchpaths.audioDirs", keys: [],
            title: "监视路径",
            subtitle: "这些文件夹里出现的音频会被自动优化",
            keywords: ["folder", "directory", "watched", "monitor", "add folder", "incoming", "music", "downloads", "automatic", "clopignore", "ignore rules", "path list"], tab: .audio, section: "Watch paths"
        ),
        SettingEntry(
            id: "audio.watchpaths.enableAutomaticAudioOptimisations", keys: ["enableAutomaticAudioOptimisations"],
            title: "启用 **音频** 自动优化",
            subtitle: "",
            keywords: ["watch", "watcher", "folder", "automatic", "background", "turn on", "turn off", "disable", "stop", "not optimising", "nothing happens"], tab: .audio, section: "Watch paths"
        ),
        SettingEntry(
            id: "audio.optimisationrules.audioCompression", keys: ["audioCompression"],
            title: "压缩",
            subtitle: "WAV、AIFF 和 FLAC 是无损格式,压缩系数对它们不生效。",
            keywords: ["quality", "bitrate", "kbps", "percent", "slider", "smaller", "file size", "vbr", "可变码率", "aac", "mp3", "lossy", "aggressive"], tab: .audio, section: "Optimisation rules"
        ),
        SettingEntry(
            id: "audio.watchedfilefilters.minAudioSizeKB", keys: ["minAudioSizeKB", "maxAudioSizeMB"],
            title: "文件大小",
            subtitle: "",
            keywords: ["skip", "skipped", "ignore", "threshold", "too big", "too small", "limit", "range", "mb", "kb", "large", "small", "podcast", "untouched"], tab: .audio, section: "Watched file filters"
        ),
        SettingEntry(
            id: "audio.watchedfilefilters.maxAudioFileCount", keys: ["maxAudioFileCount"],
            title: "文件数量",
            subtitle: "",
            keywords: ["batch", "bulk", "many", "at once", "limit", "skip", "copied", "moved", "album", "import", "nothing happens", "too many"], tab: .audio, section: "Watched file filters"
        ),
        SettingEntry(
            id: "audio.compatibility.formatsToConvertToAAC", keys: ["formatsToConvertToAAC"],
            title: "转换为 AAC(M4A)",
            subtitle: "",
            keywords: ["m4a", "flac", "aiff", "wav", "lossless", "target", "output", "pills", "toggle", "re-encode", "exclusive"], tab: .audio, section: "Compatibility"
        ),
        SettingEntry(
            id: "audio.compatibility.formatsToConvertToMP3", keys: ["formatsToConvertToMP3"],
            title: "转换为 MP3",
            subtitle: "",
            keywords: ["wav", "flac", "aiff", "lossless", "target", "output", "pills", "toggle", "re-encode", "exclusive"], tab: .audio, section: "Compatibility"
        ),
        SettingEntry(
            id: "general.editwithexternalapp.editorAppAudio", keys: ["editorAppAudio"],
            title: "音频",
            subtitle: "",
            keywords: ["editor", "external app", "open with", "choose", "edit", "cmd e", "audacity", "ferrite", "fission", "default", "waveform"], tab: .general, section: "Edit with external app"
        ),
        SettingEntry(
            id: "files.audio.sameFolderNameTemplateAudio", keys: ["sameFolderNameTemplateAudio"],
            title: "优化后音频的命名模板",
            subtitle: "",
            keywords: ["filename", "rename", "pattern", "%f", "variables", "placeholder", "same folder", "placement", "copy", "beside", "next to"], tab: .files, section: "Audio"
        ),
        SettingEntry(
            id: "files.audio.specificFolderNameTemplateAudio", keys: ["specificFolderNameTemplateAudio"],
            title: "优化后音频的路径模板",
            subtitle: "",
            keywords: ["filename", "rename", "pattern", "%p", "%f", "variables", "placeholder", "指定文件夹", "placement", "destination", "output"], tab: .files, section: "Audio"
        ),
        SettingEntry(
            id: "files.audio.convertedSameFolderNameTemplateAudio", keys: ["convertedSameFolderNameTemplateAudio"],
            title: "转换后音频的命名模板",
            subtitle: "",
            keywords: ["filename", "rename", "pattern", "%f", "conversion", "wav", "mp3", "aac", "variables", "placeholder", "same folder", "beside"], tab: .files, section: "Audio"
        ),
        SettingEntry(
            id: "files.audio.convertedSpecificFolderNameTemplateAudio", keys: ["convertedSpecificFolderNameTemplateAudio"],
            title: "转换后音频的路径模板",
            subtitle: "",
            keywords: ["filename", "rename", "pattern", "%p", "%f", "conversion", "wav", "mp3", "variables", "placeholder", "指定文件夹", "destination", "output"], tab: .files, section: "Audio"
        ),
        SettingEntry(
            id: "pdf.watchpaths.pdfDirs", keys: [],
            title: "监视路径",
            subtitle: "这些文件夹里出现的 PDF 会被自动优化",
            keywords: ["directories", "monitor", "downloads", "desktop", "clopignore", "ignore rules", "drop", "incoming"], tab: .pdf, section: "Watch paths"
        ),
        SettingEntry(
            id: "pdf.watchpaths.enableAutomaticPDFOptimisations", keys: ["enableAutomaticPDFOptimisations"],
            title: "启用 PDF 自动优化",
            subtitle: "",
            keywords: ["watch", "folder", "background", "monitor", "turn off", "disable", "stop", "incoming", "downloads", "not optimising"], tab: .pdf, section: "Watch paths"
        ),
        SettingEntry(
            id: "pdf.optimisationrules.pdfDPI", keys: ["pdfDPI"],
            title: "压缩",
            subtitle: "Clop 按源图像密度自动为每个 PDF 选择 DPI,并缩小超过它的图像",
            keywords: ["resolution", "quality", "adaptive", "scanned", "lossless", "150", "300", "blurry", "ghostscript", "shrink", "smaller", "file size", "text quality", "pixelated"], tab: .pdf, section: "Optimisation rules"
        ),
        SettingEntry(
            id: "pdf.watchedfilefilters.minPDFSizeKB", keys: ["minPDFSizeKB", "maxPDFSizeMB"],
            title: "文件大小",
            subtitle: "",
            keywords: ["skip", "too big", "too small", "ignored", "limit", "minimum", "maximum", "mb", "kb", "range", "large", "huge", "not optimised"], tab: .pdf, section: "Watched file filters"
        ),
        SettingEntry(
            id: "pdf.watchedfilefilters.maxPDFFileCount", keys: ["maxPDFFileCount"],
            title: "文件数量",
            subtitle: "一次拷贝/移动的 PDF 超过此数量时跳过优化",
            keywords: ["batch", "bulk", "threshold", "ignored", "watched folder", "nothing happened", "limit", "multiple files"], tab: .pdf, section: "Watched file filters"
        ),
        SettingEntry(
            id: "general.editwithexternalapp.editorAppPDF", keys: ["editorAppPDF"],
            title: "PDF 文件",
            subtitle: "",
            keywords: ["editor", "open with", "external app", "edit", "choose app", "preview", "acrobat", "pdf expert", "cmd e", "⌘e", "default app", "hand off"], tab: .general, section: "Edit with external app"
        ),
        SettingEntry(
            id: "files.pdf.sameFolderNameTemplatePDF", keys: ["sameFolderNameTemplatePDF"],
            title: "同文件夹命名模板",
            subtitle: "",
            keywords: ["filename", "rename", "pattern", "suffix", "optimised", "tokens", "next to", "beside", "overwrite", "copy"], tab: .files, section: "PDF"
        ),
        SettingEntry(
            id: "files.pdf.specificFolderNameTemplatePDF", keys: ["specificFolderNameTemplatePDF"],
            title: "指定文件夹命名模板",
            subtitle: "",
            keywords: ["path", "filename", "rename", "pattern", "destination", "output", "tokens", "where do they go", "subfolder"], tab: .files, section: "PDF"
        ),
        SettingEntry(
            id: "images.photosintegration.photoCropOrientation", keys: ["photoCropOrientation"],
            title: "照片裁剪方向",
            subtitle: "",
            keywords: ["portrait", "landscape", "adaptive", "longest edge", "height", "width", "resize", "aspect", "segmented", "picker"], tab: .images, section: "Photos integration"
        ),
        SettingEntry(
            id: "clipboard.ignoredapps.clipboardIgnoredAppBundleIds", keys: [],
            title: "忽略的应用",
            subtitle: "这些应用在前台时跳过剪贴板优化",
            keywords: ["denylist", "blacklist", "exclude", "exclusion", "bundle id", "frontmost", "foreground app", "pixelmator", "figma", "password manager", "copy", "paste", "per app"], tab: .clipboard, section: "Ignored apps"
        ),
        SettingEntry(
            id: "general.main.showMenubarIcon", keys: ["showMenubarIcon", "useClassicMenubarIcon", "useGeometricMenubarIcon"],
            title: "菜单栏图标",
            subtitle: "",
            keywords: ["status bar", "tray", "hide", "hidden", "style", "classic", "geometric", "new", "eye slash", "top bar", "missing", "disappeared"], tab: .general, section: ""
        ),
        SettingEntry(
            id: "general.main.allowClopToAppearInScreenshots", keys: ["allowClopToAppearInScreenshots"],
            title: "截屏时显示 Clop 界面",
            subtitle: "",
            keywords: ["screen recording", "capture", "悬浮结果", "drop zone", "visible", "hidden", "cleanshot", "record", "demo", "share"], tab: .general, section: ""
        ),
        SettingEntry(
            id: "general.main.pauseAutomaticOptimisations", keys: ["pauseAutomaticOptimisations"],
            title: "暂停自动优化",
            subtitle: "",
            keywords: ["resume", "stop", "disable", "snooze", "watcher", "监视的文件夹", "clipboard", "nothing happens", "not working", "temporarily", "off"], tab: .general, section: ""
        ),
        SettingEntry(
            id: "general.workingdirectory.workdir", keys: ["workdir"],
            title: "工作目录路径",
            subtitle: "",
            keywords: ["workdir", "folder", "cache", "temp", "temporary", "backups", "scratch", "disk space", "location", "move", "reset"], tab: .general, section: "Working directory"
        ),
        SettingEntry(
            id: "keys.triggerkeys.keyComboModifiers", keys: ["keyComboModifiers"],
            title: "触发键",
            subtitle: "",
            keywords: ["modifier", "modifiers", "hotkey", "shortcut", "control", "shift", "option", "command", "ctrl", "hold", "combo", "global"], tab: .keys, section: "Trigger keys"
        ),
        SettingEntry(
            id: "keys.actionkeys.enabledKeys", keys: ["enabledKeys"],
            title: "操作键",
            subtitle: "",
            keywords: [
                "hotkey",
                "shortcut",
                "downscale",
                "quicklook",
                "rename",
                "恢复原件",
                "pause",
                "escape",
                "dismiss",
                "clear all",
                "bring back",
                "speed up",
                "aggressive",
                "optimise aggressively",
                "optimise clipboard",
                "stop",
                "paste",
                "keycap",
            ], tab: .keys, section: "Action keys"
        ),
        SettingEntry(
            id: "keys.resizekeys.quickResizeKeys", keys: ["quickResizeKeys"],
            title: "缩放键",
            subtitle: "",
            keywords: ["downscale", "percent", "percentage", "10%", "20%", "90%", "tens", "number row", "hotkey", "shortcut", "scale", "shrink", "smaller", "trigger", "hold", "quick"], tab: .keys, section: "Resize keys"
        ),
        SettingEntry(
            id: "floating.main.floatingResultActions", keys: ["floatingResultActions"],
            title: "操作按钮",
            subtitle: "",
            keywords: ["悬浮结果", "grid", "icons", "share", "quicklook", "customise", "reorder", "remove", "add", "toolbar", "send securely", "aggressive", "downscale"], tab: .floating, section: ""
        ),
        SettingEntry(
            id: "floating.main.compactResultActions", keys: ["compactResultActions"],
            title: "侧边操作",
            subtitle: "",
            keywords: ["compact result", "icons", "buttons", "row", "customise", "add", "remove", "quicklook", "share", "crop", "show in finder", "save as"], tab: .floating, section: ""
        ),
        SettingEntry(
            id: "images.watchpaths.dirsHideFloatingResult", keys: [],
            title: "显示悬浮结果",
            subtitle: "优化此文件夹中的文件时显示悬浮缩略图与进度",
            keywords: ["watched", "silent", "quiet", "hide", "no popup", "background", "checkbox", "column", "notification", "per directory"], tab: .images, section: "Watch paths"
        ),
        SettingEntry(
            id: "presetZones.presetzones.presetZones", keys: [],
            title: "预设区",
            subtitle: "点按预设区可指派或新建管线;把文件拖到预设区即运行其操作。",
            keywords: ["drop target", "quadrant", "corner", "control key", "image", "video", "audio", "pdf", "automation"], tab: .presetZones, section: "Preset zones"
        ),

    ]

    static let byID: [String: SettingEntry] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    /// Words a query carries and a settings row does not. Dropped rather than down-weighted, because
    /// `requireAll` is the problem: someone types "replacing the original video", the row that answers
    /// it has no "the" anywhere, and requiring the word throws the answer away and keeps whichever
    /// rows happen to have a full sentence for a subtitle.
    ///
    /// A fixed list rather than one read off the index. In 125 rows "the" looks rare enough to matter
    /// and it never does, so frequency is the wrong instrument here.
    static let stopWords: Set = [
        "an", "and", "any", "are", "as", "at", "be", "but", "by", "can", "do", "does", "for", "from",
        "get", "has", "have", "how", "if", "in", "into", "is", "it", "its", "me", "my", "no", "not",
        "of", "on", "or", "so", "some", "that", "the", "their", "them", "then", "there", "these",
        "they", "this", "to", "was", "what", "when", "where", "which", "why", "will", "with", "would",
        "you", "your",
    ]

    /// The title an anchored control is named by, for rows that write exactly one key and whose id
    /// no other row shares.
    static func accessibilityTitle(for id: String) -> String? {
        accessibilityTitles[id]
    }

    /// Split into lowercase words. Shared by the index and the query so both are cut the same way.
    static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// How well a query word matches an indexed word, 0 when it does not.
    ///
    /// Graded rather than yes/no, because the rungs have to outrank each other: typing "send" must put
    /// the row called "Send securely" above a row that merely mentions "sender" in a keyword.
    ///
    /// The prefix rung carries the field while you are still typing, and it has no minimum length on
    /// purpose. An earlier version needed four characters before it would look at a prefix at all,
    /// which meant "sen" found nothing and the field looked broken until the fourth keystroke.
    static func wordScore(_ query: String, _ indexed: String) -> Double {
        if query == indexed {
            return 1
        }
        if indexed.hasPrefix(query) {
            return 0.9
        }
        // Neither is a prefix of the other, and they can still be the same word: "replacing" and
        // "replace" part ways at the seventh letter. A strict prefix test scores that pair zero, which
        // is exactly how a question about Clop "replacing" the original missed the row whose keyword is
        // "replace". Scored by how much of the longer word the stem accounts for, so a real inflection
        // lands near a prefix hit and "compression" against "compatibility" lands nowhere.
        let stem = sharedPrefixLength(query, indexed)
        let ratio = Double(stem) / Double(max(query.count, indexed.count))
        if stem >= 4, ratio >= 0.5 {
            return 0.85 * ratio
        }
        if query.count >= 4, indexed.contains(query) {
            return 0.5
        }
        return 0
    }

    /// Is `query` a subsequence of `text`, and how tightly packed? nil when it is not in there at all.
    ///
    /// The fzf trick, and the net for typos and abbreviations: "clipbord" and "metdata" are nobody's
    /// word, and both are one dropped letter from a row that exists. Runs of adjacent letters and
    /// letters landing on a word boundary score higher, which is what keeps the loose matches off rows
    /// that merely happen to contain the letters somewhere.
    ///
    /// Four characters minimum: below that the letters of a query are scattered through most of the
    /// index and the score means nothing.
    static func subsequenceScore(_ query: String, _ text: String) -> Double? {
        guard query.count >= 4, text.count >= query.count else { return nil }
        let q = Array(query), t = Array(text)
        var score = 0, streak = 0, ti = 0

        for ch in q {
            var found = false
            while ti < t.count {
                if t[ti] == ch {
                    let atWordStart = ti == 0 || !(t[ti - 1].isLetter || t[ti - 1].isNumber)
                    streak += 1
                    score += 1 + streak * 3 + (atWordStart ? 6 : 0)
                    ti += 1
                    found = true
                    break
                }
                streak = 0
                ti += 1
            }
            guard found else { return nil }
        }

        // Against a perfect contiguous run starting at a word boundary, so a long subtitle that happens
        // to contain the letters cannot outscore a short title that spells them out.
        let perfect = q.indices.reduce(6) { $0 + 1 + ($1 + 1) * 3 }
        return min(1, Double(score) / Double(perfect))
    }

    /// The best any field of `entry` does with one query word.
    static func tokenScore(_ token: String, in entry: SettingEntry) -> Double {
        var best = 0.0
        for field in entry.searchFields {
            for word in field.words {
                let score = wordScore(token, word)
                guard score > 0 else { continue }
                best = max(best, field.weight * score)
            }
        }
        guard best == 0 else { return best }

        // Only once no whole word matched. Held below the weakest whole-word rung deliberately: a
        // subsequence hit is a guess, and it must never push a row that really carries the word down.
        for field in entry.searchTexts {
            guard let score = subsequenceScore(token, field.text) else { continue }
            best = max(best, field.weight * score * 0.4)
        }
        return best
    }

    /// Rows matching the query, best first.
    ///
    /// `requireAll` is what separates the two callers. The Settings field passes true, because someone
    /// typing two words expects both to count. An agent hands over a whole sentence full of words no
    /// row carries, so `MCPSettingsBridge.matches` passes false and leans on the scoring instead.
    static func rank(_ query: String, requireAll: Bool, limit: Int = 25) -> [SettingEntry] {
        var tokens = Array(Set(words(query).filter { $0.count > 1 && !stopWords.contains($0) }))
        // Unless the query is nothing but function words, in which case they are all there is to go on.
        if tokens.isEmpty {
            tokens = Array(Set(words(query).filter { $0.count > 1 }))
        }
        guard !tokens.isEmpty else { return [] }

        // Scored once per row and word, then reused for the weighting below. The weighting needs to
        // know how many rows each word hits, and running a fuzzy matcher over the whole index twice is
        // the expensive half of a keystroke.
        let scores = all.map { entry in tokens.map { tokenScore($0, in: entry) } }
        let hits = tokens.indices.map { t in scores.reduce(0.0) { $0 + ($1[t] > 0 ? 1 : 0) } }
        // Squared, so the one word that decides the answer dominates the ones every row carries. Plain
        // inverse document frequency damps too gently for a query that is a whole sentence: "the" is in
        // 37 rows and "mp4" is in 5, and a title match on "the" was outscoring the row that actually
        // answers the question.
        let weights = hits.map { pow(Foundation.log((Double(all.count) + 1) / ($0 + 1)) + 0.1, 2) }

        return zip(all, scores).compactMap { entry, rowScores -> (SettingEntry, Double)? in
            var total = 0.0
            var matched = 0
            for (t, score) in rowScores.enumerated() where score > 0 {
                matched += 1
                total += score * weights[t]
            }
            guard matched > 0 else { return nil }
            if requireAll, matched < tokens.count {
                return nil
            }
            return (entry, total)
        }
        .sorted { $0.1 == $1.1 ? $0.0.title < $1.0.title : $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }

    /// What the Settings search field calls: rows matching every word, best first.
    ///
    /// Falling back to the partial match keeps the field from dead-ending. Someone types a phrase with
    /// one word no row carries and the answer is still one word away, so showing the rows that match
    /// the rest beats "没有匹配项".
    static func search(_ query: String) -> [SettingEntry] {
        let strict = rank(query, requireAll: true)
        return strict.isEmpty ? rank(query, requireAll: false) : strict
    }

    private static let accessibilityTitles: [String: String] = {
        let counts = Dictionary(grouping: all, by: \.id).mapValues(\.count)
        return Dictionary(all.filter { $0.keys.count == 1 && counts[$0.id] == 1 }.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
    }()

    private static func sharedPrefixLength(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }

}
