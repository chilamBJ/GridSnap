import AppKit

/// 箭头标注
struct ArrowElement: AnnotationElement {
    var toolType: AnnotationToolType { .arrow }
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat

    func draw(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        // 线段
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // 箭头头部
        let headLength: CGFloat = 12
        let headAngle: CGFloat = .pi / 6

        let angle = atan2(end.y - start.y, end.x - start.x)
        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.setFillColor(color.cgColor)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()

        context.restoreGState()
    }

    func handles() -> [Handle] {
        [Handle(type: .startPoint, center: start),
         Handle(type: .endPoint, center: end)]
    }

    mutating func moveHandle(_ type: HandleType, to point: CGPoint) {
        switch type {
        case .startPoint: start = point
        case .endPoint:   end = point
        default: break
        }
    }

    mutating func translate(dx: CGFloat, dy: CGFloat) {
        start.x += dx; start.y += dy
        end.x += dx;   end.y += dy
    }

    func contains(point: CGPoint) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return false }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (length * length)))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        let dist = sqrt(pow(point.x - projection.x, 2) + pow(point.y - projection.y, 2))
        return dist < 8
    }
}
