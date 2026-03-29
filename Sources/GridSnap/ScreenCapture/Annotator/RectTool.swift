import AppKit

/// 矩形标注
struct RectElement: AnnotationElement {
    var toolType: AnnotationToolType { .rect }
    var origin: CGPoint
    var size: CGSize
    var color: NSColor
    var lineWidth: CGFloat

    var rect: CGRect { CGRect(origin: origin, size: size) }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.stroke(rect)
        context.restoreGState()
    }

    func handles() -> [Handle] {
        let r = rect
        return [
            Handle(type: .topLeft,     center: CGPoint(x: r.minX, y: r.maxY)),
            Handle(type: .topRight,    center: CGPoint(x: r.maxX, y: r.maxY)),
            Handle(type: .bottomLeft,  center: CGPoint(x: r.minX, y: r.minY)),
            Handle(type: .bottomRight, center: CGPoint(x: r.maxX, y: r.minY)),
        ]
    }

    mutating func moveHandle(_ type: HandleType, to point: CGPoint) {
        let r = rect
        switch type {
        case .topLeft:
            origin = CGPoint(x: point.x, y: min(point.y, r.minY))
            size = CGSize(width: r.maxX - point.x, height: point.y - r.minY)
        case .topRight:
            origin = CGPoint(x: r.minX, y: min(point.y, r.minY))
            size = CGSize(width: point.x - r.minX, height: point.y - r.minY)
        case .bottomLeft:
            origin = CGPoint(x: point.x, y: point.y)
            size = CGSize(width: r.maxX - point.x, height: r.maxY - point.y)
        case .bottomRight:
            origin = CGPoint(x: r.minX, y: point.y)
            size = CGSize(width: point.x - r.minX, height: r.maxY - point.y)
        default: break
        }
        // 规范化：确保 size 不为负
        if size.width < 0 { origin.x += size.width; size.width = -size.width }
        if size.height < 0 { origin.y += size.height; size.height = -size.height }
    }

    mutating func translate(dx: CGFloat, dy: CGFloat) {
        origin.x += dx; origin.y += dy
    }

    func contains(point: CGPoint) -> Bool {
        let expanded = rect.insetBy(dx: -8, dy: -8)
        let inner = rect.insetBy(dx: 8, dy: 8)
        return expanded.contains(point) && !inner.contains(point)
    }
}
