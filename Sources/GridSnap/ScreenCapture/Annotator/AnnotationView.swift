import AppKit

/// 标注工具类型
enum AnnotationToolType: String, CaseIterable {
    case arrow  = "箭头"
    case rect   = "矩形"
    case text   = "文字"
    case mosaic = "马赛克"
}

/// 控制手柄类型
enum HandleType {
    case topLeft, topRight, bottomLeft, bottomRight
    case startPoint, endPoint  // 箭头专用
    case body                  // 整体拖动
}

/// 控制手柄
struct Handle {
    let type: HandleType
    let center: CGPoint
    static let radius: CGFloat = 5
    var rect: CGRect {
        CGRect(x: center.x - Self.radius, y: center.y - Self.radius,
               width: Self.radius * 2, height: Self.radius * 2)
    }
    func contains(point: CGPoint) -> Bool {
        let hitRadius: CGFloat = Self.radius + 4 // 扩大点击热区
        return hypot(point.x - center.x, point.y - center.y) <= hitRadius
    }
}

/// 单个标注元素
protocol AnnotationElement {
    var toolType: AnnotationToolType { get }
    var color: NSColor { get set }
    var lineWidth: CGFloat { get set }
    func draw(in context: CGContext)
    func contains(point: CGPoint) -> Bool
    /// 返回可拖拽的控制手柄
    func handles() -> [Handle]
    /// 拖动某个手柄时更新自身
    mutating func moveHandle(_ type: HandleType, to point: CGPoint)
    /// 整体平移
    mutating func translate(dx: CGFloat, dy: CGFloat)
}

/// 绘制选中状态的手柄
func drawSelectionHandles(_ handles: [Handle], in context: CGContext) {
    for handle in handles {
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.5)
        context.fillEllipse(in: handle.rect)
        context.strokeEllipse(in: handle.rect)
        context.restoreGState()
    }
}

/// 绘制 hover 高亮轮廓
func drawHoverOutline(_ handles: [Handle], in context: CGContext) {
    guard !handles.isEmpty else { return }
    let xs = handles.map { $0.center.x }
    let ys = handles.map { $0.center.y }
    let bbox = CGRect(
        x: (xs.min() ?? 0) - 6, y: (ys.min() ?? 0) - 6,
        width: ((xs.max() ?? 0) - (xs.min() ?? 0)) + 12,
        height: ((ys.max() ?? 0) - (ys.min() ?? 0)) + 12
    )
    context.saveGState()
    context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.4).cgColor)
    context.setLineWidth(1.5)
    context.setLineDash(phase: 0, lengths: [4, 3])
    context.stroke(bbox)
    context.restoreGState()
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

/// 交互模式
private enum InteractionMode {
    case none                               // 空闲
    case drawing                            // 新建标注
    case draggingHandle(Int, HandleType)     // 拖手柄 (元素索引, 手柄类型)
    case movingElement(Int)                  // 整体拖动 (元素索引)
}

final class AnnotationCanvasView: NSView {
    private let image: NSImage
    var currentTool: AnnotationToolType = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 2.0

    private var elements: [AnnotationElement] = []
    private var currentElement: AnnotationElement?
    private var dragStart: NSPoint?

    /// 选中状态
    private var selectedIndex: Int? = nil
    private var mode: InteractionMode = .none
    private var lastDragPoint: NSPoint?
    private var hoveredIndex: Int? = nil
    private var trackingArea: NSTrackingArea?

    /// Undo: 是否还能撤销
    var canUndo: Bool { !elements.isEmpty }

    init(frame: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // 检查是否 hover 在选中元素的手柄上
        if let selIdx = selectedIndex {
            for h in elements[selIdx].handles() {
                if h.contains(point: point) {
                    NSCursor.openHand.set()
                    setHoveredIndex(nil)
                    return
                }
            }
        }
        // 检查是否 hover 在某个元素上
        var newHover: Int? = nil
        for i in stride(from: elements.count - 1, through: 0, by: -1) {
            if elements[i].contains(point: point) { newHover = i; break }
        }
        if newHover != nil { NSCursor.pointingHand.set() }
        else { NSCursor.crosshair.set() }
        setHoveredIndex(newHover)
    }

    private func setHoveredIndex(_ idx: Int?) {
        guard hoveredIndex != idx else { return }
        hoveredIndex = idx
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Undo

    func undo() {
        guard !elements.isEmpty else { return }
        if let sel = selectedIndex, sel == elements.count - 1 { selectedIndex = nil }
        if let hov = hoveredIndex, hov >= elements.count - 1 { hoveredIndex = nil }
        elements.removeLast()
        needsDisplay = true
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undo(); return
        }
        // Escape 取消选中
        if event.keyCode == 53 {
            selectedIndex = nil
            needsDisplay = true
            return
        }
        // Delete/Backspace 删除选中
        if (event.keyCode == 51 || event.keyCode == 117), let idx = selectedIndex {
            elements.remove(at: idx)
            selectedIndex = nil
            hoveredIndex = nil
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        image.draw(in: bounds)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        for (i, element) in elements.enumerated() {
            element.draw(in: ctx)
            if i == selectedIndex {
                drawSelectionHandles(element.handles(), in: ctx)
            } else if i == hoveredIndex {
                drawHoverOutline(element.handles(), in: ctx)
            }
        }
        currentElement?.draw(in: ctx)
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        lastDragPoint = point

        // 1. 如果有选中元素，先检查是否点在手柄上
        if let selIdx = selectedIndex {
            let handles = elements[selIdx].handles()
            for handle in handles {
                if handle.contains(point: point) {
                    mode = .draggingHandle(selIdx, handle.type)
                    NSCursor.closedHand.set()
                    return
                }
            }
            // 点在选中元素本体上 → 整体移动
            if elements[selIdx].contains(point: point) {
                mode = .movingElement(selIdx)
                NSCursor.closedHand.set()
                return
            }
        }

        // 2. 检查是否点击了某个已有元素 → 选中它
        for i in stride(from: elements.count - 1, through: 0, by: -1) {
            if elements[i].contains(point: point) {
                selectedIndex = i
                mode = .none
                needsDisplay = true
                return
            }
        }

        // 3. 点击空白 → 取消选中，开始绘制新元素
        selectedIndex = nil
        mode = .drawing

        switch currentTool {
        case .arrow:
            currentElement = ArrowElement(start: point, end: point, color: currentColor, lineWidth: currentLineWidth)
        case .rect:
            currentElement = RectElement(origin: point, size: .zero, color: currentColor, lineWidth: currentLineWidth)
        case .text:
            mode = .none
            promptForText(at: point)
            return
        case .mosaic:
            currentElement = MosaicElement(rect: NSRect(origin: point, size: .zero), sourceImage: image)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)

        switch mode {
        case .draggingHandle(let idx, let handleType):
            elements[idx].moveHandle(handleType, to: current)
            needsDisplay = true

        case .movingElement(let idx):
            if let last = lastDragPoint {
                let dx = current.x - last.x
                let dy = current.y - last.y
                elements[idx].translate(dx: dx, dy: dy)
                needsDisplay = true
            }

        case .drawing:
            guard let start = dragStart else { return }
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

        case .none:
            if let selIdx = selectedIndex, elements[selIdx].contains(point: current) {
                mode = .movingElement(selIdx)
                NSCursor.closedHand.set()
            }
        }

        lastDragPoint = current
    }

    override func mouseUp(with event: NSEvent) {

        switch mode {
        case .drawing:
            if let element = currentElement {
                elements.append(element)
                selectedIndex = elements.count - 1
                currentElement = nil
            }

        case .draggingHandle, .movingElement:
            break  // 已经在 drag 中实时更新了

        case .none:
            break
        }

        mode = .none
        dragStart = nil
        lastDragPoint = nil
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    private func promptForText(at point: NSPoint) {
        // 使用异步 sheet 避免 runModal 阻塞事件循环
        guard let hostWindow = window else { return }
        let alert = NSAlert()
        alert.messageText = "输入文字"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = textField
        alert.beginSheetModal(for: hostWindow) { [weak self] response in
            guard let self = self else { return }
            if response == .alertFirstButtonReturn, !textField.stringValue.isEmpty {
                let textElement = TextElement(
                    position: point,
                    text: textField.stringValue,
                    color: self.currentColor,
                    fontSize: 16
                )
                self.elements.append(textElement)
                self.selectedIndex = self.elements.count - 1
                self.needsDisplay = true
            }
            // 恢复画布焦点
            hostWindow.makeFirstResponder(self)
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
