import AppKit
import ApplicationServices
import os

private let gsLogger = Logger(subsystem: "com.gridsnap.app", category: "WindowManager")

/// 统一日志 — 同时输出到 stdout 和 os_log（方便从 Finder 启动时通过 Console.app 查看）
func gsLog(_ message: String) {
    print(message)
    gsLogger.notice("\(message, privacy: .public)")
}

// macOS 私有 API：直接从 AXUIElement 获取 CGWindowID
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// 代表一个可操控的窗口
struct ManagedWindow: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let title: String
    var frame: CGRect
    let axWindow: AXUIElement

    var isFloating: Bool { true }
}

/// 网格布局状态 — 记录当前网格的单元格和窗口分配
struct GridState {
    let screen: NSScreen
    let cellFrames: [CGRect]        // CG 坐标系
    var windowIDs: [CGWindowID?]    // 每个 cell 对应的窗口 ID，nil = 空位
}

/// 窗口管理核心：查询和操控 macOS 窗口
final class WindowManager {
    static let shared = WindowManager()

    /// 当前活动的网格布局状态
    var activeGrid: GridState?

    // MARK: - 查询所有可见窗口

    /// 获取指定显示器上的所有可见窗口
    func getVisibleWindows(on display: NSScreen? = nil) -> [ManagedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            gsLog("[GridSnap] CGWindowListCopyWindowInfo 返回 nil")
            return []
        }

        var windows: [ManagedWindow] = []
        var axFailCount = 0
        var candidateCount = 0
        // CG→NS 坐标转换需要主屏高度
        let primaryH = NSScreen.screens.first?.frame.height ?? 0

        for info in windowList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 // 普通窗口层
            else { continue }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let title = info[kCGWindowName as String] as? String ?? ""

            // 跳过自身和没有标题的窗口
            if ownerName == "GridSnap" || ownerName == "WindowServer" { continue }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // 跳过太小的窗口（可能是隐藏的辅助窗口）
            guard bounds.width > 50 && bounds.height > 50 else { continue }

            // 如果指定了显示器，将 CG 坐标（左上原点）转为 NS 坐标（左下原点）再比较
            if let screen = display {
                let nsY = primaryH - bounds.origin.y - bounds.height
                let nsCenter = CGPoint(x: bounds.midX, y: nsY + bounds.height / 2)
                if !screen.frame.contains(nsCenter) {
                    continue
                }
            }

            candidateCount += 1

            // 获取 AX 元素
            let appElement = AXUIElementCreateApplication(pid)
            guard let axWindow = findAXWindow(app: appElement, matching: bounds) else {
                axFailCount += 1
                gsLog("[GridSnap] AX 查询失败: \(ownerName) (pid=\(pid), wid=\(windowID))")
                continue
            }

            let window = ManagedWindow(
                id: windowID,
                pid: pid,
                app: ownerName,
                title: title,
                frame: bounds,
                axWindow: axWindow
            )
            windows.append(window)
        }

        gsLog("[GridSnap] getVisibleWindows: 候选=\(candidateCount) 成功=\(windows.count) AX失败=\(axFailCount))")
        return windows
    }

    // MARK: - 查找当前 active 窗口

    /// 在窗口列表中找到当前 frontmost 应用的窗口索引
    func findActiveWindowIndex(in windows: [ManagedWindow]) -> Int? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let frontPID = frontApp.processIdentifier

        // 优先找 frontmost app 的 focused window
        let appRef = AXUIElementCreateApplication(frontPID)
        var focusedValue: AnyObject?
        AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedValue)

        if let focusedWindow = focusedValue {
            // 拿 focused window 的 frame 来匹配
            var posValue: AnyObject?
            var sizeValue: AnyObject?
            AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXPositionAttribute as CFString, &posValue)
            AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXSizeAttribute as CFString, &sizeValue)

            if let pv = posValue, let sv = sizeValue {
                var pos = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
                AXValueGetValue(sv as! AXValue, .cgSize, &size)

                // 找匹配的窗口
                for (i, w) in windows.enumerated() {
                    if w.pid == frontPID &&
                       abs(w.frame.origin.x - pos.x) < 5 &&
                       abs(w.frame.origin.y - pos.y) < 5 {
                        return i
                    }
                }
            }
        }

        // fallback: 找同 PID 的第一个窗口
        return windows.firstIndex(where: { $0.pid == frontPID })
    }

    // MARK: - 移动窗口

    func moveWindow(_ window: ManagedWindow, to position: CGPoint) {
        var point = position
        let value = AXValueCreate(.cgPoint, &point)!
        AXUIElementSetAttributeValue(window.axWindow, kAXPositionAttribute as CFString, value)
    }

    // MARK: - 调整窗口大小

    func resizeWindow(_ window: ManagedWindow, to size: CGSize) {
        var s = size
        let value = AXValueCreate(.cgSize, &s)!
        AXUIElementSetAttributeValue(window.axWindow, kAXSizeAttribute as CFString, value)
    }

    // MARK: - 移动并调整大小

    func setWindowFrame(_ window: ManagedWindow, frame: CGRect) {
        moveWindow(window, to: frame.origin)
        resizeWindow(window, to: frame.size)
    }

    // MARK: - 排列所有窗口到指定布局

    func arrangeWindows(using layout: LayoutStrategy, on screen: NSScreen? = nil) {
        // 前置检查辅助功能权限
        if !AccessibilityHelper.checkAccess(prompt: false) {
            gsLog("[GridSnap] 辅助功能权限不足，无法排列窗口")
            DispatchQueue.main.async {
                AccessibilityHelper.showPermissionAlert()
            }
            return
        }

        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        var windows = getVisibleWindows(on: targetScreen)

        guard !windows.isEmpty else {
            gsLog("[GridSnap] 没有找到可管理的窗口")
            return
        }

        // 1+N 布局：把当前 active 窗口排到第一位（占左半大窗口）
        if layout is Layout1Plus2 || layout is Layout1Plus3 {
            if let activeIdx = findActiveWindowIndex(in: windows), activeIdx > 0 {
                let active = windows.remove(at: activeIdx)
                windows.insert(active, at: 0)
            }
        }

        let frames = layout.calculateFrames(
            windowCount: windows.count,
            in: targetScreen.visibleFrame
        )

        for (i, window) in windows.enumerated() where i < frames.count {
            let cgFrame = convertToCGCoordinates(frames[i])
            setWindowFrame(window, frame: cgFrame)
        }

        // 保存网格状态 — 使用完整网格（包含空位）
        let allCellFrames: [CGRect]
        if let gridLayout = layout as? GridLayout {
            allCellFrames = gridLayout.allCellFrames(in: targetScreen.visibleFrame).map { convertToCGCoordinates($0) }
        } else if let autoLayout = layout as? AutoGridLayout {
            // AutoGridLayout 内部使用 GridLayout
            let (r, c) = AutoGridLayout.bestGrid(for: windows.count)
            let gl = GridLayout(rows: r, cols: c, config: autoLayout.config)
            allCellFrames = gl.allCellFrames(in: targetScreen.visibleFrame).map { convertToCGCoordinates($0) }
        } else {
            allCellFrames = frames.map { convertToCGCoordinates($0) }
        }

        var windowIDs: [CGWindowID?] = []
        for i in 0..<allCellFrames.count {
            windowIDs.append(i < windows.count ? windows[i].id : nil)
        }
        activeGrid = GridState(screen: targetScreen, cellFrames: allCellFrames, windowIDs: windowIDs)
    }

    /// 排列所有屏幕的窗口
    func arrangeAllScreens(using layout: LayoutStrategy) {
        for screen in NSScreen.screens {
            arrangeWindows(using: layout, on: screen)
        }
    }

    // MARK: - 平滑动画排列

    private var animationTimer: Timer?

    /// 快速过渡动画 — AX API 太慢无法做真正逐帧动画
    /// 只做 3 步快速跳跃（~80ms），视觉上有"弹过去"的效果
    private func arrangeWindowsAnimated(windows: [ManagedWindow], targetFrames: [CGRect], duration: Double) {
        let startFrames: [CGRect] = windows.enumerated().map { (i, w) in
            i < targetFrames.count ? w.frame : .zero
        }
        let endFrames: [CGRect] = targetFrames.map { convertToCGCoordinates($0) }

        // 3 步: 30% → 70% → 100%，每步间隔 ~25ms
        let keyframes: [Double] = [0.3, 0.7, 1.0]

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }

            for (idx, t) in keyframes.enumerated() {
                let eased = 1.0 - pow(1.0 - t, 3.0)

                for (i, window) in windows.enumerated() where i < endFrames.count {
                    let from = startFrames[i]
                    let to = endFrames[i]
                    let current = CGRect(
                        x: self.lerp(from.origin.x, to.origin.x, eased),
                        y: self.lerp(from.origin.y, to.origin.y, eased),
                        width: self.lerp(from.width, to.width, eased),
                        height: self.lerp(from.height, to.height, eased)
                    )
                    self.setWindowFrame(window, frame: current)
                }

                if idx < keyframes.count - 1 {
                    usleep(25_000) // 25ms
                }
            }
        }
    }

    /// 线性插值
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }

    // MARK: - Private

    /// 通过 CGWindowID 精确查找 AX 窗口（零位置匹配，100% 可靠）
    func findAXWindowByCGID(app: AXUIElement, windowID: CGWindowID) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement]
        else { return nil }

        for axWindow in axWindows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &wid) == .success, wid == windowID {
                return axWindow
            }
        }
        return nil
    }

    /// 在 AX 层级中找到匹配指定位置的窗口（最近距离匹配，fallback）
    func findAXWindow(app: AXUIElement, matching bounds: CGRect) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement]
        else { return nil }

        var bestWindow: AXUIElement?
        var bestDist = CGFloat.greatestFiniteMagnitude

        for axWindow in axWindows {
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?

            guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
                  AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success
            else { continue }

            var point = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

            let dist = hypot(point.x - bounds.origin.x, point.y - bounds.origin.y)
            if dist < bestDist {
                bestDist = dist
                bestWindow = axWindow
            }
        }

        // 容差 100px — 宁可不移也别移错
        return bestDist < 100 ? bestWindow : nil
    }

    /// 通过 CGWindowID 的位置信息在 AX 层级中查找窗口
    func findAXWindowByID(app: AXUIElement, windowID: CGWindowID) -> AXUIElement? {
        // 先从 CGWindowList 获取该 windowID 的位置
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var targetBounds: CGRect?
        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID, wid == windowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            targetBounds = CGRect(
                x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0
            )
            break
        }

        guard let bounds = targetBounds else { return nil }
        return findAXWindow(app: app, matching: bounds)
    }

    /// NSScreen (左下原点) → CGWindow (左上原点) 坐标转换
    private func convertToCGCoordinates(_ nsRect: CGRect) -> CGRect {
        guard let mainScreen = NSScreen.screens.first else { return nsRect }
        let screenHeight = mainScreen.frame.height
        return CGRect(
            x: nsRect.origin.x,
            y: screenHeight - nsRect.origin.y - nsRect.height,
            width: nsRect.width,
            height: nsRect.height
        )
    }
}
