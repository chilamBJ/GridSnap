import AppKit

/// 截屏遮罩窗口控制器 — 全屏透明窗口，智能截屏模式
/// hover 高亮窗口 → 点击截窗口 → 拖拽截区域 → Esc 取消
final class CaptureOverlayController: NSWindowController {
    let screen: NSScreen
    private let manager: CaptureManager
    private var overlayView: CaptureOverlayView!
    private var toolbarWindow: NSWindow?

    init(screen: NSScreen, manager: CaptureManager) {
        self.screen = screen
        self.manager = manager

        // 创建全屏透明窗口 — 用 .zero 初始化，稍后 setFrame
        let window = KeyableWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true

        // 显式设置 frame 到目标屏幕的精确位置和大小
        window.setFrame(screen.frame, display: true)

        super.init(window: window)

        // view frame 使用相对坐标 (0,0, screenW, screenH)
        let viewFrame = NSRect(origin: .zero, size: screen.frame.size)
        overlayView = CaptureOverlayView(frame: viewFrame, screen: screen, manager: manager, controller: self)
        window.contentView = overlayView

        showToolbar()

    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    override func close() {
        NSCursor.pop()
        toolbarWindow?.close()
        toolbarWindow = nil
        super.close()
    }

    func finishSelection(_ rect: CGRect) {
        manager.finishCapture(region: rect, on: screen)
    }

    func cancelSelection() {
        manager.cancelCapture()
    }

    func switchMode(_ mode: CaptureMode) {
        manager.currentMode = mode
        overlayView.needsDisplay = true
    }

    // MARK: - 简化工具栏

    private func showToolbar() {
        let toolbarHeight: CGFloat = 36
        let toolbarWidth: CGFloat = 260
        let toolbarX = screen.frame.midX - toolbarWidth / 2
        let toolbarY = screen.frame.origin.y + 50

        let toolbarRect = NSRect(x: toolbarX, y: toolbarY, width: toolbarWidth, height: toolbarHeight)

        let tbWindow = NSWindow(
            contentRect: toolbarRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        tbWindow.level = .screenSaver + 1
        tbWindow.isOpaque = false
        tbWindow.backgroundColor = .clear
        tbWindow.hasShadow = true
        tbWindow.isReleasedWhenClosed = false

        let toolbarView = SmartCaptureToolbarView(
            frame: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight),
            controller: self, manager: manager
        )
        tbWindow.contentView = toolbarView
        tbWindow.orderFront(nil)
        self.toolbarWindow = tbWindow
    }
}

// MARK: - 简化工具栏视图

final class SmartCaptureToolbarView: NSView {
    private weak var controller: CaptureOverlayController?
    private let manager: CaptureManager

    init(frame: NSRect, controller: CaptureOverlayController, manager: CaptureManager) {
        self.controller = controller
        self.manager = manager
        super.init(frame: frame)
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func setupUI() {
        let y = (bounds.height - 20) / 2

        let hint = NSTextField(labelWithString: "点击截窗口 · 拖拽截区域 · Esc 取消")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.sizeToFit()
        hint.frame.origin = NSPoint(x: 10, y: y)
        addSubview(hint)

        let closeBtn = NSButton(frame: NSRect(x: bounds.width - 30, y: y, width: 22, height: 22))
        closeBtn.bezelStyle = .circular
        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        addSubview(closeBtn)
    }

    @objc private func closeTapped() { controller?.cancelSelection() }
}

// MARK: - 智能截屏遮罩视图

final class CaptureOverlayView: NSView {
    private let manager: CaptureManager
    private weak var controller: CaptureOverlayController?
    private let screen: NSScreen

    private var dragStart: NSPoint?
    private var dragEnd: NSPoint?
    private var isDragging = false
    private var highlightedWindowFrame: CGRect?
    private var windowFramesLocal: [CGRect] = []

    init(frame: NSRect, screen: NSScreen, manager: CaptureManager, controller: CaptureOverlayController) {
        self.manager = manager
        self.controller = controller
        self.screen = screen
        super.init(frame: frame)

        cacheWindowFrames()
        setupTracking()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - 缓存窗口 frame

    private func cacheWindowFrames() {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        // CG 坐标系: 原点在主屏左上角
        // NS 坐标系: 原点在主屏左下角
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let scrOrigin = screen.frame.origin
        let scrSize = screen.frame.size

        for info in windowList {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }

            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            let w = boundsDict["Width"] ?? 0
            let h = boundsDict["Height"] ?? 0

            guard w > 50 && h > 50 else { continue }

            // CG (left-top origin) → NS global (left-bottom origin)
            let nsX = cgX
            let nsY = primaryH - cgY - h

            // NS global → view local (相对于此 screen 的左下角)
            let localX = nsX - scrOrigin.x
            let localY = nsY - scrOrigin.y

            let localFrame = CGRect(x: localX, y: localY, width: w, height: h)

            // 只保留与本屏有交集的窗口
            let screenLocalBounds = CGRect(origin: .zero, size: scrSize)
            if localFrame.intersects(screenLocalBounds) {
                windowFramesLocal.append(localFrame)
            }
        }

    }

    // MARK: - 鼠标跟踪

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)

        var bestFrame: CGRect?
        var bestArea: CGFloat = .infinity
        for wf in windowFramesLocal {
            if wf.contains(point) {
                let area = wf.width * wf.height
                if area < bestArea {
                    bestArea = area
                    bestFrame = wf
                }
            }
        }

        highlightedWindowFrame = bestFrame
        needsDisplay = true
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 半透明遮罩覆盖整个 view
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        if isDragging, let start = dragStart, let end = dragEnd {
            let selection = rectFrom(start, end)
            if selection.width > 2 && selection.height > 2 {
                // 挖空选区
                NSColor.clear.setFill()
                selection.fill(using: .copy)

                NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
                let path = NSBezierPath(rect: selection)
                path.lineWidth = 2
                path.stroke()
                drawSizeLabel(for: selection)
            }
        } else if let wf = highlightedWindowFrame {
            // 挖空窗口高亮区域
            NSColor.clear.setFill()
            wf.fill(using: .copy)

            NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
            let path = NSBezierPath(roundedRect: wf.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4)
            path.lineWidth = 2.5
            path.stroke()
            drawSizeLabel(for: wf)
        }
    }

    private static let sizeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)

    private func drawSizeLabel(for rect: NSRect) {
        guard rect.width > 0, rect.height > 0,
              !rect.width.isNaN, !rect.height.isNaN
        else { return }

        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let font = Self.sizeFont
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let attrStr = NSAttributedString(string: " \(text) ", attributes: attrs)
        let labelSize = attrStr.size()

        guard labelSize.width > 0, labelSize.height > 0 else { return }

        let bgRect = NSRect(
            x: rect.midX - labelSize.width / 2 - 4,
            y: max(rect.origin.y - labelSize.height - 8, 4),
            width: labelSize.width + 8,
            height: labelSize.height + 4
        )
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        bgPath.fill()
        attrStr.draw(at: NSPoint(x: bgRect.origin.x + 4, y: bgRect.origin.y + 2))
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragEnd = point
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        dragEnd = current
        if hypot(current.x - start.x, current.y - start.y) > 5 {
            isDragging = true
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging, let start = dragStart, let end = dragEnd {
            let selection = rectFrom(start, end)
            if selection.width > 5 && selection.height > 5 {
                controller?.finishSelection(selection)
                return
            }
        } else if let wf = highlightedWindowFrame {
            controller?.finishSelection(wf)
            return
        }

        isDragging = false
        dragStart = nil
        dragEnd = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller?.cancelSelection() }
    }

    private func rectFrom(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

// MARK: - Borderless 但可接收键盘事件的窗口

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
