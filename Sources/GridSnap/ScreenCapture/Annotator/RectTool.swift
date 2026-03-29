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

    func contains(point: CGPoint) -> Bool {
        let expanded = rect.insetBy(dx: -8, dy: -8)
        let inner = rect.insetBy(dx: 8, dy: 8)
        return expanded.contains(point) && !inner.contains(point)
    }
}
