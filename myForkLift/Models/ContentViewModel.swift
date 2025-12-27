import Foundation
import Combine
import AppKit

/// 当前激活的面板
enum Pane {
    case left
    case right
}

/// `ContentView` 对应的视图模型，负责管理与面板、选择和刷新相关的状态
final class ContentViewModel: ObservableObject {
    /// 当前激活的面板
    @Published var activePane: Pane = .left
    
    /// 是否显示隐藏文件
    @Published var leftShowHiddenFiles: Bool = false
    @Published var rightShowHiddenFiles: Bool = false
    
    /// 选中的文件/目录
    @Published var leftSelectedItems: Set<URL> = []
    @Published var rightSelectedItems: Set<URL> = []
    
    /// 文件选择状态管理器
    @Published var leftSelectionState: FileSelectionState = FileSelectionState()
    @Published var rightSelectionState: FileSelectionState = FileSelectionState()
    
    /// 用于触发文件列表刷新的标记
    @Published var refreshTrigger: UUID = UUID()
    
    /// 从菜单打开的文件列表
    @Published var openedFiles: [URL] = []
    
    // MARK: - 目录历史记录管理
    
    /// 历史记录最大长度
    private let maxHistoryLength = 20
    
    /// 左侧面板目录历史记录
    private var leftHistory: [URL] = []
    /// 左侧面板当前历史记录索引
    private var leftHistoryIndex: Int = -1
    
    /// 右侧面板目录历史记录
    private var rightHistory: [URL] = []
    /// 右侧面板当前历史记录索引
    private var rightHistoryIndex: Int = -1
    
    // UserDefaults 键（窗口路径、位置和显示选项）
    let favoritesKey = "DWBrowserFavorites"
    let leftPaneURLKey = "DWBrowserLeftPaneURL"
    let rightPaneURLKey = "DWBrowserRightPaneURL"
    let windowPositionKey = "DWBrowserWindowPosition"
    let windowSizeKey = "DWBrowserWindowSize"
    let leftShowFileTypeKey = "DWBrowserLeftShowFileType"
    let leftShowFileSizeKey = "DWBrowserLeftShowFileSize"
    let leftShowFileDateKey = "DWBrowserLeftShowFileDate"
    let rightShowFileTypeKey = "DWBrowserRightShowFileType"
    let rightShowFileSizeKey = "DWBrowserRightShowFileSize"
    let rightShowFileDateKey = "DWBrowserRightShowFileDate"
    let openedFilesKey = "DWBrowserOpenedFiles"
    
    // MARK: - 窗口路径与状态持久化
    
    /// 保存左右面板当前路径
    func saveWindowPaths(leftPaneURL: URL, rightPaneURL: URL) {
        let leftPath = leftPaneURL.path
        let rightPath = rightPaneURL.path
        
        let leftType = "本地"
        let rightType = "本地"
        
        UserDefaults.standard.set(leftPath, forKey: leftPaneURLKey)
        UserDefaults.standard.set(rightPath, forKey: rightPaneURLKey)
        
        // 验证保存是否成功
        if let savedLeft = UserDefaults.standard.string(forKey: leftPaneURLKey),
           let savedRight = UserDefaults.standard.string(forKey: rightPaneURLKey) {
        } else {
        }
    }
    
    /// 从 UserDefaults 加载左右面板路径，如果不存在则返回传入的默认值
    func loadWindowPaths(
        defaultLeft: URL,
        defaultRight: URL
    ) -> (left: URL, right: URL) {
        
        guard let leftPath = UserDefaults.standard.string(forKey: leftPaneURLKey),
              let rightPath = UserDefaults.standard.string(forKey: rightPaneURLKey) else {
            return (defaultLeft, defaultRight)
        }
        
        
        // 处理路径格式问题
        let cleanLeftPath = leftPath.hasPrefix("//") ? String(leftPath.dropFirst()) : leftPath
        let cleanRightPath = rightPath.hasPrefix("//") ? String(rightPath.dropFirst()) : rightPath
        
        let leftURL = URL(fileURLWithPath: cleanLeftPath)
        let rightURL = URL(fileURLWithPath: cleanRightPath)
        
        

        
        var finalLeft = defaultLeft
        var finalRight = defaultRight
        
        // 验证左路径是否存在
        if FileManager.default.fileExists(atPath: leftURL.path) {
            finalLeft = leftURL
        } else {
        }
        
        // 验证右路径是否存在
        if FileManager.default.fileExists(atPath: rightURL.path) {
            finalRight = rightURL
        } else {
        }
        
        return (finalLeft, finalRight)
    }
    
    /// 保存窗口位置和大小
    func saveWindowFrame(_ frame: NSRect) {
        let position = frame.origin
        let size = frame.size
        
        UserDefaults.standard.set(["x": position.x, "y": position.y], forKey: windowPositionKey)
        UserDefaults.standard.set(["width": size.width, "height": size.height], forKey: windowSizeKey)
        
    }
    
    /// 从 UserDefaults 读取窗口位置和大小并应用到窗口
    func restoreWindowFrame(for window: NSWindow) {
        // 加载位置
        if let positionDict = UserDefaults.standard.dictionary(forKey: windowPositionKey),
           let x = positionDict["x"] as? CGFloat,
           let y = positionDict["y"] as? CGFloat {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // 加载大小
        if let sizeDict = UserDefaults.standard.dictionary(forKey: windowSizeKey),
           let width = sizeDict["width"] as? CGFloat,
           let height = sizeDict["height"] as? CGFloat {
            var newFrame = window.frame
            newFrame.size = NSSize(width: width, height: height)
            window.setFrame(newFrame, display: true)
        }
        
    }
    
    /// 保存文件信息显示选项
    func saveFileDisplayOptions(
        leftShowFileSize: Bool,
        leftShowFileDate: Bool,
        leftShowFileType: Bool,
        rightShowFileSize: Bool,
        rightShowFileDate: Bool,
        rightShowFileType: Bool
    ) {
        UserDefaults.standard.set(leftShowFileSize, forKey: leftShowFileSizeKey)
        UserDefaults.standard.set(leftShowFileDate, forKey: leftShowFileDateKey)
        UserDefaults.standard.set(leftShowFileType, forKey: leftShowFileTypeKey)
        
        UserDefaults.standard.set(rightShowFileSize, forKey: rightShowFileSizeKey)
        UserDefaults.standard.set(rightShowFileDate, forKey: rightShowFileDateKey)
        UserDefaults.standard.set(rightShowFileType, forKey: rightShowFileTypeKey)
        
    }
    
    /// 保存打开的文件列表
    func saveOpenedFiles() {
        let filePaths = openedFiles.map { $0.path }
        UserDefaults.standard.set(filePaths, forKey: openedFilesKey)
    }
    
    /// 加载打开的文件列表
    func loadOpenedFiles() {
        if let savedPaths = UserDefaults.standard.array(forKey: openedFilesKey) as? [String] {
            openedFiles = savedPaths.compactMap { path in
                let url = URL(fileURLWithPath: path)
                // 只加载存在的文件
                if FileManager.default.fileExists(atPath: path) {
                    return url
                } else {
                    return nil
                }
            }
        } else {
        }
    }
    
    /// 从 UserDefaults 加载文件信息显示选项
    func loadFileDisplayOptions(
        leftShowFileSize: inout Bool,
        leftShowFileDate: inout Bool,
        leftShowFileType: inout Bool,
        rightShowFileSize: inout Bool,
        rightShowFileDate: inout Bool,
        rightShowFileType: inout Bool
    ) {
        leftShowFileSize = UserDefaults.standard.bool(forKey: leftShowFileSizeKey)
        leftShowFileDate = UserDefaults.standard.bool(forKey: leftShowFileDateKey)
        leftShowFileType = UserDefaults.standard.bool(forKey: leftShowFileTypeKey)
        
        rightShowFileSize = UserDefaults.standard.bool(forKey: rightShowFileSizeKey)
        rightShowFileDate = UserDefaults.standard.bool(forKey: rightShowFileDateKey)
        rightShowFileType = UserDefaults.standard.bool(forKey: rightShowFileTypeKey)
        
    }
    
    // MARK: - 选择相关
    
    /// 获取当前激活面板的所有选中项
    func getCurrentSelectedItems() -> Set<URL> {
        let result: Set<URL>
        switch activePane {
        case .left:
            result = leftSelectedItems
        case .right:
            result = rightSelectedItems
        }
        return result
    }
    
    /// 获取当前激活面板的任意一个选中项（兼容旧代码）
    func getCurrentSelectedItem() -> URL? {
        return getCurrentSelectedItems().first
    }
    
    /// 将选中的文件/文件夹复制到系统剪贴板
    func copySelectedItemsToClipboard() {
        let selectedItems = getCurrentSelectedItems()
        guard !selectedItems.isEmpty else {
            return
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsUrls = selectedItems.map { $0 as NSURL }
        _ = pasteboard.writeObjects(nsUrls)
    }
    
    /// 清空两个面板的所有选中状态
    func clearAllSelections() {
        leftSelectedItems.removeAll()
        rightSelectedItems.removeAll()
    }
    
    /// 设置当前激活面板，并自动清空另一个面板的选中状态
    func setActivePane(_ pane: Pane) {
        
        activePane = pane
        
        // 清空非激活面板的选择状态，但保留当前激活面板的选择
        switch pane {
        case .left:
            if !rightSelectedItems.isEmpty {
                rightSelectedItems.removeAll()
            }
        case .right:
            if !leftSelectedItems.isEmpty {
                leftSelectedItems.removeAll()
            }
        }
        
    }
    
    /// 触发文件列表刷新
    func triggerRefresh() {
        refreshTrigger = UUID()
    }
    
    /// 从系统剪贴板获取文件URLs
    func getURLsFromClipboard() -> [URL] {
        let pasteboard = NSPasteboard.general
        guard let nsUrls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL] else {
            return []
        }
        return nsUrls.map { $0 as URL }
    }
    
    /// 将剪贴板中的文件粘贴到指定目录
    func pasteItemsToDirectory(_ targetDirectory: URL) -> (success: Bool, message: String) {
        let urlsToPaste = getURLsFromClipboard()
        guard !urlsToPaste.isEmpty else {
            return (false, "剪贴板中没有可粘贴的文件")
        }
        
        let fileManager = FileManager.default
        var successCount = 0
        var errorCount = 0
        
        for sourceURL in urlsToPaste {
            let fileName = sourceURL.lastPathComponent
            let destinationURL = targetDirectory.appendingPathComponent(fileName)
            
            // 检查目标文件是否已存在
            if fileManager.fileExists(atPath: destinationURL.path) {
                // 如果目标文件已存在，添加一个数字后缀
                let fileExtension = sourceURL.pathExtension
                let fileNameWithoutExtension = fileExtension.isEmpty ? 
                    sourceURL.deletingPathExtension().lastPathComponent : 
                    sourceURL.deletingPathExtension().lastPathComponent
                
                var counter = 1
                var uniqueDestinationURL: URL
                
                repeat {
                    let newFileName = fileExtension.isEmpty ? 
                        "\(fileNameWithoutExtension) \(counter)" : 
                        "\(fileNameWithoutExtension) \(counter).\(fileExtension)"
                    uniqueDestinationURL = targetDirectory.appendingPathComponent(newFileName)
                    counter += 1
                } while fileManager.fileExists(atPath: uniqueDestinationURL.path)
                
                do {
                    try fileManager.copyItem(at: sourceURL, to: uniqueDestinationURL)
                    successCount += 1
                } catch {
                    errorCount += 1
                }
            } else {
                do {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                    successCount += 1
                } catch {
                    errorCount += 1
                }
            }
        }
        
        if successCount > 0 && errorCount == 0 {
            return (true, "已成功粘贴\(successCount)个项目")
        } else if successCount > 0 && errorCount > 0 {
            return (false, "部分粘贴成功：\(successCount)个项目成功，\(errorCount)个项目失败")
        } else {
            return (false, "所有项目粘贴失败")
        }
    }
    
    /// 将剪贴板中的文件粘贴到当前激活的面板目录
    func pasteItemsToCurrentActivePane(leftURL: URL, rightURL: URL) -> (success: Bool, message: String) {
        let targetDirectory = activePane == .left ? leftURL : rightURL
        return pasteItemsToDirectory(targetDirectory)
    }
    
    // MARK: - 目录历史记录管理方法
    
    /// 将URL添加到指定面板的历史记录
    func addToHistory(url: URL, for pane: Pane) {
        switch pane {
        case .left:
            // 如果当前不是最新的历史记录，截断历史记录
            if leftHistoryIndex < leftHistory.count - 1 {
                leftHistory = Array(leftHistory[0...leftHistoryIndex])
            }
            
            // 如果URL与当前历史记录最后一项相同，不重复添加
            if let lastURL = leftHistory.last, lastURL == url {
                return
            }
            
            // 添加新URL
            leftHistory.append(url)
            leftHistoryIndex = leftHistory.count - 1
            
            // 限制历史记录长度
            if leftHistory.count > maxHistoryLength {
                leftHistory.removeFirst()
                leftHistoryIndex -= 1
            }
            
        case .right:
            // 如果当前不是最新的历史记录，截断历史记录
            if rightHistoryIndex < rightHistory.count - 1 {
                rightHistory = Array(rightHistory[0...rightHistoryIndex])
            }
            
            // 如果URL与当前历史记录最后一项相同，不重复添加
            if let lastURL = rightHistory.last, lastURL == url {
                return
            }
            
            // 添加新URL
            rightHistory.append(url)
            rightHistoryIndex = rightHistory.count - 1
            
            // 限制历史记录长度
            if rightHistory.count > maxHistoryLength {
                rightHistory.removeFirst()
                rightHistoryIndex -= 1
            }
        }
    }
    
    /// 返回指定面板的上一个目录
    func goBackInHistory(for pane: Pane) -> URL? {
        switch pane {
        case .left:
            if canGoBack(for: .left) {
                leftHistoryIndex -= 1
                return leftHistory[leftHistoryIndex]
            }
            return nil
            
        case .right:
            if canGoBack(for: .right) {
                rightHistoryIndex -= 1
                return rightHistory[rightHistoryIndex]
            }
            return nil
        }
    }
    
    /// 检查指定面板是否可以返回上一个目录
    func canGoBack(for pane: Pane) -> Bool {
        switch pane {
        case .left:
            return leftHistoryIndex > 0
        case .right:
            return rightHistoryIndex > 0
        }
    }
    
    /// 初始化历史记录（应用启动或重置时调用）
    func initializeHistory(leftURL: URL, rightURL: URL) {
        leftHistory = [leftURL]
        leftHistoryIndex = 0
        rightHistory = [rightURL]
        rightHistoryIndex = 0
    }
}


