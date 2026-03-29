import AppKit

/// 截屏工具栏视图 — 浮在屏幕底部
/// ┌───────────────────────────────────────┐
/// │  [区域] [窗口] [全屏] [长截屏]  │  [剪贴板▾] [✕]  │
/// └───────────────────────────────────────┘
final class CaptureToolbarView: NSView {
    private weak var controller: CaptureOverlayController?
    private let manager: CaptureManager
    private var modeButtons: [NSButton] = []
    private var outputButton: NSButton!

    init(frame: NSRect, controller: CaptureOverlayController, manager: CaptureManager) {
        self.controller = controller
        self.manager = manager
        super.init(frame: frame)
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // 圆角毛玻璃背景
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func setupUI() {
        let modes = CaptureMode.allCases
        let buttonWidth: CGFloat = 60
        let buttonHeight: CGFloat = 28
        let gap: CGFloat = 6
        let startX: CGFloat = 12
        let y = (bounds.height - buttonHeight) / 2

        // 模式按钮
        for (i, mode) in modes.enumerated() {
            let btn = NSButton(frame: NSRect(
                x: startX + CGFloat(i) * (buttonWidth + gap),
                y: y,
                width: buttonWidth,
                height: buttonHeight
            ))
            btn.title = mode.rawValue
            btn.bezelStyle = .recessed
            btn.setButtonType(.pushOnPushOff)
            btn.state = mode == manager.currentMode ? .on : .off
            btn.target = self
            btn.action = #selector(modeTapped(_:))
            btn.tag = i
            btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            addSubview(btn)
            modeButtons.append(btn)
        }

        // 分隔线
        let sepX = startX + CGFloat(modes.count) * (buttonWidth + gap) + 4
        let sep = NSBox(frame: NSRect(x: sepX, y: 6, width: 1, height: bounds.height - 12))
        sep.boxType = .separator
        addSubview(sep)

        // 输出方式按钮
        let outputX = sepX + 10
        outputButton = NSButton(frame: NSRect(x: outputX, y: y, width: 80, height: buttonHeight))
        let outputTitle = Preferences.shared.screenshotOutput == "clipboard" ? "剪贴板 ▾" : "文件 ▾"
        outputButton.title = outputTitle
        outputButton.bezelStyle = .recessed
        outputButton.target = self
        outputButton.action = #selector(outputTapped(_:))
        outputButton.font = NSFont.systemFont(ofSize: 12)
        addSubview(outputButton)

        // 关闭按钮
        let closeX = bounds.width - 36
        let closeBtn = NSButton(frame: NSRect(x: closeX, y: y, width: 28, height: buttonHeight))
        closeBtn.title = "✕"
        closeBtn.bezelStyle = .recessed
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        closeBtn.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        addSubview(closeBtn)
    }

    @objc private func modeTapped(_ sender: NSButton) {
        let mode = CaptureMode.allCases[sender.tag]
        manager.currentMode = mode

        // 更新按钮状态
        for (i, btn) in modeButtons.enumerated() {
            btn.state = i == sender.tag ? .on : .off
        }

        controller?.switchMode(mode)
    }

    @objc private func outputTapped(_ sender: NSButton) {
        let menu = NSMenu()
        let clipItem = NSMenuItem(title: "复制到剪贴板", action: #selector(setClipboardOutput), keyEquivalent: "")
        clipItem.target = self
        let fileItem = NSMenuItem(title: "保存到文件", action: #selector(setFileOutput), keyEquivalent: "")
        fileItem.target = self

        let current = Preferences.shared.screenshotOutput
        clipItem.state = current == "clipboard" ? .on : .off
        fileItem.state = current == "file" ? .on : .off

        menu.addItem(clipItem)
        menu.addItem(fileItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func setClipboardOutput() {
        Preferences.shared.screenshotOutput = "clipboard"
        outputButton.title = "剪贴板 ▾"
    }

    @objc private func setFileOutput() {
        Preferences.shared.screenshotOutput = "file"
        outputButton.title = "文件 ▾"
    }

    @objc private func closeTapped() {
        controller?.cancelSelection()
    }
}
