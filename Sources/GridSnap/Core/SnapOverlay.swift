import AppKit

/// 磁吸吸附预览高亮窗口 — 半透明区域预览
final class SnapOverlayWindow {
    private var window: NSWindow?

    /// isSwap: true=互换(橙色), false=填充空位(蓝色)
    init(frame: CGRect, on screen: NSScreen, isSwap: Bool = false) {
        let win = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.setFrame(frame, display: false)
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false

        let contentView = SnapPreviewView(frame: NSRect(origin: .zero, size: frame.size), isSwap: isSwap)
        win.contentView = contentView

        self.window = win
    }

    func show() {
        window?.orderFront(nil)

        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window?.animator().alphaValue = 1.0
        }
    }

    func dismiss() {
        let win = window
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            win?.animator().alphaValue = 0
        }, completionHandler: {
            win?.close()
        })
        window = nil
    }
}

// MARK: - 预览视图

final class SnapPreviewView: NSView {
    private let isSwap: Bool

    init(frame: NSRect, isSwap: Bool) {
        self.isSwap = isSwap
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 4, dy: 4)
        let color: NSColor = isSwap ? .systemOrange : .systemBlue

        // 半透明填充
        color.withAlphaComponent(0.15).setFill()
        let fill = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        fill.fill()

        // 边框
        color.withAlphaComponent(0.6).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        border.lineWidth = 2.5
        border.stroke()

        // 互换模式显示双箭头图标
        if isSwap {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: min(bounds.width, bounds.height) * 0.15, weight: .bold),
                .foregroundColor: color.withAlphaComponent(0.5)
            ]
            let text = "⇄"
            let size = text.size(withAttributes: attrs)
            let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            text.draw(at: origin, withAttributes: attrs)
        }
    }
}
