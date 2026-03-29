import AppKit

/// 马赛克标注
struct MosaicElement: AnnotationElement {
    var toolType: AnnotationToolType { .mosaic }
    var rect: CGRect
    var color: NSColor = .clear
    var lineWidth: CGFloat = 0
    let sourceImage: NSImage

    private let blockSize: Int = 10

    func draw(in context: CGContext) {
        guard rect.width > 2, rect.height > 2 else { return }

        // 从源图获取对应区域并做像素化
        guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let scaleX = CGFloat(cgImage.width) / sourceImage.size.width
        let scaleY = CGFloat(cgImage.height) / sourceImage.size.height

        let cropRect = CGRect(
            x: rect.origin.x * scaleX,
            y: (sourceImage.size.height - rect.origin.y - rect.height) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return }

        // 缩小再放大 = 像素化
        let smallW = max(1, Int(rect.width) / blockSize)
        let smallH = max(1, Int(rect.height) / blockSize)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let miniCtx = CGContext(
            data: nil,
            width: smallW,
            height: smallH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        miniCtx.interpolationQuality = .none
        miniCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))

        guard let miniImage = miniCtx.makeImage() else { return }

        // 绘制像素化图像到原始区域
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(miniImage, in: rect)
        context.restoreGState()
    }

    func contains(point: CGPoint) -> Bool {
        rect.contains(point)
    }
}
