import SwiftUI

// MARK: - 统一设计常量

private enum DS {
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let labelFont = Font.system(size: 13, weight: .medium)
    static let monoFont = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let captionFont = Font.system(size: 11, weight: .regular)
    static let fg = Color.primary
    static let fgSec = Color.primary.opacity(0.5)
    static let border = Color.primary.opacity(0.12)
    static let bgSec = Color.primary.opacity(0.04)
}

// MARK: - 主视图

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            HotkeyTab()
                .tabItem { Label("快捷键", systemImage: "command") }
            ScreenshotTab()
                .tabItem { Label("截屏", systemImage: "viewfinder") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 460)
    }
}

// MARK: - 通用

struct GeneralTab: View {
    @StateObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                Toggle("开机自启动", isOn: $prefs.launchAtLogin)
                    .font(DS.bodyFont)
            } header: {
                SettingsSectionHeader("启动")
            }

            Section {
                SettingsRow("排列范围") {
                    Picker("", selection: $prefs.arrangeScope) {
                        Text("当前屏幕").tag("current")
                        Text("所有屏幕").tag("all")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                SettingsRow("动画模式") {
                    Picker("", selection: $prefs.animationMode) {
                        Text("瞬时").tag("instant")
                        Text("平滑").tag("smooth")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                if prefs.animationMode == "smooth" {
                    SettingsRow("动画时长") {
                        Slider(value: $prefs.animationDuration, in: 0.1...1.0, step: 0.05)
                            .frame(maxWidth: 140)
                        Text(String(format: "%.2fs", prefs.animationDuration))
                            .font(DS.monoFont)
                            .foregroundColor(DS.fgSec)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                SettingsSectionHeader("窗口排列")
            }

            Section {
                Toggle("启用磁吸吸附", isOn: $prefs.snapEnabled)
                    .font(DS.bodyFont)
                    .onChange(of: prefs.snapEnabled) { enabled in
                        if enabled { SnapZoneManager.shared.start() }
                        else { SnapZoneManager.shared.stop() }
                    }

                if prefs.snapEnabled {
                    SettingsRow("灵敏度") {
                        Slider(value: Binding(
                            get: { Double(prefs.snapSensitivity) },
                            set: { prefs.snapSensitivity = Int($0) }
                        ), in: 4...30, step: 2)
                        .frame(maxWidth: 140)
                        Text("\(prefs.snapSensitivity)px")
                            .font(DS.monoFont)
                            .foregroundColor(DS.fgSec)
                            .frame(width: 44, alignment: .trailing)
                    }

                    SettingsRow("吸附区域") {
                        SnapZonePreview()
                    }
                }
            } header: {
                SettingsSectionHeader("磁吸")
            }
        }
        .padding()
    }
}

// MARK: - 磁吸预览

struct SnapZonePreview: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let gap: CGFloat = 1.5
            let halfW = (w - gap) / 2
            let halfH = (h - gap) / 2

            let zones = [
                CGRect(x: 0, y: 0, width: halfW, height: halfH),
                CGRect(x: halfW + gap, y: 0, width: halfW, height: halfH),
                CGRect(x: 0, y: halfH + gap, width: halfW, height: halfH),
                CGRect(x: halfW + gap, y: halfH + gap, width: halfW, height: halfH),
            ]
            for rect in zones {
                context.fill(Path(rect), with: .color(.primary.opacity(0.06)))
                context.stroke(Path(rect), with: .color(.primary.opacity(0.2)), lineWidth: 0.5)
            }
        }
        .frame(width: 56, height: 36)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

// MARK: - 快捷键

struct HotkeyTab: View {
    var body: some View {
        Form {
            Section {
                HotkeyRow("2×2 网格", shortcut: "⌃⌥1")
                HotkeyRow("2×3 网格", shortcut: "⌃⌥2")
                HotkeyRow("2×4 网格", shortcut: "⌃⌥3")
                HotkeyRow("1+2 布局", shortcut: "⌃⌥4")
                HotkeyRow("1+3 布局", shortcut: "⌃⌥5")
                HotkeyRow("2+3 布局", shortcut: "⌃⌥6")
                HotkeyRow("自动最佳", shortcut: "⌃⌥G")
            } header: {
                SettingsSectionHeader("窗口排列")
            }

            Section {
                HotkeyRow("区域截屏", shortcut: "⌃⌥S")
                HotkeyRow("录屏", shortcut: "⌃⌥R")
            } header: {
                SettingsSectionHeader("截屏 / 录屏")
            }
        }
        .padding()
    }
}

struct HotkeyRow: View {
    let label: String
    let shortcut: String

    init(_ label: String, shortcut: String) {
        self.label = label
        self.shortcut = shortcut
    }

    var body: some View {
        HStack {
            Text(label)
                .font(DS.bodyFont)
            Spacer()
            Text(shortcut)
                .font(DS.monoFont)
                .foregroundColor(DS.fgSec)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.bgSec)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.border, lineWidth: 0.5))
        }
    }
}

// MARK: - 截屏设置

struct ScreenshotTab: View {
    @StateObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                SettingsRow("默认输出") {
                    Picker("", selection: $prefs.screenshotOutput) {
                        Text("剪贴板").tag("clipboard")
                        Text("保存文件").tag("file")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            } header: {
                SettingsSectionHeader("输出")
            }

            if prefs.screenshotOutput == "file" {
                Section {
                    HStack(spacing: 8) {
                        Text(shortenPath(prefs.screenshotSavePath))
                            .font(DS.bodyFont)
                            .foregroundColor(DS.fgSec)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("更改…") { selectSavePath() }
                            .font(DS.bodyFont)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } header: {
                    SettingsSectionHeader("保存路径")
                }
            }

            Section {
                SettingsRow("格式") {
                    Picker("", selection: $prefs.screenshotFormat) {
                        Text("JPEG").tag("jpeg")
                        Text("PNG").tag("png")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                if prefs.screenshotFormat == "jpeg" {
                    SettingsRow("压缩质量") {
                        Slider(value: $prefs.screenshotQuality, in: 0.3...1.0, step: 0.05)
                            .frame(maxWidth: 140)
                        Text("\(Int(prefs.screenshotQuality * 100))%")
                            .font(DS.monoFont)
                            .foregroundColor(DS.fgSec)
                            .frame(width: 36, alignment: .trailing)
                    }

                    HStack {
                        Text("体积小")
                            .font(DS.captionFont)
                            .foregroundColor(DS.fgSec)
                        Spacer()
                        Text("画质高")
                            .font(DS.captionFont)
                            .foregroundColor(DS.fgSec)
                    }
                    .padding(.leading, 90)
                    .padding(.trailing, 40)
                }
            } header: {
                SettingsSectionHeader("图片")
            }
        }
        .padding()
    }

    private func selectSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择截屏文件保存位置"
        panel.directoryURL = URL(fileURLWithPath: prefs.screenshotSavePath)
        if panel.runModal() == .OK, let url = panel.url {
            prefs.screenshotSavePath = url.path
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - 关于

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            // 极简 logo: 纯线框网格
            Canvas { context, size in
                let s = size.width
                let inset: CGFloat = 6
                let gap: CGFloat = 4
                let cellW = (s - 2 * inset - gap) / 2
                let cellH = (s - 2 * inset - gap) / 2
                let rects = [
                    CGRect(x: inset, y: inset, width: cellW, height: cellH),
                    CGRect(x: inset + cellW + gap, y: inset, width: cellW, height: cellH),
                    CGRect(x: inset, y: inset + cellH + gap, width: cellW, height: cellH),
                    CGRect(x: inset + cellW + gap, y: inset + cellH + gap, width: cellW, height: cellH),
                ]
                for rect in rects {
                    let path = Path(roundedRect: rect, cornerRadius: 3)
                    context.stroke(path, with: .color(.primary.opacity(0.7)), lineWidth: 1.5)
                }
            }
            .frame(width: 56, height: 56)

            Text("GridSnap")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DS.fg)

            Text("v1.0.0")
                .font(DS.captionFont)
                .foregroundColor(DS.fgSec)

            Text("窗口管理 · 截屏标注 · 磁吸吸附 · 录屏")
                .font(DS.captionFont)
                .foregroundColor(DS.fgSec)

            Rectangle()
                .fill(DS.border)
                .frame(width: 180, height: 0.5)
                .padding(.vertical, 4)

            HStack(spacing: 20) {
                LinkButton("GitHub", url: "https://github.com/gridsnap/gridsnap")
                LinkButton("反馈", url: "https://github.com/gridsnap/gridsnap/issues")
            }

            Text("© 2026 GridSnap")
                .font(.system(size: 10))
                .foregroundColor(DS.fgSec)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 通用组件

struct SettingsSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(DS.fgSec)
            .textCase(.none)
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(DS.bodyFont)
                .frame(width: 80, alignment: .leading)
            Spacer()
            content
        }
    }
}

struct LinkButton: View {
    let title: String
    let url: String

    init(_ title: String, url: String) {
        self.title = title
        self.url = url
    }

    var body: some View {
        Button(title) {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
        .font(DS.captionFont)
        .foregroundColor(DS.fgSec)
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}
