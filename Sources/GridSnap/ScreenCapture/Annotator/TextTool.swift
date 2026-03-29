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

    func contains(point: CGPoint) -> Bool {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(origin: position, size: size)
        return rect.contains(point)
    }
}
