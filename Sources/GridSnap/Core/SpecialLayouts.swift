import Foundation

// MARK: - 特殊布局

/// 1+2 布局: 左边 1 大窗口，右边上下两个窗口
/// ┌─────┬─────┐
/// │     │  2  │
/// │  1  ├─────┤
/// │     │  3  │
/// └─────┴─────┘
struct Layout1Plus2: LayoutStrategy {
    let config: GridConfig
    var name: String { "1+2" }

    init(config: GridConfig = GridConfig()) {
        self.config = config
    }

    func calculateFrames(windowCount: Int, in rect: CGRect) -> [CGRect] {
        let pad = config.padding
        let gap = config.gap
        let count = min(windowCount, 3)

        let areaX = rect.origin.x + pad
        let areaY = rect.origin.y + pad
        let areaW = rect.width - 2 * pad
        let areaH = rect.height - 2 * pad

        // 左边占一半宽
        let leftW = (areaW - gap) / 2
        let rightW = areaW - leftW - gap
        let halfH = (areaH - gap) / 2

        var frames: [CGRect] = []

        // 1: 左边全高
        frames.append(CGRect(x: areaX, y: areaY, width: leftW, height: areaH))

        if count >= 2 {
            // 2: 右上 (NSScreen: y 大 = 上)
            frames.append(CGRect(x: areaX + leftW + gap, y: areaY + halfH + gap, width: rightW, height: halfH))
        }
        if count >= 3 {
            // 3: 右下
            frames.append(CGRect(x: areaX + leftW + gap, y: areaY, width: rightW, height: halfH))
        }

        return frames
    }
}

/// 1+3 布局: 左边 1 大窗口，右边三个窗口
/// ┌─────┬─────┐
/// │     │  2  │
/// │  1  ├─────┤
/// │     │  3  │
/// │     ├─────┤
/// │     │  4  │
/// └─────┴─────┘
struct Layout1Plus3: LayoutStrategy {
    let config: GridConfig
    var name: String { "1+3" }

    init(config: GridConfig = GridConfig()) {
        self.config = config
    }

    func calculateFrames(windowCount: Int, in rect: CGRect) -> [CGRect] {
        let pad = config.padding
        let gap = config.gap
        let count = min(windowCount, 4)

        let areaX = rect.origin.x + pad
        let areaY = rect.origin.y + pad
        let areaW = rect.width - 2 * pad
        let areaH = rect.height - 2 * pad

        let leftW = (areaW - gap) / 2
        let rightW = areaW - leftW - gap
        let thirdH = (areaH - 2 * gap) / 3

        var frames: [CGRect] = []

        // 1: 左边全高
        frames.append(CGRect(x: areaX, y: areaY, width: leftW, height: areaH))

        if count >= 2 {
            // 2: 右上
            frames.append(CGRect(x: areaX + leftW + gap, y: areaY + 2 * (thirdH + gap), width: rightW, height: thirdH))
        }
        if count >= 3 {
            // 3: 右中
            frames.append(CGRect(x: areaX + leftW + gap, y: areaY + thirdH + gap, width: rightW, height: thirdH))
        }
        if count >= 4 {
            // 4: 右下
            frames.append(CGRect(x: areaX + leftW + gap, y: areaY, width: rightW, height: thirdH))
        }

        return frames
    }
}

/// 2+3 布局: 上面 2 个窗口，下面 3 个窗口
/// ┌───┬───┐
/// │ 1 │ 2 │
/// ├───┼───┼───┤
/// │ 3 │ 4 │ 5 │
/// └───┴───┴───┘
struct Layout2Plus3: LayoutStrategy {
    let config: GridConfig
    var name: String { "2+3" }

    init(config: GridConfig = GridConfig()) {
        self.config = config
    }

    func calculateFrames(windowCount: Int, in rect: CGRect) -> [CGRect] {
        let pad = config.padding
        let gap = config.gap
        let count = min(windowCount, 5)

        let areaX = rect.origin.x + pad
        let areaY = rect.origin.y + pad
        let areaW = rect.width - 2 * pad
        let areaH = rect.height - 2 * pad

        let halfH = (areaH - gap) / 2
        let halfW = (areaW - gap) / 2
        let thirdW = (areaW - 2 * gap) / 3

        var frames: [CGRect] = []

        // 上面两个 (NSScreen: y 大 = 上)
        // 1: 左上
        frames.append(CGRect(x: areaX, y: areaY + halfH + gap, width: halfW, height: halfH))

        if count >= 2 {
            // 2: 右上
            frames.append(CGRect(x: areaX + halfW + gap, y: areaY + halfH + gap, width: halfW, height: halfH))
        }

        // 下面三个
        if count >= 3 {
            // 3: 左下
            frames.append(CGRect(x: areaX, y: areaY, width: thirdW, height: halfH))
        }
        if count >= 4 {
            // 4: 中下
            frames.append(CGRect(x: areaX + thirdW + gap, y: areaY, width: thirdW, height: halfH))
        }
        if count >= 5 {
            // 5: 右下
            frames.append(CGRect(x: areaX + 2 * (thirdW + gap), y: areaY, width: thirdW, height: halfH))
        }

        return frames
    }
}

// MARK: - 布局注册表

/// 所有可用的布局
enum LayoutRegistry {
    static func grid(_ rows: Int, _ cols: Int) -> LayoutStrategy {
        GridLayout(rows: rows, cols: cols)
    }

    static let auto = AutoGridLayout()
    static let oneTwo = Layout1Plus2()
    static let oneThree = Layout1Plus3()
    static let twoThree = Layout2Plus3()

    /// 默认快捷键与布局的映射
    static let defaultBindings: [(key: String, layout: LayoutStrategy)] = [
        ("1", grid(2, 2)),    // ⌘⇧1 = 2×2
        ("2", grid(2, 3)),    // ⌘⇧2 = 2×3
        ("3", grid(2, 4)),    // ⌘⇧3 = 2×4
        ("4", oneTwo),        // ⌘⇧4 = 1+2
        ("5", oneThree),      // ⌘⇧5 = 1+3
        ("6", twoThree),      // ⌘⇧6 = 2+3
        ("g", auto),          // ⌘⇧G = 自动
    ]
}
