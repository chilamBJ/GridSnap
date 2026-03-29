import AppKit

/// 磁吸区域定义 (屏幕边缘吸附 — 当无网格时的 fallback)
enum SnapZone: CaseIterable {
    case left, right, topLeft, topRight, bottomLeft, bottomRight, fullScreen

    func frame(for screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame
        let halfW = f.width / 2
        let halfH = f.height / 2

        switch self {
        case .left:        return CGRect(x: f.minX, y: f.minY, width: halfW, height: f.height)
        case .right:       return CGRect(x: f.minX + halfW, y: f.minY, width: halfW, height: f.height)
        case .topLeft:     return CGRect(x: f.minX, y: f.minY + halfH, width: halfW, height: halfH)
        case .topRight:    return CGRect(x: f.minX + halfW, y: f.minY + halfH, width: halfW, height: halfH)
        case .bottomLeft:  return CGRect(x: f.minX, y: f.minY, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: f.minX + halfW, y: f.minY, width: halfW, height: halfH)
        case .fullScreen:  return f
        }
    }

    func triggerRect(for screen: NSScreen, sensitivity: CGFloat) -> CGRect {
        let f = screen.frame
        let s = sensitivity
        let corner: CGFloat = 80

        switch self {
        case .left:        return CGRect(x: f.minX, y: f.minY + corner, width: s, height: f.height - 2 * corner)
        case .right:       return CGRect(x: f.maxX - s, y: f.minY + corner, width: s, height: f.height - 2 * corner)
        case .topLeft:     return CGRect(x: f.minX, y: f.maxY - corner, width: corner, height: corner)
        case .topRight:    return CGRect(x: f.maxX - corner, y: f.maxY - corner, width: corner, height: corner)
        case .bottomLeft:  return CGRect(x: f.minX, y: f.minY, width: corner, height: corner)
        case .bottomRight: return CGRect(x: f.maxX - corner, y: f.minY, width: corner, height: corner)
        case .fullScreen:  return CGRect(x: f.minX + corner, y: f.maxY - s, width: f.width - 2 * corner, height: s)
        }
    }

    var priority: Int {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return 0
        case .left, .right: return 1
        case .fullScreen: return 2
        }
    }
}

/// 磁吸吸附管理器 — 网格感知 + 屏幕边缘吸附
final class SnapZoneManager {
    static let shared = SnapZoneManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlay: SnapOverlayWindow?

    // 网格模式状态
    private var targetCellIndex: Int?
    private var sourceCellIndex: Int?
    private var sourceAXWindow: AXUIElement?
    private var sourceWindowID: CGWindowID?  // 初始化时确定，拖拽期间不变
    private var dragInitialized = false

    // 窗口拖拽检测 — 区分窗口拖动 vs 窗口内操作
    private var initialWindowPos: CGPoint?   // 拖拽开始时窗口位置
    private var initialMousePos: NSPoint?    // 拖拽开始时鼠标位置
    private var isConfirmedWindowDrag = false // 窗口位置确实发生了移动
    private let dragThreshold: CGFloat = 15  // 窗口移动阈值 (px)

    // 边缘吸附模式状态
    private var activeZone: SnapZone?

    // 过期拖拽检测
    private var lastDragTime: CFAbsoluteTime = 0

    var isEnabled: Bool {
        get { Preferences.shared.snapEnabled }
        set { Preferences.shared.snapEnabled = newValue; newValue ? start() : stop() }
    }

    // MARK: - Start / Stop

    func start() {
        guard Preferences.shared.snapEnabled else { return }
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDragged.rawValue) |
                                     (1 << CGEventType.leftMouseUp.rawValue) |
                                     (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                                     (1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<SnapZoneManager>.fromOpaque(refcon).takeUnretainedValue()

                // ━━ tap 被禁用：只重新启用，不清理状态（避免破坏正在进行的拖拽）━━
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                DispatchQueue.main.async {
                    let mouseLocation = NSEvent.mouseLocation
                    switch type {
                    case .leftMouseDragged:
                        manager.handleDrag(at: mouseLocation)
                    case .leftMouseUp:
                        manager.handleDrop(at: mouseLocation)
                    default:
                        break
                    }
                }
                return Unmanaged.passUnretained(event)  // listenOnly tap 不需要 retain
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("GridSnap: CGEventTap 创建失败，请确保已授予辅助功能权限")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("GridSnap: 磁吸吸附已启动")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        cleanup()
    }

    // MARK: - Drag Handling

    private func handleDrag(at point: NSPoint) {
        let now = CFAbsoluteTimeGetCurrent()

        // 过期拖拽检测：两次 drag 事件间隔 > 1s，说明上次拖拽的 mouseUp 丢了
        if dragInitialized && (now - lastDragTime) > 1.0 {
            cleanup()
        }
        lastDragTime = now

        let wm = WindowManager.shared

        if let grid = wm.activeGrid {
            handleGridDrag(at: point, grid: grid)
            return
        }

        handleEdgeDrag(at: point)
    }

    private func handleDrop(at point: NSPoint) {
        let wm = WindowManager.shared

        print("[DROP] mouseUp at \(point) | activeGrid=\(wm.activeGrid != nil) targetCell=\(targetCellIndex as Any) sourceCell=\(sourceCellIndex as Any) sourceWinID=\(sourceWindowID as Any) sourceAX=\(sourceAXWindow != nil) confirmed=\(isConfirmedWindowDrag)")

        if wm.activeGrid != nil, targetCellIndex != nil {
            handleGridDrop()
            return
        }

        if activeZone != nil {
            handleEdgeDrop(at: point)
            return
        }

        cleanup()
    }

    // MARK: - 网格模式：拖拽到 cell / 互换位置

    private func handleGridDrag(at point: NSPoint, grid: GridState) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0

        // 首次拖拽：识别被拖拽窗口及其所在 cell（唯一做 AX 的时机）
        if !dragInitialized {
            dragInitialized = true
            initialMousePos = point
            initializeDragSource(grid: grid, primaryH: primaryH)
        }

        // 用鼠标移动距离判断是否为真正的窗口拖拽（不做 AX 调用）
        if !isConfirmedWindowDrag {
            if let initMouse = initialMousePos {
                let moved = hypot(point.x - initMouse.x, point.y - initMouse.y)
                if moved < dragThreshold { return }
            }
            isConfirmedWindowDrag = true
        }

        // 将 NS 鼠标坐标转为 CG 坐标
        let cgPoint = CGPoint(x: point.x, y: primaryH - point.y)

        // 检测鼠标在哪个 cell 内
        var hitIndex: Int?
        for (i, cellFrame) in grid.cellFrames.enumerated() {
            let expanded = cellFrame.insetBy(dx: -50, dy: -50)
            if expanded.contains(cgPoint) {
                if i == sourceCellIndex { continue }
                hitIndex = i
                break
            }
        }

        if let idx = hitIndex {
            if idx != targetCellIndex {
                targetCellIndex = idx
                let cellFrame = grid.cellFrames[idx]
                let nsFrame = CGRect(
                    x: cellFrame.origin.x,
                    y: primaryH - cellFrame.origin.y - cellFrame.height,
                    width: cellFrame.width,
                    height: cellFrame.height
                )
                hideOverlay()
                overlay = SnapOverlayWindow(frame: nsFrame, on: grid.screen, isSwap: true)
                overlay?.show()
            }
        } else {
            if targetCellIndex != nil {
                targetCellIndex = nil
                hideOverlay()
            }
        }
    }

    /// 识别被拖拽的窗口和它原来所在的 cell
    private func initializeDragSource(grid: GridState, primaryH: CGFloat) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let axWindow = windowRef
        else { return }

        sourceAXWindow = (axWindow as! AXUIElement)

        // 读取当前位置
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow as! AXUIElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(axWindow as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }

        initialWindowPos = pos

        // ━━ 在窗口还没移动时确定其 CGWindowID（此时位置匹配可靠）━━
        sourceWindowID = resolveWindowID(pid: frontApp.processIdentifier, position: pos)

        // 优先：从 grid 的 windowIDs 映射表精确查找源 cell
        if let wid = sourceWindowID {
            for (i, gridWID) in grid.windowIDs.enumerated() {
                if gridWID == wid {
                    sourceCellIndex = i
                    print("[DRAG] source cell \(i) from grid.windowIDs for wid=\(wid)")
                    return
                }
            }
        }

        // Fallback：用窗口中心距离匹配（windowIDs 可能还没更新）
        let windowCenter = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, cell) in grid.cellFrames.enumerated() {
            let cellCenter = CGPoint(x: cell.midX, y: cell.midY)
            let dist = hypot(cellCenter.x - windowCenter.x, cellCenter.y - windowCenter.y)
            if dist < bestDist {
                bestDist = dist
                sourceCellIndex = i
            }
        }
        print("[DRAG] source cell \(sourceCellIndex ?? -1) from position fallback")
    }

    /// 通过 pid 从 CGWindowList 确定窗口 ID（找最近的窗口，不要求精确匹配）
    private func resolveWindowID(pid: pid_t, position: CGPoint) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var bestID: CGWindowID?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for info in windowList {
            guard let wPid = info[kCGWindowOwnerPID as String] as? pid_t,
                  wPid == pid,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { continue }
            let wx = boundsDict["X"] ?? 0
            let wy = boundsDict["Y"] ?? 0
            let dist = hypot(wx - position.x, wy - position.y)
            if dist < bestDist {
                bestDist = dist
                bestID = windowID
            }
        }
        // 容差 100px（拖拽开始时窗口可能已移动了一点）
        return bestDist < 100 ? bestID : nil
    }

    private func handleGridDrop() {
        guard let targetIdx = targetCellIndex,
              let grid = WindowManager.shared.activeGrid,
              let sourceAX = sourceAXWindow
        else {
            print("[DROP] GUARD FAIL: targetCell=\(targetCellIndex as Any) grid=\(WindowManager.shared.activeGrid != nil) sourceAX=\(sourceAXWindow != nil)")
            cleanup(); return
        }

        let targetFrame = grid.cellFrames[targetIdx]
        let sourceIdx = sourceCellIndex

        hideOverlay()

        let wm = WindowManager.shared

        let lightWindows = getLightweightWindows()

        // 找到目标 cell 中的所有窗口（排除被拖拽的）
        let occupants = findAllLightWindowsInCell(targetFrame, from: lightWindows, excluding: sourceWindowID)
        print("[DROP] targetIdx=\(targetIdx) sourceIdx=\(sourceIdx as Any) sourceWinID=\(sourceWindowID as Any) occupants=\(occupants.map { $0.id })")

        // 把所有 occupant 移到源 cell（用 CGWindowID 精确匹配 AX 窗口）
        if let srcIdx = sourceIdx, srcIdx < grid.cellFrames.count {
            let swapFrame = grid.cellFrames[srcIdx]
            for occ in occupants {
                let appElement = AXUIElementCreateApplication(occ.pid)
                if let axWin = wm.findAXWindowByCGID(app: appElement, windowID: occ.id) {
                    var pos = swapFrame.origin
                    var size = swapFrame.size
                    AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!)
                    AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
                    print("[DROP] moved occupant \(occ.id) to source cell \(srcIdx)")
                } else {
                    print("[DROP] FAILED: findAXWindowByCGID nil for occupant \(occ.id)")
                }
            }
        }

        // 移动被拖拽窗口到目标 cell
        var pos = targetFrame.origin
        var size = targetFrame.size
        AXUIElementSetAttributeValue(sourceAX, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!)
        AXUIElementSetAttributeValue(sourceAX, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        print("[DROP] moved dragged to target cell \(targetIdx)")

        // ━━ 直接更新 grid.windowIDs（原子 swap，不重新扫描）━━
        if var wids = WindowManager.shared.activeGrid?.windowIDs {
            // 把所有 occupant ID 放到源 cell（只取第一个有意义的）
            if let srcIdx = sourceIdx, srcIdx < wids.count {
                wids[srcIdx] = occupants.first?.id
            }
            // 被拖拽窗口到目标 cell
            if targetIdx < wids.count {
                wids[targetIdx] = sourceWindowID
            }
            WindowManager.shared.activeGrid?.windowIDs = wids
            print("[DROP] windowIDs updated: \(wids)")
        }

        targetCellIndex = nil
        sourceCellIndex = nil
        sourceAXWindow = nil
        sourceWindowID = nil
        dragInitialized = false
        initialWindowPos = nil
        initialMousePos = nil
        isConfirmedWindowDrag = false
        activeZone = nil
    }

    // MARK: - 轻量窗口查找（不需要 AX 遍历）

    /// 轻量窗口信息（只需 CGWindowList，不需要 AX）
    private struct LightWindow {
        let id: CGWindowID
        let pid: pid_t
        let frame: CGRect
    }

    /// 获取所有可见窗口的基础信息（极快，不涉及 AX）
    private func getLightweightWindows() -> [LightWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [LightWindow] = []
        for info in windowList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { continue }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            if ownerName == "GridSnap" || ownerName == "WindowServer" { continue }

            let frame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            guard frame.width > 50 && frame.height > 50 else { continue }

            result.append(LightWindow(id: windowID, pid: pid, frame: frame))
        }
        return result
    }

    /// 在 cell 区域内查找窗口，排除指定 ID
    private func findLightWindowInCell(_ cellFrame: CGRect, from windows: [LightWindow], excluding excludeID: CGWindowID?) -> LightWindow? {
        let expanded = cellFrame.insetBy(dx: -30, dy: -30)
        for w in windows {
            if let exID = excludeID, w.id == exID { continue }
            let center = CGPoint(x: w.frame.midX, y: w.frame.midY)
            if expanded.contains(center) {
                return w
            }
        }
        return nil
    }

    /// 在 cell 区域内查找所有窗口，排除指定 ID
    private func findAllLightWindowsInCell(_ cellFrame: CGRect, from windows: [LightWindow], excluding excludeID: CGWindowID?) -> [LightWindow] {
        let expanded = cellFrame.insetBy(dx: -30, dy: -30)
        var result: [LightWindow] = []
        for w in windows {
            if let exID = excludeID, w.id == exID { continue }
            let center = CGPoint(x: w.frame.midX, y: w.frame.midY)
            if expanded.contains(center) {
                result.append(w)
            }
        }
        return result
    }



    /// 用轻量查询 rebuild grid 状态
    private func rebuildGridStateLightweight() {
        guard let grid = WindowManager.shared.activeGrid else { return }
        let lightWindows = getLightweightWindows()
        var newWindowIDs: [CGWindowID?] = Array(repeating: nil, count: grid.cellFrames.count)

        for (i, cellFrame) in grid.cellFrames.enumerated() {
            if let w = findLightWindowInCell(cellFrame, from: lightWindows, excluding: nil) {
                newWindowIDs[i] = w.id
            }
        }

        WindowManager.shared.activeGrid?.windowIDs = newWindowIDs
    }

    // MARK: - 屏幕边缘吸附 (Fallback — 无网格时)

    private func handleEdgeDrag(at point: NSPoint) {
        let sensitivity = CGFloat(Preferences.shared.snapSensitivity)

        // 首次拖拽：记录初始位置（AX 只在初始化时调一次）
        if !dragInitialized {
            dragInitialized = true
            initialMousePos = point
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
                var windowRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
                   let axWindow = windowRef {
                    sourceAXWindow = (axWindow as! AXUIElement)
                }
            }
        }

        // 用鼠标移动距离判断（零 AX 调用）
        if !isConfirmedWindowDrag {
            if let initMouse = initialMousePos {
                let moved = hypot(point.x - initMouse.x, point.y - initMouse.y)
                if moved < dragThreshold { return }
            }
            isConfirmedWindowDrag = true
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            hideOverlay()
            activeZone = nil
            return
        }

        var detectedZone: SnapZone?
        let sortedZones = SnapZone.allCases.sorted { $0.priority < $1.priority }
        for zone in sortedZones {
            if zone.triggerRect(for: screen, sensitivity: sensitivity).contains(point) {
                detectedZone = zone
                break
            }
        }

        if let zone = detectedZone {
            if zone != activeZone {
                activeZone = zone
                let targetFrame = zone.frame(for: screen)
                hideOverlay()
                overlay = SnapOverlayWindow(frame: targetFrame, on: screen)
                overlay?.show()
            }
        } else {
            if activeZone != nil {
                activeZone = nil
                hideOverlay()
            }
        }
    }

    private func handleEdgeDrop(at point: NSPoint) {
        guard let zone = activeZone else { cleanup(); return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { cleanup(); return }

        let targetFrame = zone.frame(for: screen)
        cleanup()

        guard let mainScreen = NSScreen.screens.first else { return }
        let screenHeight = mainScreen.frame.height
        let cgFrame = CGRect(
            x: targetFrame.origin.x,
            y: screenHeight - targetFrame.origin.y - targetFrame.height,
            width: targetFrame.width,
            height: targetFrame.height
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
            let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

            var windowRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
                  let axWindow = windowRef
            else { return }

            var position = cgFrame.origin
            var size = cgFrame.size

            if let posValue = AXValueCreate(.cgPoint, &position) {
                AXUIElementSetAttributeValue(axWindow as! AXUIElement, kAXPositionAttribute as CFString, posValue)
            }
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(axWindow as! AXUIElement, kAXSizeAttribute as CFString, sizeValue)
            }
        }
    }

    // MARK: - Helpers

    /// 获取当前屏幕上所有活跃窗口的 ID 集合
    private func getLiveWindowIDs() -> Set<CGWindowID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids = Set<CGWindowID>()
        for info in windowList {
            if let wid = info[kCGWindowNumber as String] as? CGWindowID,
               let layer = info[kCGWindowLayer as String] as? Int, layer == 0 {
                ids.insert(wid)
            }
        }
        return ids
    }

    private func cleanup() {
        targetCellIndex = nil
        sourceCellIndex = nil
        sourceAXWindow = nil
        sourceWindowID = nil
        dragInitialized = false
        initialWindowPos = nil
        initialMousePos = nil
        isConfirmedWindowDrag = false
        activeZone = nil
        lastDragTime = 0
        hideOverlay()
    }

    private func hideOverlay() {
        overlay?.dismiss()
        overlay = nil
    }
}
