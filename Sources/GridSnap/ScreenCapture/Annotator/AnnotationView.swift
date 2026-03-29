import AppKit

/// 标注工具类型
enum AnnotationToolType: String, CaseIterable {
    case arrow  = "箭头"
    case rect   = "矩形"
    case text   = "文字"
    case mosaic = "马赛克"
}

/// 单个标注元素
protocol AnnotationElement {
    var toolType: AnnotationToolType { get }
    var color: NSColor { get set }
    var lineWidth: CGFloat { get set }
    func draw(in context: CGContext)
    func contains(point: CGPoint) -> Bool
}

/// 标注编辑窗口
final class AnnotationWindowController: NSWindowController {
    private let sourceImage: NSImage
    private let onFinish: (NSImage) -> Void
    private let onAbandon: () -> Void
    private var annotationView: AnnotationCanvasView!

    /// - Parameters:
    ///   - image: 截屏原图
    ///   - onFinish: 用户点击完成时回调(带标注的最终图片)
    ///   - onAbandon: 用户点击放弃时回调(不保存不复制)
    init(image: NSImage,
         onFinish: @escaping (NSImage) -> Void,
         onAbandon: @escaping () -> Void = {}) {
        self.sourceImage = image
        self.onFinish = onFinish
        self.onAbandon = onAbandon

        let imageSize = image.size
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        // 窗口大小适配屏幕
        let scale = min(
            screenFrame.width * 0.8 / imageSize.width,
            screenFrame.height * 0.8 / imageSize.height,
            1.0
        )
        let windowSize = NSSize(
            width: max(imageSize.width * scale + 60, 560),
            height: max(imageSize.height * scale + 80, 300)
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 560, height: 300)
        window.title = "标注编辑"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI(imageSize: imageSize, scale: scale)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(imageSize: NSSize, scale: CGFloat) {
        guard let contentView = window?.contentView else { return }

        // 工具栏
        let toolbar = AnnotationToolbarView(
            frame: NSRect(x: 0, y: contentView.bounds.height - 40, width: contentView.bounds.width, height: 40)
        )
        toolbar.autoresizingMask = [.width, .minYMargin]
        toolbar.onToolSelected = { [weak self] tool in
            self?.annotationView.currentTool = tool
        }
        toolbar.onColorSelected = { [weak self] color in
            self?.annotationView.currentColor = color
        }
        toolbar.onUndo = { [weak self] in
            self?.annotationView.undo()
        }
        toolbar.onDone = { [weak self] in
            self?.finishAnnotation()
        }
        toolbar.onCancel = { [weak self] in
            self?.abandonAnnotation()
        }
        contentView.addSubview(toolbar)

        // 画布 (scrollview 包裹)
        let canvasFrame = NSRect(
            x: 0, y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - 40
        )
        let scrollView = NSScrollView(frame: canvasFrame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        annotationView = AnnotationCanvasView(
            frame: NSRect(origin: .zero, size: imageSize),
            image: sourceImage
        )
        scrollView.documentView = annotationView
        contentView.addSubview(scrollView)
    }

    /// 完成 - 保存标注后的图片
    private func finishAnnotation() {
        let result = annotationView.renderFinalImage()
        onFinish(result)
        close()
    }

    /// 放弃 - 丢弃整个截屏，不保存、不复制
    private func abandonAnnotation() {
        onAbandon()
        close()
    }
}

// MARK: - 标注画布

final class AnnotationCanvasView: NSView {
    private let image: NSImage
    var currentTool: AnnotationToolType = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 2.0

    private var elements: [AnnotationElement] = []
    private var currentElement: AnnotationElement?
    private var dragStart: NSPoint?

    /// Undo: 是否还能撤销
    var canUndo: Bool { !elements.isEmpty }

    init(frame: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Undo

    func undo() {
        guard !elements.isEmpty else { return }
        elements.removeLast()
        needsDisplay = true
    }

    // MARK: - Cmd+Z 快捷键

    override func keyDown(with event: NSEvent) {
        // Cmd+Z -> undo
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undo()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 底图
        image.draw(in: bounds)

        // 已有标注
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for element in elements {
            element.draw(in: ctx)
        }
        currentElement?.draw(in: ctx)
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)  // 确保接收键盘事件
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point

        switch currentTool {
        case .arrow:
            currentElement = ArrowElement(start: point, end: point, color: currentColor, lineWidth: currentLineWidth)
        case .rect:
            currentElement = RectElement(origin: point, size: .zero, color: currentColor, lineWidth: currentLineWidth)
        case .text:
            // 文字工具在 mouseUp 时弹输入框
            break
        case .mosaic:
            currentElement = MosaicElement(rect: NSRect(origin: point, size: .zero), sourceImage: image)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .arrow:
            if var arrow = currentElement as? ArrowElement {
                arrow.end = current
                currentElement = arrow
            }
        case .rect:
            if var rect = currentElement as? RectElement {
                let x = min(start.x, current.x)
                let y = min(start.y, current.y)
                rect.origin = NSPoint(x: x, y: y)
                rect.size = NSSize(width: abs(current.x - start.x), height: abs(current.y - start.y))
                currentElement = rect
            }
        case .text:
            break
        case .mosaic:
            if var mosaic = currentElement as? MosaicElement {
                let x = min(start.x, current.x)
                let y = min(start.y, current.y)
                mosaic.rect = NSRect(x: x, y: y, width: abs(current.x - start.x), height: abs(current.y - start.y))
                currentElement = mosaic
            }
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if currentTool == .text {
            let point = convert(event.locationInWindow, from: nil)
            promptForText(at: point)
            return
        }

        if let element = currentElement {
            elements.append(element)
            currentElement = nil
            needsDisplay = true
        }
        dragStart = nil
    }

    private func promptForText(at point: NSPoint) {
        let alert = NSAlert()
        alert.messageText = "输入文字"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = textField
        if alert.runModal() == .alertFirstButtonReturn, !textField.stringValue.isEmpty {
            let textElement = TextElement(
                position: point,
                text: textField.stringValue,
                color: currentColor,
                fontSize: 16
            )
            elements.append(textElement)
            needsDisplay = true
        }
    }

    /// 合成最终图像
    func renderFinalImage() -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: size))

        if let ctx = NSGraphicsContext.current?.cgContext {
            for element in elements {
                element.draw(in: ctx)
            }
        }

        result.unlockFocus()
        return result
    }
}

// MARK: - 标注工具栏

final class AnnotationToolbarView: NSView {
    var onToolSelected: ((AnnotationToolType) -> Void)?
    var onColorSelected: ((NSColor) -> Void)?
    var onUndo: (() -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    private var toolButtons: [NSButton] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath.strokeLine(from: NSPoint(x: 0, y: 0), to: NSPoint(x: bounds.width, y: 0))
    }

    private func setupUI() {
        var x: CGFloat = 8
        let y: CGFloat = 6
        let h: CGFloat = 28

        // SF Symbol 映射
        let icons = ["arrow.up.right", "rectangle", "textformat", "mosaic"]

        // 工具按钮
        for (i, tool) in AnnotationToolType.allCases.enumerated() {
            let btn = NSButton(frame: NSRect(x: x, y: y, width: 56, height: h))
            btn.title = tool.rawValue
            btn.bezelStyle = .rounded
            btn.setButtonType(.pushOnPushOff)
            btn.state = (i == 0) ? .on : .off  // 默认选中箭头
            btn.tag = i
            btn.target = self
            btn.action = #selector(toolTapped(_:))
            btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            if let img = NSImage(systemSymbolName: icons[i], accessibilityDescription: tool.rawValue) {
                btn.image = img
                btn.imagePosition = .imageLeading
            }
            addSubview(btn)
            toolButtons.append(btn)
            x += 62
        }

        x += 8

        // 颜色选择
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .white, .black]
        for (i, color) in colors.enumerated() {
            let swatch = NSButton(frame: NSRect(x: x + CGFloat(i) * 24, y: y + 4, width: 20, height: 20))
            swatch.title = ""
            swatch.bezelStyle = .smallSquare
            swatch.isBordered = true
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.layer?.cornerRadius = 3
            swatch.layer?.borderWidth = 1.5
            swatch.layer?.borderColor = NSColor.separatorColor.cgColor
            swatch.tag = i
            swatch.target = self
            swatch.action = #selector(colorTapped(_:))
            addSubview(swatch)
        }

        // 撤销按钮 (Cmd+Z)
        let undoBtn = NSButton(frame: NSRect(x: bounds.width - 190, y: y, width: 56, height: h))
        undoBtn.title = "撤销"
        undoBtn.bezelStyle = .rounded
        undoBtn.target = self
        undoBtn.action = #selector(undoTapped)
        undoBtn.autoresizingMask = .minXMargin
        if let img = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销") {
            undoBtn.image = img
            undoBtn.imagePosition = .imageLeading
        }
        addSubview(undoBtn)

        // 放弃按钮 - 丢弃整个截屏
        let cancelBtn = NSButton(frame: NSRect(x: bounds.width - 126, y: y, width: 56, height: h))
        cancelBtn.title = "放弃"
        cancelBtn.bezelStyle = .rounded
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelTapped)
        cancelBtn.autoresizingMask = .minXMargin
        addSubview(cancelBtn)

        // 完成按钮
        let doneBtn = NSButton(frame: NSRect(x: bounds.width - 64, y: y, width: 56, height: h))
        doneBtn.title = "完成"
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"  // Enter 键快捷键
        doneBtn.target = self
        doneBtn.action = #selector(doneTapped)
        doneBtn.autoresizingMask = .minXMargin
        addSubview(doneBtn)
    }

    @objc private func toolTapped(_ sender: NSButton) {
        for btn in toolButtons {
            btn.state = (btn === sender) ? .on : .off
        }
        onToolSelected?(AnnotationToolType.allCases[sender.tag])
    }

    @objc private func colorTapped(_ sender: NSButton) {
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .white, .black]
        onColorSelected?(colors[sender.tag])
    }

    @objc private func undoTapped() { onUndo?() }
    @objc private func doneTapped() { onDone?() }
    @objc private func cancelTapped() { onCancel?() }
}
