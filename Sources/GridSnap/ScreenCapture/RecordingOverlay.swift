import AppKit

/// 录屏浮动控制面板 — 显示录制状态和控制按钮
final class RecordingOverlayController: NSWindowController {
    private let recorder: ScreenRecorder
    private var elapsedLabel: NSTextField!
    private var updateTimer: Timer?

    init(recorder: ScreenRecorder) {
        self.recorder = recorder

        let width: CGFloat = 220
        let height: CGFloat = 44

        // 屏幕顶部居中
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - 80

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let contentView = RecordingControlView(
            frame: NSRect(x: 0, y: 0, width: width, height: height),
            controller: self
        )
        window.contentView = contentView
        self.elapsedLabel = contentView.elapsedLabel

        // 定时更新时间
        startUpdating()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.orderFront(nil)
    }

    override func close() {
        updateTimer?.invalidate()
        updateTimer = nil
        super.close()
    }

    func stopRecording() {
        recorder.stopRecording()
    }

    private func startUpdating() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let elapsed = self.recorder.elapsed
            let mins = Int(elapsed) / 60
            let secs = Int(elapsed) % 60
            self.elapsedLabel?.stringValue = String(format: "%02d:%02d", mins, secs)
        }
    }
}

// MARK: - 控制面板视图

final class RecordingControlView: NSView {
    weak var controller: RecordingOverlayController?
    var elapsedLabel: NSTextField!

    init(frame: NSRect, controller: RecordingOverlayController) {
        self.controller = controller
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // 深色半透明圆角背景
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let bg = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.75).setFill()
        bg.fill()
    }

    private func setupUI() {
        // 红色录制指示器圆点
        let dot = NSView(frame: NSRect(x: 14, y: 15, width: 14, height: 14))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 7

        // 脉冲动画
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.8
        pulse.repeatCount = .infinity
        pulse.autoreverses = true
        dot.layer?.add(pulse, forKey: "pulse")
        addSubview(dot)

        // 时间标签
        elapsedLabel = NSTextField(labelWithString: "00:00")
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        elapsedLabel.textColor = .white
        elapsedLabel.frame = NSRect(x: 36, y: 10, width: 70, height: 24)
        addSubview(elapsedLabel)

        // 停止按钮
        let stopBtn = NSButton(frame: NSRect(x: 130, y: 7, width: 76, height: 30))
        stopBtn.title = "停止"
        stopBtn.bezelStyle = .rounded
        stopBtn.contentTintColor = .systemRed
        stopBtn.target = self
        stopBtn.action = #selector(stopClicked)
        addSubview(stopBtn)
    }

    @objc private func stopClicked() {
        controller?.stopRecording()
    }
}
