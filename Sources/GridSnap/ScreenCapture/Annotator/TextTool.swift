import AppKit

/// 文字标注
struct TextElement: AnnotationElement {
    var toolType: AnnotationToolType { .text }
    var position: CGPoint
    var text: String
    var color: NSColor
    var fontSize: CGFloat
    var lineWidth: CGFloat = 0

    func draw(in context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)

        // 用 NSGraphicsContext 绘制
        context.saveGState()
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsCtx
        attrStr.draw(at: position)
        context.restoreGState()
    }

    private var textRect: CGRect {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGRect(origin: position, size: size)
    }

    func handles() -> [Handle] {
        let r = textRect
        return [
            Handle(type: .topLeft,     center: CGPoint(x: r.minX, y: r.maxY)),
            Handle(type: .topRight,    center: CGPoint(x: r.maxX, y: r.maxY)),
            Handle(type: .bottomLeft,  center: CGPoint(x: r.minX, y: r.minY)),
            Handle(type: .bottomRight, center: CGPoint(x: r.maxX, y: r.minY)),
        ]
    }

    mutating func moveHandle(_ type: HandleType, to point: CGPoint) {
        let r = textRect
        guard r.width > 0 else { return }
        switch type {
        case .topRight, .bottomRight:
            let newWidth = max(20, point.x - r.minX)
            fontSize = max(8, min(200, fontSize * newWidth / r.width))
        case .topLeft, .bottomLeft:
            let newWidth = max(20, r.maxX - point.x)
            fontSize = max(8, min(200, fontSize * newWidth / r.width))
            position.x = point.x
        default: break
        }
    }

    mutating func translate(dx: CGFloat, dy: CGFloat) {
        position.x += dx; position.y += dy
    }

    func contains(point: CGPoint) -> Bool {
        return textRect.insetBy(dx: -4, dy: -4).contains(point)
    }
}
