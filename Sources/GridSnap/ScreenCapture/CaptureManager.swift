import AppKit
import ScreenCaptureKit

/// 截屏模式
enum CaptureMode: String, CaseIterable {
    case region   = "区域"
    case window   = "窗口"
    case screen   = "全屏"
    case scroll   = "长截屏"
}

/// 截屏完成后的回调数据
struct CaptureResult {
    let image: NSImage
    let mode: CaptureMode
}

/// 截屏管理器 — 截屏功能的总入口
final class CaptureManager: ObservableObject {
    static let shared = CaptureManager()

    @Published var isCapturing = false
    @Published var currentMode: CaptureMode = .region

    private var overlayControllers: [CaptureOverlayController] = []
    private var annotationController: AnnotationWindowController?
    private var activeScrollCapture: ScrollCapture?

    // MARK: - 进入/退出截屏模式

    func startCapture(mode: CaptureMode = .region) {
        guard !isCapturing else { return }
        isCapturing = true
        currentMode = mode


        // 每个屏幕都创建一个 overlay 窗口
        for screen in NSScreen.screens {
            let overlay = CaptureOverlayController(screen: screen, manager: self)
            overlayControllers.append(overlay)
            overlay.showWindow(nil)
        }

        // 所有 overlay 就绪后激活 app
        NSApp.activate(ignoringOtherApps: true)
    }

    func cancelCapture() {
        cleanup()
    }

    func finishCapture(region: CGRect, on screen: NSScreen) {
        // 先隐藏所有 overlay
        for ctl in overlayControllers {
            ctl.window?.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }

            // region 是 view 本地坐标 (origin 在 screen 左下角)
            // 转为 NS 全局坐标
            let globalRect = CGRect(
                x: screen.frame.origin.x + region.origin.x,
                y: screen.frame.origin.y + region.origin.y,
                width: region.width,
                height: region.height
            )

            switch self.currentMode {
            case .scroll:
                // 长截屏：找到框选区域内的窗口，执行滚动截取
                self.startScrollCapture(in: globalRect, on: screen)
                return  // cleanup 由回调处理

            case .screen:
                if let image = self.captureFullScreen(screen) {
                    let result = CaptureResult(image: image, mode: self.currentMode)
                    self.handleCaptureResult(result)
                }

            default:
                if let image = self.captureRegion(globalRect) {
                    let result = CaptureResult(image: image, mode: self.currentMode)
                    self.handleCaptureResult(result)
                }
            }

            self.cleanup()
        }
    }

    // MARK: - 长截屏

    private func startScrollCapture(in globalRect: CGRect, on screen: NSScreen) {
        // 找框选区域内的窗口
        let wm = WindowManager.shared
        let windows = wm.getVisibleWindows(on: screen)

        // 转换 globalRect 到 CG 坐标系来匹配窗口
        guard let primaryScreen = NSScreen.screens.first else {
            cleanup()
            return
        }
        let primaryH = primaryScreen.frame.height
        let cgRect = CGRect(
            x: globalRect.origin.x,
            y: primaryH - globalRect.origin.y - globalRect.height,
            width: globalRect.width,
            height: globalRect.height
        )

        // 找与框选区域交集最大的窗口
        var bestWindow: ManagedWindow?
        var bestOverlap: CGFloat = 0
        for window in windows {
            let intersection = window.frame.intersection(cgRect)
            if !intersection.isNull {
                let area = intersection.width * intersection.height
                if area > bestOverlap {
                    bestOverlap = area
                    bestWindow = window
                }
            }
        }

        guard let targetWindow = bestWindow else {
            print("GridSnap: 长截屏 — 未找到目标窗口")
            cleanup()
            return
        }

        print("GridSnap: 长截屏 — 开始截取窗口: \(targetWindow.app) - \(targetWindow.title)")

         let scrollCapture = ScrollCapture(targetWindow: targetWindow)
        self.activeScrollCapture = scrollCapture
        scrollCapture.capture(maxScrolls: 20) { [weak self] image in
            guard let self = self else { return }
            if let image = image {
                // 如果图片太大，缩放到合理尺寸以便标注
                let maxHeight: CGFloat = 8000
                let finalImage: NSImage
                if image.size.height > maxHeight {
                    let ratio = maxHeight / image.size.height
                    let newSize = NSSize(width: image.size.width * ratio, height: maxHeight)
                    finalImage = NSImage(size: newSize)
                    finalImage.lockFocus()
                    image.draw(in: NSRect(origin: .zero, size: newSize),
                              from: NSRect(origin: .zero, size: image.size),
                              operation: .sourceOver, fraction: 1.0)
                    finalImage.unlockFocus()
                } else {
                    finalImage = image
                }
                let result = CaptureResult(image: finalImage, mode: .scroll)
                self.handleCaptureResult(result)
            } else {
                print("GridSnap: 长截屏失败")
            }
            self.activeScrollCapture = nil
            self.cleanup()
        }
    }

    // MARK: - 截取区域

    private func captureRegion(_ nsGlobalRect: CGRect) -> NSImage? {
        // NS 全局坐标 (左下原点) → CG 坐标 (左上原点)
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let primaryH = primaryScreen.frame.height

        var cgRect = nsGlobalRect
        cgRect.origin.y = primaryH - nsGlobalRect.origin.y - nsGlobalRect.height

        guard cgRect.width > 0, cgRect.height > 0 else { return nil }

        guard let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return nil }

        // size 用点数（nsGlobalRect 的尺寸），不用 cgImage 像素数
        // cgImage 在 Retina 屏上可能是 2x 像素，但 NSImage.size 应该是点数
        return NSImage(cgImage: cgImage, size: NSSize(width: nsGlobalRect.width, height: nsGlobalRect.height))
    }

    // MARK: - 截取全屏

    private func captureFullScreen(_ screen: NSScreen) -> NSImage? {
        return captureRegion(screen.frame)
    }

    // MARK: - 处理截屏结果

    private func handleCaptureResult(_ result: CaptureResult) {
        let annotator = AnnotationWindowController(
            image: result.image,
            onFinish: { [weak self] annotatedImage in
                self?.outputImage(annotatedImage)
                self?.annotationController = nil
            },
            onAbandon: { [weak self] in
                // 放弃: 不保存、不复制，什么都不做
                print("GridSnap: 用户放弃截屏")
                self?.annotationController = nil
            }
        )
        self.annotationController = annotator
        annotator.showWindow(nil)
    }

    private func outputImage(_ image: NSImage) {
        let prefs = Preferences.shared

        if prefs.screenshotOutput == "file" {
            saveToFile(image)
        }
        // 无论用户选择保存到文件还是剪贴板，都默认复制一份到剪贴板
        copyToClipboard(image)
    }

    private func copyToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        showNotification("已复制到剪贴板")
    }

    private func saveToFile(_ image: NSImage) {
        let prefs = Preferences.shared
        let dir = prefs.screenshotSavePath
        let useJPEG = prefs.screenshotFormat == "jpeg"
        let quality = prefs.screenshotQuality

        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let ext = useJPEG ? "jpg" : "png"
        let filename = "GridSnap_\(formatter.string(from: Date())).\(ext)"
        let path = (dir as NSString).appendingPathComponent(filename)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return }

        let fileData: Data?
        if useJPEG {
            fileData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        } else {
            fileData = bitmap.representation(using: .png, properties: [:])
        }

        guard let data = fileData else { return }

        do {
            try data.write(to: URL(fileURLWithPath: path))
            let sizeMB = String(format: "%.1f", Double(data.count) / 1_048_576.0)
            print("GridSnap: 已保存 \(ext.uppercased()) (\(sizeMB)MB) → \(path)")
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        } catch {
            print("GridSnap: 保存截图失败: \(error)")
        }
    }

    private func showNotification(_ message: String) {
        print("GridSnap: \(message)")
    }

    private func cleanup() {
        for ctl in overlayControllers {
            ctl.close()
        }
        overlayControllers.removeAll()
        isCapturing = false
    }
}
