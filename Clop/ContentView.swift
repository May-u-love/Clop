//
//  ContentView.swift
//  Clop
//
//  Created by Alin Panaitiu on 16.07.2022.
//

import Defaults
import LaunchAtLogin
import Lowtech
import LowtechIndie
import LowtechPro
import SwiftUI
import System

// MARK: - MenuView

struct MenuView: View {
    @ObservedObject var um = UM
    @ObservedObject var pm = PM
    @ObservedObject var om = OM
    @ObservedObject var wdm = WDM
    @ObservedObject var lastApp = LastFocusedAppTracker.shared
    @Environment(\.openWindow) var openWindow

    @Default(.keyComboModifiers) var keyComboModifiers
    @Default(.enabledKeys) var enabledKeys
    @Default(.useAggressiveOptimisationGIF) var useAggressiveOptimisationGIF
    @Default(.useAggressiveOptimisationJPEG) var useAggressiveOptimisationJPEG
    @Default(.useAggressiveOptimisationPNG) var useAggressiveOptimisationPNG
    @Default(.videoEncoder) var videoEncoder
    @Default(.cliInstalled) var cliInstalled
    @Default(.pauseAutomaticOptimisations) var pauseAutomaticOptimisations
    @Default(.allowClopToAppearInScreenshots) var allowClopToAppearInScreenshots
    @Default(.clipboardIgnoredAppBundleIds) var clipboardIgnoredAppBundleIds

    @State var cliInstallResult: String?

    var proErrors: some View {
        Section("因免费版限制而跳过的项目") {
            ForEach(om.skippedBecauseNotPro, id: \.self) { url in
                let str = url.isFileURL ? url.filePath!.shellString : url.absoluteString
                Button("    \(str.count > 50 ? (str.prefix(25) + "..." + str.suffix(15)) : str)") {
                    QuickLooker.quicklook(url: url)
                }
            }
            Button("获取 Clop Pro") {
                manageLicenceInSettings()
            }
        }
    }

    var body: some View {
        Button("设置") {
            openWindow(id: "settings")
            focus()
        }.keyboardShortcut(",")
        Button("批量优化器") {
            BAT.presentForDropping()
        }
        LaunchAtLogin.Toggle()

        Divider()

        Section("剪贴板操作") {
            Button("优化") {
                Task { try? await optimiseLastClipboardItem() }
            }.hotkeyHint(.c, "c", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)

            if !useAggressiveOptimisationGIF ||
                !useAggressiveOptimisationJPEG ||
                !useAggressiveOptimisationPNG ||
                videoEncoder != .slowHighQuality
            {
                Button("优化(激进)") {
                    Task { try? await optimiseLastClipboardItem(aggressiveOptimisation: true) }
                }.hotkeyHint(.a, "a", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)
            }

            Button("缩小") {
                scalingFactor = max(scalingFactor > 0.5 ? scalingFactor - 0.25 : scalingFactor - 0.1, 0.1)
                Task { try? await optimiseLastClipboardItem(downscaleTo: scalingFactor) }
            }.hotkeyHint(.minus, "-", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)
            Button("Quicklook") {
                Task { try? await quickLookLastClipboardItem() }
            }.hotkeyHint(.space, " ", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)

            if let bundleID = lastApp.bundleId {
                let appName = lastApp.name ?? bundleID
                Toggle("忽略来自 \(appName) 的剪贴板事件", isOn: Binding(
                    get: { clipboardIgnoredAppBundleIds.contains(bundleID) },
                    set: { ignore in
                        if ignore {
                            clipboardIgnoredAppBundleIds.insert(bundleID)
                        } else {
                            clipboardIgnoredAppBundleIds.remove(bundleID)
                        }
                    }
                ))
            }
        }

        Section("备份") {
            Button("打开备份文件夹") {
                NSWorkspace.shared.open(FilePath.clopBackups.url)
            }
            Button("打开工作目录") {
                NSWorkspace.shared.open(FilePath.workdir.url)
            }
            Button("强制清空工作目录") {
                do {
                    for dir in [FilePath.clopBackups, .videos, .images, .pdfs, .conversions, .downloads, .forResize, .forFilters, .finderQuickAction, .processLogs] {
                        try FileManager.default.removeItem(at: dir.url)
                    }
                } catch {
                    showNotice("Failed to clean working directory\n\(error.localizedDescription)")
                }

                FilePath.workdir.mkdir(withIntermediateDirectories: true, permissions: 0o755)
                guard FilePath.workdir.exists else {
                    showNotice("创建工作目录失败")
                    return
                }

                showNotice("工作目录已清理")
            }

            Button("撤销上次优化") {
                om.clipboardImageOptimiser?.restoreOriginal()
            }
            .hotkeyHint(.z, "z", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)
            .disabled(om.clipboardImageOptimiser?.isOriginal ?? true)
            Button("找回上个结果") {
                guard let last = om.removedOptimisers.popLast() else {
                    return
                }
                om.optimisers = om.optimisers.without(last).with(last)
            }
            .hotkeyHint(.equal, "=", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)
            .disabled(om.removedOptimisers.isEmpty)
        }

        Section("自动化") {
            Toggle("暂停自动优化", isOn: $pauseAutomaticOptimisations)
                .searchAnchor("general.main.pauseAutomaticOptimisations")
            if !cliInstalled {
                Button("安装命令行集成") {
                    do {
                        try installCLIBinary()
                        cliInstallResult = "CLI installed at \(CLOP_CLI_BIN_SHELL)"
                    } catch let error as InstallCLIError {
                        cliInstallResult = error.message
                    } catch {
                        cliInstallResult = "安装失败"
                    }
                    showNotice(cliInstallResult!)
                }
            }
            if let cliInstallResult {
                Text(cliInstallResult).disabled(true)
            } else if cliInstalled {
                Text("命令行工具已安装到 \(CLOP_CLI_BIN_SHELL)").disabled(true)
            }
        }

        if wdm.hasSessions {
            Menu("正在发送文件(\(wdm.sessions.count))") {
                ForEach(wdm.sessions) { session in
                    Menu(session.fileNames) {
                        Button("复制链接") {
                            session.copyLink()
                        }
                        if session.downloadCount > 0 {
                            Text("已下载 \(session.downloadCount) 次")
                        }
                        Button("停止发送") {
                            wdm.stopSession(session)
                        }
                    }
                }
                Divider()
                Button("复制全部链接") {
                    let links = wdm.sessions.map(\.shareURL).joined(separator: "\n")
                    withGeneralPasteboard { pb in
                        pb.clearContents()
                        pb.setString(links, forType: .string)
                    }
                }
                Button("全部停止") {
                    wdm.stopAll()
                }
            }
        }

        if !proactive, !om.skippedBecauseNotPro.isEmpty {
            proErrors
        }

        Menu("关于…") {
            Button("联系开发者") {
                NSWorkspace.shared.open(contactURL())
            }
            Button("生成调试信息") {
                DebugDump.confirmAndRun()
            }
            Button("隐私政策") {
                NSWorkspace.shared.open("https://lowtechguys.com/clop/privacy".url!)
            }
            Text("许可:\(proactive ? "Pro" : "Free")")
            #if DEBUG
                Button("重置试用期") {
                    product?.resetTrial()
                }
                Button("终止试用期") {
                    product?.expireTrial()
                }
            #endif
            Text("版本:v\(Bundle.main.version)")
        }

        Button("管理许可") {
            manageLicenceInSettings()
        }

        Button(um.newVersion != nil ? "v\(um.newVersion!) 有可用更新" : "检查更新") {
            checkForUpdates()
            focus()
        }

        Toggle("截屏时显示 Clop 界面", isOn: $allowClopToAppearInScreenshots)
            .searchAnchor("general.main.allowClopToAppearInScreenshots")
        Divider()
        Button("退出") {
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }
}

func contactURL() -> URL {
    guard var urlBuilder = URLComponents(url: "https://lowtechguys.com/contact".url!, resolvingAgainstBaseURL: false) else {
        return "https://lowtechguys.com/contact".url!
    }
    urlBuilder.queryItems = [URLQueryItem(name: "userid", value: SERIAL_NUMBER_HASH), URLQueryItem(name: "app", value: "Clop")]

    if let licenseCode = product?.licenseCode {
        urlBuilder.queryItems?.append(URLQueryItem(name: "code", value: licenseCode))
    }

    if let email = product?.activationEmail {
        urlBuilder.queryItems?.append(URLQueryItem(name: "email", value: email))
    }

    return urlBuilder.url ?? "https://lowtechguys.com/contact".url!
}

extension View {
    /// Attach a menu item's keyboard-shortcut hint only when the matching global hotkey is still
    /// enabled in settings, so disabling a hotkey also drops its (now non-functional) hint from the
    /// menubar menu.
    @ViewBuilder
    func hotkeyHint(_ key: SauceKey, _ equivalent: KeyEquivalent, enabled: [SauceKey], modifiers: EventModifiers) -> some View {
        if enabled.contains(key) {
            keyboardShortcut(equivalent, modifiers: modifiers)
        } else {
            self
        }
    }
}
