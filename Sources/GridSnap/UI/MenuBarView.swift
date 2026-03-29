import SwiftUI

// MARK: - 布局图示

struct LayoutIcon: View {
    let layout: LayoutType
    var size: CGFloat = 32

    enum LayoutType {
        case grid2x2, grid2x3, grid2x4
        case oneTwo, oneThree, twoThree
        case auto
    }

    var body: some View {
        Canvas { context, cs in
            let gap: CGFloat = 1.5
            let w = cs.width, h = cs.height
            let r: CGFloat = 2

            switch layout {
            case .grid2x2:  drawGrid(context, 2, 2, cs, gap, r)
            case .grid2x3:  drawGrid(context, 2, 3, cs, gap, r)
            case .grid2x4:  drawGrid(context, 2, 4, cs, gap, r)
            case .oneTwo:
                let lw = (w - gap) * 0.5, rw = w - lw - gap, hh = (h - gap) / 2
                stroke(context, CGRect(x: 0, y: 0, width: lw, height: h), r, 0.6)
                stroke(context, CGRect(x: lw + gap, y: 0, width: rw, height: hh), r, 0.35)
                stroke(context, CGRect(x: lw + gap, y: hh + gap, width: rw, height: hh), r, 0.35)
            case .oneThree:
                let lw = (w - gap) * 0.5, rw = w - lw - gap, th = (h - 2 * gap) / 3
                stroke(context, CGRect(x: 0, y: 0, width: lw, height: h), r, 0.6)
                for i in 0..<3 { stroke(context, CGRect(x: lw + gap, y: CGFloat(i) * (th + gap), width: rw, height: th), r, 0.35) }
            case .twoThree:
                let hh = (h - gap) / 2, hw = (w - gap) / 2, tw = (w - 2 * gap) / 3
                stroke(context, CGRect(x: 0, y: 0, width: hw, height: hh), r, 0.5)
                stroke(context, CGRect(x: hw + gap, y: 0, width: hw, height: hh), r, 0.5)
                for i in 0..<3 { stroke(context, CGRect(x: CGFloat(i) * (tw + gap), y: hh + gap, width: tw, height: hh), r, 0.35) }
            case .auto:
                drawGrid(context, 2, 2, cs, gap, r)
                context.draw(Text("✦").font(.system(size: cs.width * 0.35, weight: .light)).foregroundColor(.primary.opacity(0.4)), at: CGPoint(x: w / 2, y: h / 2))
            }
        }
        .frame(width: size, height: size * 0.7)
    }

    private func drawGrid(_ ctx: GraphicsContext, _ rows: Int, _ cols: Int, _ s: CGSize, _ gap: CGFloat, _ r: CGFloat) {
        let cw = (s.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let ch = (s.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
        for row in 0..<rows { for col in 0..<cols {
            let rect = CGRect(x: CGFloat(col) * (cw + gap), y: CGFloat(row) * (ch + gap), width: cw, height: ch)
            stroke(ctx, rect, r, 0.4)
        }}
    }

    private func stroke(_ ctx: GraphicsContext, _ rect: CGRect, _ r: CGFloat, _ opacity: Double) {
        let path = Path(roundedRect: rect, cornerRadius: r)
        ctx.fill(path, with: .color(.primary.opacity(opacity * 0.15)))
        ctx.stroke(path, with: .color(.primary.opacity(opacity)), lineWidth: 0.8)
    }
}

// MARK: - 布局按钮

struct LayoutButton: View {
    let icon: LayoutIcon.LayoutType
    let label: String
    let shortcut: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                LayoutIcon(layout: icon, size: 36)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
                Text(shortcut)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.35))
            }
            .frame(width: 60, height: 60)
            .background(hovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(hovering ? 0.15 : 0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - 菜单栏面板

struct MenuBarView: View {
    @StateObject private var prefs = Preferences.shared
    @StateObject private var recorder = ScreenRecorder.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            // ── 窗口排列 ──
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("排列窗口")

                HStack(spacing: 5) {
                    LayoutButton(icon: .grid2x2, label: "2×2", shortcut: "⌃⌥1") {
                        doArrange(GridLayout(rows: 2, cols: 2))
                    }
                    LayoutButton(icon: .grid2x3, label: "2×3", shortcut: "⌃⌥2") {
                        doArrange(GridLayout(rows: 2, cols: 3))
                    }
                    LayoutButton(icon: .grid2x4, label: "2×4", shortcut: "⌃⌥3") {
                        doArrange(GridLayout(rows: 2, cols: 4))
                    }
                    LayoutButton(icon: .auto, label: "自动", shortcut: "⌃⌥G") {
                        doArrange(AutoGridLayout())
                    }
                }

                HStack(spacing: 5) {
                    LayoutButton(icon: .oneTwo, label: "1+2", shortcut: "⌃⌥4") {
                        doArrange(Layout1Plus2())
                    }
                    LayoutButton(icon: .oneThree, label: "1+3", shortcut: "⌃⌥5") {
                        doArrange(Layout1Plus3())
                    }
                    LayoutButton(icon: .twoThree, label: "2+3", shortcut: "⌃⌥6") {
                        doArrange(Layout2Plus3())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ThinDivider()

            // ── 截屏 / 录屏 ──
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("截屏 / 录屏")

                HStack(spacing: 6) {
                    ActionButton(icon: "viewfinder", label: "截屏", shortcut: "⌃⌥S") {
                        dismiss(); CaptureManager.shared.startCapture(mode: .region)
                    }
                    ActionButton(icon: "arrow.up.and.down.text.horizontal", label: "长截屏", shortcut: nil) {
                        dismiss(); CaptureManager.shared.startCapture(mode: .scroll)
                    }
                    ActionButton(
                        icon: recorder.state == .idle ? "record.circle" : "stop.circle",
                        label: recorder.state == .idle ? "录屏" : "停止",
                        shortcut: "⌃⌥R",
                        isActive: recorder.state != .idle
                    ) {
                        recorder.toggleRecording()
                    }
                }
            }
            .padding(.horizontal, 12)

            ThinDivider()

            // ── 设置 ──
            VStack(spacing: 5) {
                // 排列范围
                InlineRow("排列范围") {
                    Picker("", selection: $prefs.arrangeScope) {
                        Text("当前").tag("current")
                        Text("全部").tag("all")
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 100)
                }

                // 磁吸
                HStack {
                    Toggle(isOn: $prefs.snapEnabled) {
                        Text("磁吸吸附")
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.6))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Color(white: 0.3))
                    .onChange(of: prefs.snapEnabled) { enabled in
                        if enabled { SnapZoneManager.shared.start() }
                        else { SnapZoneManager.shared.stop() }
                    }
                }

                // 截屏输出
                InlineRow("截屏输出") {
                    Picker("", selection: $prefs.screenshotOutput) {
                        Text("剪贴板").tag("clipboard")
                        Text("文件").tag("file")
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 100)
                }

                if prefs.screenshotOutput == "file" {
                    Button { selectSavePath() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                                .foregroundColor(.primary.opacity(0.4))
                            Text(shortenPath(prefs.screenshotSavePath))
                                .font(.system(size: 10))
                                .foregroundColor(.primary.opacity(0.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("更改")
                                .font(.system(size: 10))
                                .foregroundColor(.primary.opacity(0.4))
                        }
                        .padding(5)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }

                // 图片格式
                InlineRow("图片格式") {
                    Picker("", selection: $prefs.screenshotFormat) {
                        Text("JPEG").tag("jpeg")
                        Text("PNG").tag("png")
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 100)
                }

                // JPEG 质量
                if prefs.screenshotFormat == "jpeg" {
                    HStack(spacing: 6) {
                        Text("压缩质量")
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.6))
                        Slider(value: $prefs.screenshotQuality, in: 0.3...1.0, step: 0.05)
                            .controlSize(.small)
                            .tint(Color(white: 0.35))
                            .frame(maxWidth: 100)
                        Text("\(Int(prefs.screenshotQuality * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.4))
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 12)
            .tint(Color(white: 0.25))

            ThinDivider()

            // ── 退出 ──
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("退出 GridSnap")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
        }
        .frame(width: 272)
    }

    // MARK: - Helpers

    private func doArrange(_ layout: LayoutStrategy) {
        gsLog("[GridSnap] doArrange 被调用: \(layout.name)")
        let scope = prefs.arrangeScope
        let screen = DisplayManager.shared.currentScreen
        dismiss()
        // 延迟执行 — 确保面板关闭后再移动窗口，避免 dismiss 干扰
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            gsLog("[GridSnap] 开始排列: scope=\(scope) screen=\(screen.localizedName)")
            if scope == "all" {
                WindowManager.shared.arrangeAllScreens(using: layout)
            } else {
                WindowManager.shared.arrangeWindows(using: layout, on: screen)
            }
        }
    }

    private func selectSavePath() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = "选择截屏/录屏保存路径"
            panel.directoryURL = URL(fileURLWithPath: prefs.screenshotSavePath)
            if panel.runModal() == .OK, let url = panel.url {
                prefs.screenshotSavePath = url.path
            }
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - 通用极简组件

struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.primary.opacity(0.35))
            .textCase(.uppercase)
    }
}

struct InlineRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.6))
            Spacer()
            content
        }
    }
}

struct ThinDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let shortcut: String?
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(isActive ? .primary : .primary.opacity(0.6))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
                if let sc = shortcut {
                    Text(sc)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.3))
                }
            }
            .frame(width: 72, height: 52)
            .background(hovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(hovering ? 0.15 : 0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
