import Carbon
import AppKit

/// 全局快捷键管理器
/// 使用 Carbon Event API 注册系统级热键
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var callbacks: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    private init() {
        installEventHandler()
    }

    deinit {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
    }

    // MARK: - 注册默认快捷键

    func registerDefaults() {
        let wm = WindowManager.shared
        let dm = DisplayManager.shared

        // ⌃⌥1 = 2×2
        register(modifiers: [.control, .option], key: kVK_ANSI_1) {
            wm.arrangeWindows(using: GridLayout(rows: 2, cols: 2), on: dm.currentScreen)
        }

        // ⌃⌥2 = 2×3
        register(modifiers: [.control, .option], key: kVK_ANSI_2) {
            wm.arrangeWindows(using: GridLayout(rows: 2, cols: 3), on: dm.currentScreen)
        }

        // ⌃⌥3 = 2×4
        register(modifiers: [.control, .option], key: kVK_ANSI_3) {
            wm.arrangeWindows(using: GridLayout(rows: 2, cols: 4), on: dm.currentScreen)
        }

        // ⌃⌥4 = 1+2
        register(modifiers: [.control, .option], key: kVK_ANSI_4) {
            wm.arrangeWindows(using: Layout1Plus2(), on: dm.currentScreen)
        }

        // ⌃⌥5 = 1+3
        register(modifiers: [.control, .option], key: kVK_ANSI_5) {
            wm.arrangeWindows(using: Layout1Plus3(), on: dm.currentScreen)
        }

        // ⌃⌥6 = 2+3
        register(modifiers: [.control, .option], key: kVK_ANSI_6) {
            wm.arrangeWindows(using: Layout2Plus3(), on: dm.currentScreen)
        }

        // ⌃⌥G = 自动最佳网格
        register(modifiers: [.control, .option], key: kVK_ANSI_G) {
            wm.arrangeWindows(using: AutoGridLayout(), on: dm.currentScreen)
        }

        // ⌃⌥S = 截屏模式
        register(modifiers: [.control, .option], key: kVK_ANSI_S) {
            CaptureManager.shared.startCapture(mode: .region)
        }

        // ⌃⌥R = 录屏
        register(modifiers: [.control, .option], key: kVK_ANSI_R) {
            ScreenRecorder.shared.toggleRecording()
        }
    }

    // MARK: - 注册快捷键

    struct Modifier: OptionSet {
        let rawValue: UInt32
        static let command  = Modifier(rawValue: UInt32(cmdKey))
        static let shift    = Modifier(rawValue: UInt32(shiftKey))
        static let option   = Modifier(rawValue: UInt32(optionKey))
        static let control  = Modifier(rawValue: UInt32(controlKey))
    }

    func register(modifiers: Modifier, key: Int, action: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        callbacks[id] = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x4753), // "GS" for GridSnap
                                      id: id)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(key),
            modifiers.rawValue,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
        } else {
            print("GridSnap: 注册快捷键失败, key=\(key), status=\(status)")
        }
    }

    // MARK: - Carbon Event Handler

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else { return status }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            if let callback = manager.callbacks[hotKeyID.id] {
                DispatchQueue.main.async {
                    callback()
                }
            }

            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }
}
