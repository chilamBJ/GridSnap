import Foundation

/// 标准网格布局：rows × cols 均匀分割
struct GridLayout: LayoutStrategy {
    let rows: Int
    let cols: Int
    let config: GridConfig

    var name: String { "\(rows)×\(cols)" }

    init(rows: Int, cols: Int, config: GridConfig = GridConfig()) {
        self.rows = rows
        self.cols = cols
        self.config = config
    }

    func calculateFrames(windowCount: Int, in rect: CGRect) -> [CGRect] {
        let all = allCellFrames(in: rect)
        return Array(all.prefix(min(windowCount, all.count)))
    }

    /// 生成完整网格的所有 cell frame（rows × cols 个）
    func allCellFrames(in rect: CGRect) -> [CGRect] {
        let pad = config.padding
        let gap = config.gap

        let areaX = rect.origin.x + pad
        let areaY = rect.origin.y + pad
        let areaW = rect.width - 2 * pad
        let areaH = rect.height - 2 * pad

        let cellW = (areaW - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let cellH = (areaH - CGFloat(rows - 1) * gap) / CGFloat(rows)

        var frames: [CGRect] = []
        for i in 0..<(rows * cols) {
            let row = i / cols
            let col = i % cols
            let x = areaX + CGFloat(col) * (cellW + gap)
            let y = areaY + CGFloat(rows - 1 - row) * (cellH + gap)
            frames.append(CGRect(x: x, y: y, width: cellW, height: cellH))
        }
        return frames
    }
}

/// 自动网格：根据窗口数量自动选择最佳网格
struct AutoGridLayout: LayoutStrategy {
    let config: GridConfig

    var name: String { "自动" }

    init(config: GridConfig = GridConfig()) {
        self.config = config
    }

    func calculateFrames(windowCount: Int, in rect: CGRect) -> [CGRect] {
        let (rows, cols) = Self.bestGrid(for: windowCount)
        let grid = GridLayout(rows: rows, cols: cols, config: config)
        return grid.calculateFrames(windowCount: windowCount, in: rect)
    }

    /// 根据窗口数量选最佳网格
    static func bestGrid(for count: Int) -> (rows: Int, cols: Int) {
        switch count {
        case 0...1: return (1, 1)
        case 2:     return (1, 2)
        case 3...4: return (2, 2)
        case 5...6: return (2, 3)
        case 7...8: return (2, 4)
        case 9:     return (3, 3)
        case 10...12: return (3, 4)
        default:    return (4, 4)
        }
    }
}
