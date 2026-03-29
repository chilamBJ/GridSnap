import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var permissionCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为纯菜单栏应用（不显示 Dock 图标）
        NSApp.setActivationPolicy(.accessory)

        // 检查辅助功能权限
        let hasPerm = AccessibilityHelper.checkAccess(prompt: true)
        gsLog("[GridSnap] 辅助功能权限: \(hasPerm)")

        if hasPerm {
            finishSetup()
        } else {
            // 弹窗引导 + 轮询等待用户授权
            AccessibilityHelper.showPermissionAlert()
            startPermissionPolling()
        }

        gsLog("GridSnap 启动完成")
    }

    /// 权限获得后完成初始化
    private func finishSetup() {
        guard hotkeyManager == nil else { return } // 避免重复初始化
        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.registerDefaults()
        SnapZoneManager.shared.start()
        gsLog("[GridSnap] 快捷键和磁吸已初始化")
    }

    /// 轮询检查辅助功能权限（用户在系统设置中授权后自动完成初始化）
    private func startPermissionPolling() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            if AccessibilityHelper.checkAccess(prompt: false) {
                gsLog("[GridSnap] 辅助功能权限已获取")
                timer.invalidate()
                self?.permissionCheckTimer = nil
                self?.finishSetup()
            }
        }
    }
}
