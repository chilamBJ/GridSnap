import AppKit

/// 长截屏：模拟滚动 + 逐帧截取 + 计算拼接
final class ScrollCapture {
    private let targetWindow: ManagedWindow?
    private let scrollAmount: CGFloat = 300  // 每次滚动点数

    init(targetWindow: ManagedWindow? = nil) {
        self.targetWindow = targetWindow
    }

    func capture(maxScrolls: Int = 20, completion: @escaping (NSImage?) -> Void) {
        guard let window = targetWindow else {
            let windows = WindowManager.shared.getVisibleWindows()
            guard let frontWindow = windows.first else { completion(nil); return }
            doCapture(window: frontWindow, maxScrolls: maxScrolls, completion: completion)
            return
        }
        doCapture(window: window, maxScrolls: maxScrolls, completion: completion)
    }

    private func doCapture(window: ManagedWindow, maxScrolls: Int, completion: @escaping (NSImage?) -> Void) {
        var captures: [CGImage] = []
        var scrollCount = 0
        var noChangeCount = 0

        guard let firstImg = captureWindowCGImage(window) else {
            completion(nil)
            return
        }
        captures.append(firstImg)

        func next() {
            guard scrollCount < maxScrolls else {
                finish()
                return
            }

            simulateScroll(in: window, amount: scrollAmount)
            scrollCount += 1

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                guard let img = captureWindowCGImage(window) else {
                    next()
                    return
                }

                guard let lastImg = captures.last else {
                    captures.append(img)
                    next()
                    return
                }

                // 到底检测：比较两张图的中间内容区（必须变化的区域）
                if contentAreaIdentical(lastImg, img) {
                    noChangeCount += 1
                    if noChangeCount >= 2 {
                        print("GridSnap: 长截屏 — 到底，共 \(captures.count) 帧")
                        finish()
                        return
                    }
                } else {
                    noChangeCount = 0
                    captures.append(img)
                }

                next()
            }
        }

        func finish() {
            let result = stitchImages(captures)
            completion(result)
        }

        next()
    }

    // MARK: - 截取窗口

    private func captureWindowCGImage(_ window: ManagedWindow) -> CGImage? {
        return CGWindowListCreateImage(
            window.frame,
            .optionIncludingWindow,
            window.id,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }

    // MARK: - 模拟滚动

    private func simulateScroll(in window: ManagedWindow, amount: CGFloat) {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(-amount),
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.location = center
        event.post(tap: .cghidEventTap)
    }

    // MARK: - 到底检测

    /// 只比较中间内容区域（30%~70%）— 该区域在滚动后必定变化
    /// 如果不变 → 说明到底了
    private func contentAreaIdentical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }

        // 取中间 40% 的区域比较（避开固定的标题栏、侧栏等）
        let y1 = a.height * 30 / 100
        let y2 = a.height * 70 / 100
        let sampleCount = 8
        let step = (y2 - y1) / sampleCount

        var matchCount = 0
        for i in 0..<sampleCount {
            let y = y1 + i * step
            guard let rowA = a.cropping(to: CGRect(x: 0, y: y, width: a.width, height: 1)),
                  let rowB = b.cropping(to: CGRect(x: 0, y: y, width: b.width, height: 1)),
                  let dataA = rowA.dataProvider?.data as Data?,
                  let dataB = rowB.dataProvider?.data as Data?,
                  dataA.count == dataB.count, dataA.count > 0
            else { continue }

            // 逐点采样比较
            let sStep = max(4, dataA.count / 60)
            var diffs = 0
            let total = dataA.count / sStep
            for j in stride(from: 0, to: dataA.count, by: sStep) {
                if abs(Int(dataA[j]) - Int(dataB[j])) > 3 { diffs += 1 }
            }
            if diffs <= max(1, total / 10) { matchCount += 1 }
        }

        // 75%+ 行匹配 → 内容没变 → 到底了
        return matchCount >= sampleCount * 6 / 8
    }

    // MARK: - 拼接（基于计算的重叠量）

    private func stitchImages(_ images: [CGImage]) -> NSImage? {
        guard !images.isEmpty else { return nil }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        if images.count == 1 {
            let cg = images[0]
            return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        }

        let width = images[0].width
        // 计算重叠：scrollAmount 是点数，图片是 scale 倍像素
        let scrollPixels = Int(scrollAmount * scale)
        let overlap = max(0, images[0].height - scrollPixels)

        // 计算总高度
        var totalHeight = images[0].height
        for i in 1..<images.count {
            totalHeight += images[i].height - overlap
        }

        print("GridSnap: 长截屏拼接 — \(images.count) 帧, 每帧重叠 \(overlap)px, 最终 \(width)×\(totalHeight)")

        guard let colorSpace = images[0].colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: width, height: totalHeight,
                bitsPerComponent: images[0].bitsPerComponent,
                bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // CG context 坐标：(0,0) 在左下角
        var yPos = totalHeight

        for (i, image) in images.enumerated() {
            if i == 0 {
                yPos -= image.height
                ctx.draw(image, in: CGRect(x: 0, y: yPos, width: image.width, height: image.height))
            } else {
                // 裁剪掉顶部重叠区域
                let cropHeight = image.height - overlap
                yPos -= cropHeight
                if overlap > 0, overlap < image.height,
                   let cropped = image.cropping(to: CGRect(x: 0, y: overlap, width: image.width, height: cropHeight)) {
                    ctx.draw(cropped, in: CGRect(x: 0, y: yPos, width: cropped.width, height: cropHeight))
                } else {
                    ctx.draw(image, in: CGRect(x: 0, y: yPos, width: image.width, height: image.height))
                }
            }
        }

        guard let resultCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: resultCG, size: NSSize(width: CGFloat(width) / scale, height: CGFloat(totalHeight) / scale))
    }
}
