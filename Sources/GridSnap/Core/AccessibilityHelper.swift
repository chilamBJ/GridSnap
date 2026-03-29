import AppKit
import ApplicationServices

/// 辅助功能权限管理
enum AccessibilityHelper {

    /// 检查是否有辅助功能权限
    static func checkAccess(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 显示权限引导弹窗
    static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "GridSnap 需要辅助功能权限"
        alert.informativeText = "请在 系统设置 → 隐私与安全性 → 辅助功能 中，添加并勾选 GridSnap。\n\n授权后重新启动 GridSnap 即可使用。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    /// 打开系统设置 > 辅助功能页面
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
