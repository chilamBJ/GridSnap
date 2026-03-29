import SwiftUI

@main
struct GridSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 菜单栏入口 — .window 模式支持完整 SwiftUI 渲染
        MenuBarExtra {
            MenuBarView()
        } label: {
            if let icon = Self.menuBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "square.grid.2x2.fill")
            }
        }
        .menuBarExtraStyle(.window)

        // 设置窗口
        Settings {
            SettingsView()
        }
    }

    /// 从 bundle 加载 AppIcon.png → 去白底 → 缩放到 18pt → 设置为 template
    private static let menuBarIcon: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let source = NSImage(contentsOf: url)
        else { return nil }

        let targetSize = NSSize(width: 22, height: 22)

        // 将白色背景替换为透明
        guard let tiffData = source.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage
        else { return nil }

        let w = cgImage.width, h = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // 白背景 → 透明，黑色部分保留为不透明
        for i in 0..<(w * h) {
            let offset = i * 4
            let r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
            let brightness = (Int(r) + Int(g) + Int(b)) / 3
            if brightness > 200 {
                // 接近白色 → 完全透明
                pixels[offset + 3] = 0
            } else {
                // 深色部分 → alpha = (255 - brightness)
                pixels[offset + 3] = UInt8(min(255, 255 - brightness))
            }
        }

        guard let processedCG = ctx.makeImage() else { return nil }

        let icon = NSImage(size: targetSize)
        icon.addRepresentation(NSBitmapImageRep(cgImage: processedCG))
        icon.size = targetSize
        icon.isTemplate = true  // 让系统自动适配浅色/深色模式
        return icon
    }()
}
