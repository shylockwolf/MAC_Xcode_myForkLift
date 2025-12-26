import Foundation
import Combine

/// 文件选择状态管理器
class FileSelectionState: ObservableObject {
    @Published var rangeSelectionAnchor: URL? = nil
    @Published var lastShiftClickItem: URL? = nil
    @Published var lastTapTime: Date = Date.distantPast
    @Published var lastTapItem: URL? = nil
    
    // 重置所有状态
    func reset() {
        rangeSelectionAnchor = nil
        lastShiftClickItem = nil
        lastTapTime = Date.distantPast
        lastTapItem = nil
    }
    
    // 设置锚点
    func setAnchor(_ url: URL) {
        rangeSelectionAnchor = url
        print("🔑 FileSelectionState: Set anchor to \(url.lastPathComponent)")
    }
    
    // 获取锚点信息
    func getAnchorInfo() -> String {
        return rangeSelectionAnchor?.lastPathComponent ?? "NONE"
    }
}