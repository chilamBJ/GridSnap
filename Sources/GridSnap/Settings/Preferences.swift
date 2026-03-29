import Foundation
import ServiceManagement

/// 用户偏好设置
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    /// 开机自启
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    /// 通过 SMAppService 注册/取消开机自启
    private func updateLoginItem() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("GridSnap: 设置开机自启失败 — \(error.localizedDescription)")
        }
    }

    /// 排列动画模式: "instant" | "smooth"
    @Published var animationMode: String {
        didSet { defaults.set(animationMode, forKey: "animationMode") }
    }

    /// 排列范围: "current" (当前屏幕) | "all" (所有屏幕)
    @Published var arrangeScope: String {
        didSet { defaults.set(arrangeScope, forKey: "arrangeScope") }
    }

    /// 截屏默认输出: "clipboard" | "file"
    @Published var screenshotOutput: String {
        didSet { defaults.set(screenshotOutput, forKey: "screenshotOutput") }
    }

    /// 截屏保存路径
    @Published var screenshotSavePath: String {
        didSet { defaults.set(screenshotSavePath, forKey: "screenshotSavePath") }
    }

    /// 截图格式: "png" | "jpeg"
    @Published var screenshotFormat: String {
        didSet { defaults.set(screenshotFormat, forKey: "screenshotFormat") }
    }

    /// JPEG 质量 (0.0 ~ 1.0)
    @Published var screenshotQuality: Double {
        didSet { defaults.set(screenshotQuality, forKey: "screenshotQuality") }
    }

    /// 排列动画时长 (秒)
    @Published var animationDuration: Double {
        didSet { defaults.set(animationDuration, forKey: "animationDuration") }
    }

    /// 磁吸吸附开关
    @Published var snapEnabled: Bool {
        didSet { defaults.set(snapEnabled, forKey: "snapEnabled") }
    }

    /// 磁吸灵敏度 (像素)
    @Published var snapSensitivity: Int {
        didSet { defaults.set(snapSensitivity, forKey: "snapSensitivity") }
    }

    private init() {
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.animationMode = defaults.string(forKey: "animationMode") ?? "instant"
        self.arrangeScope = defaults.string(forKey: "arrangeScope") ?? "current"
        self.screenshotOutput = defaults.string(forKey: "screenshotOutput") ?? "clipboard"
        self.screenshotSavePath = defaults.string(forKey: "screenshotSavePath")
            ?? NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? "~/Desktop"
        self.animationDuration = defaults.object(forKey: "animationDuration") as? Double ?? 0.3
        self.snapEnabled = defaults.object(forKey: "snapEnabled") as? Bool ?? true
        self.snapSensitivity = defaults.object(forKey: "snapSensitivity") as? Int ?? 12
        self.screenshotFormat = defaults.string(forKey: "screenshotFormat") ?? "jpeg"
        self.screenshotQuality = defaults.object(forKey: "screenshotQuality") as? Double ?? 0.8
    }
}
