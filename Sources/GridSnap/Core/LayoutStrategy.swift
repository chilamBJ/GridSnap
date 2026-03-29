import Foundation

/// 布局策略协议 — 所有布局（标准网格、特殊布局）都实现此协议
protocol LayoutStrategy {
    /// 布局名称
    var name: String { get }

    /// 计算每个窗口的目标 frame
    /// - Parameters:
    ///   - windowCount: 需要排列的窗口数量
    ///   - availableRect: 可用区域 (NSScreen.visibleFrame)
    /// - Returns: 每个窗口的目标 CGRect（NSScreen 坐标系，左下原点）
    func calculateFrames(windowCount: Int, in availableRect: CGRect) -> [CGRect]
}

/// 标准网格布局参数
struct GridConfig {
    var padding: CGFloat = 8
    var gap: CGFloat = 6
}
