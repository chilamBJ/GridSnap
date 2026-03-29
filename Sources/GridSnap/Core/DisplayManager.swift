import AppKit

/// 多显示器管理
final class DisplayManager {
    static let shared = DisplayManager()

    /// 当前鼠标所在的显示器
    var currentScreen: NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// 所有显示器
    var allScreens: [NSScreen] {
        NSScreen.screens
    }

    /// 显示器数量
    var screenCount: Int {
        NSScreen.screens.count
    }
}
