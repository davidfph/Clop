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
    @Environment(\.openWindow) var openWindow

    @Default(.keyComboModifiers) var keyComboModifiers
    @Default(.useAggressiveOptimisationGIF) var useAggressiveOptimisationGIF
    @Default(.useAggressiveOptimisationJPEG) var useAggressiveOptimisationJPEG
    @Default(.useAggressiveOptimisationPNG) var useAggressiveOptimisationPNG
    @Default(.useAggressiveOptimisationMP4) var useAggressiveOptimisationMP4
    @Default(.cliInstalled) var cliInstalled
    @Default(.pauseAutomaticOptimisations) var pauseAutomaticOptimisations
    @Default(.allowClopToAppearInScreenshots) var allowClopToAppearInScreenshots

    @State var cliInstallResult: String?

    @ViewBuilder var proErrors: some View {
        Section("因免费版限制而跳过的项目") {
            ForEach(om.skippedBecauseNotPro, id: \.self) { url in
                let str = url.isFileURL ? url.filePath!.shellString : url.absoluteString
                Button("    \(str.count > 50 ? (str.prefix(25) + "..." + str.suffix(15)) : str)") {
                    QuickLooker.quicklook(url: url)
                }
            }
            Button("获取 Clop Pro") {
                settingsViewManager.tab = .about
                openWindow(id: "settings")

                PRO?.manageLicence()
                focus()
                NSApp.windows.first(where: { $0.title == "Settings" })?.makeKeyAndOrderFront(nil)
            }
        }
    }

    var body: some View {
        Button("设置") {
            openWindow(id: "settings")
            focus()
        }.keyboardShortcut(",")
        LaunchAtLogin.Toggle()

        Divider()

        Section("剪贴板操作") {
            Button("优化") {
                Task.init { try? await optimiseLastClipboardItem() }
            }.keyboardShortcut("c", modifiers: keyComboModifiers.eventModifiers)

            if !useAggressiveOptimisationGIF ||
                !useAggressiveOptimisationJPEG ||
                !useAggressiveOptimisationPNG ||
                !useAggressiveOptimisationMP4
            {
                Button("优化（激进）") {
                    Task.init { try? await optimiseLastClipboardItem(aggressiveOptimisation: true) }
                }.keyboardShortcut("a", modifiers: keyComboModifiers.eventModifiers)
            }

            Button("缩小") {
                scalingFactor = max(scalingFactor > 0.5 ? scalingFactor - 0.25 : scalingFactor - 0.1, 0.1)
                Task.init { try? await optimiseLastClipboardItem(downscaleTo: scalingFactor) }
            }.keyboardShortcut("-", modifiers: keyComboModifiers.eventModifiers)
            Button("快速预览") {
                Task.init { try? await quickLookLastClipboardItem() }
            }.keyboardShortcut(" ", modifiers: keyComboModifiers.eventModifiers)

        }

        Section("备份") {
            Button("打开备份文件夹") {
                NSWorkspace.shared.open(FilePath.clopBackups.url)
            }
            Button("打开工作目录") {
                NSWorkspace.shared.open(FilePath.workdir.url)
            }
            Button("强制清理工作目录") {
                do {
                    for dir in [FilePath.clopBackups, .videos, .images, .pdfs, .conversions, .downloads, .forResize, .forFilters, .finderQuickAction, .processLogs] {
                        try FileManager.default.removeItem(at: dir.url)
                    }
                } catch {
                    showNotice("清理工作目录失败\n\(error.localizedDescription)")
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
            .keyboardShortcut("z", modifiers: keyComboModifiers.eventModifiers)
            .disabled(om.clipboardImageOptimiser?.isOriginal ?? true)
            Button("恢复上次结果") {
                guard let last = om.removedOptimisers.popLast() else {
                    return
                }
                om.optimisers = om.optimisers.without(last).with(last)
            }
            .keyboardShortcut("=", modifiers: keyComboModifiers.eventModifiers)
            .disabled(om.removedOptimisers.isEmpty)
        }

        Section("自动化") {
            Toggle("暂停自动优化", isOn: $pauseAutomaticOptimisations)
            if !cliInstalled {
                Button("安装命令行集成") {
                    do {
                        try installCLIBinary()
                        cliInstallResult = "CLI 已安装在 \(CLOP_CLI_BIN_SHELL)"
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
                Text("CLI 已安装在 \(CLOP_CLI_BIN_SHELL)").disabled(true)
            }
        }

        if !proactive, !om.skippedBecauseNotPro.isEmpty {
            proErrors
        }

        Menu("关于...") {
            Button("联系开发者") {
                NSWorkspace.shared.open(contactURL())
            }
            Button("隐私政策") {
                NSWorkspace.shared.open("https://lowtechguys.com/clop/privacy".url!)
            }
            Text("许可证：\(proactive ? "Pro" : "免费")")
            #if DEBUG
                Button("重置试用") {
                    product?.resetTrial()
                }
                Button("过期试用") {
                    product?.expireTrial()
                }
            #endif
            Text("版本：v\(Bundle.main.version)")
        }

        Button("管理许可证") {
            settingsViewManager.tab = .about
            openWindow(id: "settings")

            PRO?.manageLicence()
            focus()
            NSApp.windows.first(where: { $0.title == "Settings" })?.makeKeyAndOrderFront(nil)
        }

        Button(um.newVersion != nil ? "v\(um.newVersion!) 更新可用" : "检查更新") {
            checkForUpdates()
            focus()
        }

        Toggle("在截图中显示 Clop 界面", isOn: $allowClopToAppearInScreenshots)
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
