//
//  FileBrowserPane.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import SwiftUI
import Foundation
import AppKit
import Combine

/// 排序字段枚举
enum SortField {
    case name
    case type
    case size
    case date
}

/// 文件浏览器面板
struct FileBrowserPane: View {
    @Binding var currentURL: URL
    @Binding var showHiddenFiles: Bool
    @Binding var selectedItems: Set<URL>
    let isActive: Bool
    let onActivate: () -> Void
    let refreshTrigger: UUID
    let panelId: String // 用于识别是左面板还是右面板
    @ObservedObject var selectionState: FileSelectionState
    @State private var items: [URL] = []
    @State private var cancellables = Set<AnyCancellable>()
    @State private var keyboardFocusView: NSView?
    @State private var isKeyboardSelection: Bool = false
    
    /// 处理键盘输入，定位到对应字母开头的文件
    func handleKeyPress(_ key: String) {
        guard !items.isEmpty else { return }
        
        // 查找以输入字母开头的第一个文件或文件夹
        let lowercaseKey = key.lowercased()
        
        // 从当前选中项的下一个位置开始搜索，实现循环导航
        let startIndex = selectedItems.first.flatMap { items.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        
        // 先查找从startIndex开始的匹配项
        if let targetIndex = findItemByKey(key: lowercaseKey, startIndex: startIndex) {
            let targetItem = items[targetIndex]
            isKeyboardSelection = true
            selectedItems = [targetItem]
            selectionState.lastShiftClickItem = targetItem
            return
        }
        
        // 如果没找到，从开头开始搜索（循环）
        if let targetIndex = findItemByKey(key: lowercaseKey, startIndex: 0) {
            let targetItem = items[targetIndex]
            isKeyboardSelection = true
            selectedItems = [targetItem]
            selectionState.lastShiftClickItem = targetItem
        }
    }
    
    /// 根据按键查找项目的辅助函数
    private func findItemByKey(key: String, startIndex: Int) -> Int? {
        for i in startIndex..<items.count {
            let name = items[i].lastPathComponent.lowercased()
            if name.hasPrefix(key) {
                return i
            }
        }
        return nil
    }
    
    /// 处理特殊键盘操作（如方向键导航）
    func handleSpecialKey(_ key: String, modifier: NSEvent.ModifierFlags) {
        guard !items.isEmpty else { return }
        
        switch key {
        case "up", "down", "left", "right":
            handleArrowKeyNavigation(key: key, modifier: modifier)
        default:
            break
        }
    }
    
    /// 处理方向键导航
    private func handleArrowKeyNavigation(key: String, modifier: NSEvent.ModifierFlags) {
        guard let currentIndex = selectedItems.first.flatMap({ items.firstIndex(of: $0) }) else {
            // 如果没有选中项，选中第一项
            if !items.isEmpty {
                isKeyboardSelection = true
                selectedItems = [items[0]]
                selectionState.lastShiftClickItem = items[0]
            }
            return
        }
        
        var targetIndex: Int
        
        switch key {
        case "up":
            targetIndex = max(0, currentIndex - 1)
        case "down":
            targetIndex = min(items.count - 1, currentIndex + 1)
        case "left":
            targetIndex = 0
        case "right":
            targetIndex = items.count - 1
        default:
            return
        }
        
        // 普通方向键：单选（忽略Shift修饰键）
        isKeyboardSelection = true
        selectedItems = [items[targetIndex]]
        selectionState.lastShiftClickItem = items[targetIndex]
    }
    
    // 文件信息显示选项 - 从外部传入
    @Binding var showFileSize: Bool
    @Binding var showFileDate: Bool
    @Binding var showFileType: Bool
    
    // 列宽度状态
    @State private var nameColumnWidth: CGFloat = 300
    @State private var typeColumnWidth: CGFloat = 80
    @State private var sizeColumnWidth: CGFloat = 60
    @State private var dateColumnWidth: CGFloat = 120
    
    // 排序状态
    @State private var sortField: SortField = .name
    @State private var isAscending: Bool = true
    // 计算内容区域的最小宽度，用于触发横向滚动
    private var contentMinWidth: CGFloat {
        let base: CGFloat = 20 + 20 + nameColumnWidth
        let typePart: CGFloat = showFileType ? (3 + typeColumnWidth) : 0
        let sizePart: CGFloat = showFileSize ? (3 + sizeColumnWidth) : 0
        let datePart: CGFloat = showFileDate ? dateColumnWidth : 0
        return base + typePart + sizePart + datePart + 24
    }
    
    private func isDirectory(_ url: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDir)
        return isDir.boolValue
    }
    
    // 获取文件类型
    private func getFileType(_ url: URL) -> String {
        if isDirectory(url) {
            return "文件夹"
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileType = attributes[.type] as? FileAttributeType {
                switch fileType {
                case .typeRegular:
                    return url.pathExtension.uppercased() + " 文件"
                case .typeSymbolicLink:
                    return "链接"
                case .typeSocket:
                    return "套接字"
                case .typeCharacterSpecial:
                    return "字符设备"
                case .typeBlockSpecial:
                    return "块设备"
                case .typeUnknown:
                    return "未知"
                default:
                    return "未知类型"
                }
            } else {
                // 如果无法获取文件类型，使用文件扩展名
                let fileExtension = url.pathExtension
                if fileExtension.isEmpty {
                    return "文件"
                } else {
                    return fileExtension.uppercased()
                }
            }
        } catch {
            // 如果无法获取类型，使用文件扩展名
            let fileExtension = url.pathExtension
            if fileExtension.isEmpty {
                return "文件"
            } else {
                return fileExtension.uppercased()
            }
        }
    }
    
    // 格式化文件大小显示
    private func formatFileSize(_ size: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var fileSize = Double(size)
        var unitIndex = 0
        
        while fileSize >= 1024 && unitIndex < units.count - 1 {
            fileSize /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", fileSize, units[unitIndex])
    }
    
    // 获取文件大小的辅助函数
    private func getFileSize(_ url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    // 获取文件修改日期的辅助函数（返回格式化字符串）
    private func getFileDate(_ url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return formatter.string(from: modificationDate)
            }
            return "未知"
        } catch {
            return "未知"
        }
    }
    
    // 获取文件修改日期的辅助函数（返回Date对象，用于排序）
    private func getFileDateModified(_ url: URL) -> Date {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.modificationDate] as? Date ?? Date.distantPast
        } catch {
            return Date.distantPast
        }
    }
    
    // 将URL路径分割成可点击的路径段
    private func getPathComponents(_ url: URL) -> [(name: String, url: URL, icon: NSImage?)] {
        var components: [(name: String, url: URL, icon: NSImage?)] = []
        
        // 处理外置设备路径：如果路径包含 /Volumes/，直接从设备名开始显示
        if url.path.hasPrefix("/Volumes/") {
            // 分割路径，跳过 /Volumes/
            let volumeComponents = url.pathComponents.dropFirst(2)
            
            if let deviceName = volumeComponents.first {
                // 外置设备名称
                let deviceURL = URL(fileURLWithPath: "/Volumes/\(deviceName)")
                let deviceIcon = NSWorkspace.shared.icon(forFile: deviceURL.path)
                
                // 添加设备名作为根路径
                components.append((name: deviceName, url: deviceURL, icon: deviceIcon))
                
                // 添加设备下的子路径
                var currentPath = deviceURL
                for component in volumeComponents.dropFirst() {
                    currentPath.appendPathComponent(component)
                    let displayName = FileManager.default.displayName(atPath: currentPath.path)
                    let icon = NSWorkspace.shared.icon(forFile: currentPath.path)
                    components.append((name: displayName, url: currentPath, icon: icon))
                }
            }
        } else {
            // 处理本地路径（Macintosh HD）
            var currentPath = URL(fileURLWithPath: "/")
            
            // 获取根卷名称（Macintosh HD 或其他）
            let rootVolumeName = FileManager.default.displayName(atPath: "/")
            let rootIcon = NSWorkspace.shared.icon(forFile: "/")
            
            // 添加根目录
            components.append((name: rootVolumeName, url: currentPath, icon: rootIcon))
            
            // 获取路径组件（不包括根目录）
            let pathComponents = url.pathComponents.dropFirst()
            
            for component in pathComponents {
                currentPath.appendPathComponent(component)
                let displayName = FileManager.default.displayName(atPath: currentPath.path)
                let icon = NSWorkspace.shared.icon(forFile: currentPath.path)
                components.append((name: displayName, url: currentPath, icon: icon))
            }
        }
        
        return components
    }
    
    // 简化的文件点击处理
    private func handleFileClick(item: URL) {
        // 设置为非键盘选择
        isKeyboardSelection = false
        
        // 激活窗口
        if !isActive {
            onActivate()
        }
        
        // 获取修饰键状态
        let currentEvent = NSApp.currentEvent
        let modifierFlags = currentEvent?.modifierFlags ?? []
        let isShiftPressed = modifierFlags.contains(.shift)
        let isCommandPressed = modifierFlags.contains(.command)
        
        // 使用日志器记录调试信息
        ShiftClickLogger.shared.log("=== CLICK DEBUG ===")
        ShiftClickLogger.shared.log("File: \(item.lastPathComponent)")
        ShiftClickLogger.shared.log("Raw modifierFlags: \(modifierFlags.rawValue)")
        ShiftClickLogger.shared.log("Shift: \(isShiftPressed), Command: \(isCommandPressed)")
        ShiftClickLogger.shared.log("Anchor before: \(selectionState.rangeSelectionAnchor?.lastPathComponent ?? "NONE")")
        ShiftClickLogger.shared.log("lastShiftClickItem: \(selectionState.lastShiftClickItem?.lastPathComponent ?? "NONE")")
        ShiftClickLogger.shared.log("Selected: \(selectedItems.count) items")
        if selectedItems.count <= 3 {
            let names = selectedItems.map { $0.lastPathComponent }.joined(separator: ", ")
            ShiftClickLogger.shared.log("Selected items: \(names)")
        }
        ShiftClickLogger.shared.log("=================")
        
        // 检测双击
        let currentTime = Date()
        let timeSinceLastTap = currentTime.timeIntervalSince(selectionState.lastTapTime)
        let isDoubleClick = timeSinceLastTap < 0.2 && selectionState.lastTapItem == item
        
        if isDoubleClick {
            // 双击处理
            print("  - 检测到双击")
            if isDirectory(item) {
                currentURL = item
                selectedItems.removeAll()
                selectionState.reset()
                print("  - 双击目录，清空锚点")
            } else {
                selectedItems.removeAll()
                selectedItems.insert(item)
                NSWorkspace.shared.open(item)
                print("  - 双击文件")
            }
        } else if isShiftPressed {
            // Shift+点击：范围选择
            print("  - 执行Shift+点击处理")
            handleShiftClick(item: item)
        } else if isCommandPressed {
            // Command+点击：切换选择状态
            print("  - 执行Command+点击处理")
            handleCommandClick(item: item)
        } else {
            // 普通点击：选中单个文件
            ShiftClickLogger.shared.log("NORMAL CLICK - Setting anchor to: \(item.lastPathComponent)")
            selectedItems.removeAll()
            selectedItems.insert(item)
            // 普通点击时设置新的范围选择锚点
            selectionState.setAnchor(item)
            selectionState.lastShiftClickItem = item
            ShiftClickLogger.shared.log("Anchor after normal click: \(selectionState.getAnchorInfo())")
        }
        
        selectionState.lastTapTime = currentTime
        selectionState.lastTapItem = item
    }
    
    // 处理Shift+点击：范围选择 - 简化版本
    private func handleShiftClick(item: URL) {
        ShiftClickLogger.shared.log("=== SHIFT CLICK ===")
        ShiftClickLogger.shared.log("Target: \(item.lastPathComponent)")
        ShiftClickLogger.shared.log("Anchor: \(selectionState.rangeSelectionAnchor?.lastPathComponent ?? "NONE")")
        
        let anchor: URL
        if selectionState.rangeSelectionAnchor != nil {
            // 使用现有的锚点
            anchor = selectionState.rangeSelectionAnchor!
            ShiftClickLogger.shared.log("Using existing rangeSelectionAnchor")
        } else {
            // 没有锚点，设置当前点击作为锚点
            ShiftClickLogger.shared.log("No anchor, setting current item as anchor")
            selectedItems.removeAll()
            selectedItems.insert(item)
            selectionState.setAnchor(item)
            selectionState.lastShiftClickItem = item
            return
        }
        
        ShiftClickLogger.shared.log("Using anchor: \(anchor.lastPathComponent)")
        
        // 执行范围选择 - 使用可靠的findItemIndex方法
        let fromIndex = findItemIndex(anchor)
        let toIndex = findItemIndex(item)
        
        guard let fromIdx = fromIndex, let toIdx = toIndex else {
            ShiftClickLogger.shared.log("Cannot find indices, selecting single item")
            selectedItems.removeAll()
            selectedItems.insert(item)
            selectionState.setAnchor(item)
            selectionState.lastShiftClickItem = item
            return
        }
        
        let startIndex = min(fromIdx, toIdx)
        let endIndex = max(fromIdx, toIdx)
        
        ShiftClickLogger.shared.log("Range: \(startIndex) to \(endIndex)")
        
        // 执行范围选择
        selectedItems.removeAll()
        for index in startIndex...endIndex {
            if index < items.count {
                selectedItems.insert(items[index])
            }
        }
        
        // 更新锚点
        selectionState.setAnchor(item)
        selectionState.lastShiftClickItem = item
        
        // 验证状态是否正确设置
        ShiftClickLogger.shared.log("After setting anchor - rangeSelectionAnchor: \(selectionState.rangeSelectionAnchor?.lastPathComponent ?? "STILL_NIL")")
        
        ShiftClickLogger.shared.logItems(Array(selectedItems), prefix: "SELECTED")
        ShiftClickLogger.shared.log("=== END SHIFT CLICK ===")
    }
    
    // 多种方式查找项目索引
    private func findItemIndex(_ item: URL) -> Int? {
        ShiftClickLogger.shared.log("Finding index for: \(item.lastPathComponent)")
        
        // 方法1: 直接URL比较
        if let index = items.firstIndex(where: { $0 == item }) {
            ShiftClickLogger.shared.log("Found by direct URL compare: \(index)")
            return index
        }
        
        // 方法2: lastPathComponent比较
        if let index = items.firstIndex(where: { $0.lastPathComponent == item.lastPathComponent }) {
            ShiftClickLogger.shared.log("Found by filename: \(index)")
            return index
        }
        
        // 方法3: path比较
        if let index = items.firstIndex(where: { $0.path == item.path }) {
            ShiftClickLogger.shared.log("Found by path: \(index)")
            return index
        }
        
        // 方法4: absoluteString比较
        if let index = items.firstIndex(where: { $0.absoluteString == item.absoluteString }) {
            ShiftClickLogger.shared.log("Found by absoluteString: \(index)")
            return index
        }
        
        ShiftClickLogger.shared.log("NOT FOUND by any method")
        return nil
    }
    
    // 处理Command+点击：切换选择状态
    private func handleCommandClick(item: URL) {
        ShiftClickLogger.shared.log("COMMAND CLICK - \(item.lastPathComponent)")
        if selectedItems.contains(item) {
            selectedItems.remove(item)
            ShiftClickLogger.shared.log("Removed from selection")
        } else {
            selectedItems.insert(item)
            ShiftClickLogger.shared.log("Added to selection")
        }
        // Command+点击时也设置新的锚点
        selectionState.setAnchor(item)
        selectionState.lastShiftClickItem = item
        ShiftClickLogger.shared.log("Command click set anchor to: \(item.lastPathComponent)")
    }
    
    // 范围选择函数
    private func performRangeSelection(fromItem: URL?, toItem: URL) {
        print("=== RANGE SELECTION ===")
        
        guard let fromItem = fromItem else {
            print("No fromItem, selecting single item")
            selectedItems.removeAll()
            selectedItems.insert(toItem)
            return
        }
        
        // 查找项目在列表中的索引
        let fromIndex = items.firstIndex(where: { $0.absoluteString == fromItem.absoluteString })
        let toIndex = items.firstIndex(where: { $0.absoluteString == toItem.absoluteString })
        
        guard let fromIdx = fromIndex, let toIdx = toIndex else {
            print("Cannot find items, selecting single item")
            selectedItems.removeAll()
            selectedItems.insert(toItem)
            return
        }
        
        print("From index: \(fromIdx) (\(fromItem.lastPathComponent))")
        print("To index: \(toIdx) (\(toItem.lastPathComponent))")
        
        // 计算选择范围
        let startIndex = min(fromIdx, toIdx)
        let endIndex = max(fromIdx, toIdx)
        
        print("Range: \(startIndex) to \(endIndex)")
        
        // 清空当前选择并添加范围内的所有项目
        selectedItems.removeAll()
        for index in startIndex...endIndex {
            if index < items.count {
                selectedItems.insert(items[index])
                print("Selected: \(items[index].lastPathComponent)")
            }
        }
        
        print("Total selected: \(selectedItems.count)")
        print("========================")
    }
    
    private func loadItems(resetSelection: Bool = true) {
        NSLog("🔄 Loading items for directory: \(currentURL.path)")
        
        if !FileManager.default.fileExists(atPath: currentURL.path) {
            NSLog("❌ Error: Path does not exist: \(currentURL.path)")
            items = []
            return
        }
        
        guard isDirectory(currentURL) else {
            NSLog("❌ Error: \(currentURL.path) is not a directory")
            items = []
            return
        }
        
        let readable = FileManager.default.isReadableFile(atPath: currentURL.path)
        NSLog("📖 Directory readable: \(readable) for path: \(currentURL.path)")
        
        // 直接加载本地文件列表
        do {
            let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
            let contents = try FileManager.default.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: [.isDirectoryKey], options: options)
            
            let filteredContents = showHiddenFiles ? contents : contents.filter { !$0.lastPathComponent.hasPrefix(".") }
            
            let sortedItems = filteredContents.sorted { a, b in
                let isDirA = isDirectory(a)
                let isDirB = isDirectory(b)
                
                // 首先按目录/文件类型排序（目录总是在前面）
                if isDirA != isDirB {
                    return isDirA
                }
                
                // 然后按选定的字段排序
                switch sortField {
                case .name:
                    let result = a.lastPathComponent.localizedCompare(b.lastPathComponent)
                    return isAscending ? result == .orderedAscending : result == .orderedDescending
                    
                case .type:
                    let typeA = getFileType(a)
                    let typeB = getFileType(b)
                    let result = typeA.localizedCompare(typeB)
                    return isAscending ? result == .orderedAscending : result == .orderedDescending
                    
                case .size:
                    let sizeA = isDirectory(a) ? 0 : getFileSize(a)
                    let sizeB = isDirectory(b) ? 0 : getFileSize(b)
                    return isAscending ? sizeA < sizeB : sizeA > sizeB
                    
                case .date:
                    let dateA = getFileDateModified(a)
                    let dateB = getFileDateModified(b)
                    return isAscending ? dateA < dateB : dateA > dateB
                }
            }
            
            NSLog("✅ Successfully loaded \(sortedItems.count) items for \(currentURL.path)")
            
            DispatchQueue.main.async {
                self.items = sortedItems
                // 根据参数决定是否重置Shift选择记录
                if resetSelection {
                    self.selectionState.reset()
                }
            }
        } catch {
            NSLog("❌ Error loading directory contents for \(currentURL.path): \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.items = []
                if resetSelection {
                    self.selectionState.reset()
                }
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 内容层 - 放在最底层，确保能接收点击事件
            VStack(spacing: 0) {
                // 可点击的路径显示栏
                HStack {
                    let pathComponents = getPathComponents(currentURL)
                    PathBarView(
                        components: pathComponents,
                        onActivate: onActivate,
                        setURL: { url in
                            NSLog("📍 Path segment clicked: \(url.path)")
                            currentURL = url
                        },
                        isActive: isActive
                    )
                    .frame(height: 24)
                    
                    Spacer()
                    Text("\(items.count) items")
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .background(Color(.controlBackgroundColor))
                .contentShape(Rectangle())
                .frame(height: 24)
                
                Divider()
                
                // 文件信息显示选项工具栏
                HStack {
                    Button(action: {
                        showFileSize.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showFileSize ? "checkmark.square.fill" : "square")
                                .font(.caption)
                            Text("大小")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    
                    Button(action: {
                        showFileType.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showFileType ? "checkmark.square.fill" : "square")
                                .font(.caption)
                            Text("类型")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    
                    Button(action: {
                        showFileDate.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showFileDate ? "checkmark.square.fill" : "square")
                                .font(.caption)
                            Text("日期")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    
                    Spacer()
                    
                    Text("显示选项")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.controlBackgroundColor))
                
                Divider()
                
                // 文件列表（支持横向滚动）
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // 表头 - 可调节大小的列标题
                        HStack(spacing: 8) {
                        // 复选框占位空间
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20)
                        
                        // 图标占位空间
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20)
                        
                        // 文件名列
                        HStack {
                            Text("文件名")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Spacer()
                            if sortField == .name {
                                Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .frame(width: nameColumnWidth)
                        .background(Color(.controlBackgroundColor))
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            if isHovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                        .onTapGesture {
                            if sortField == .name {
                                isAscending.toggle()
                            } else {
                                sortField = .name
                                isAscending = false // 第一次点击降序
                            }
                            loadItems()
                        }
                        
                        // 分隔线和拖拽区域
                        Rectangle()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: 3)
                            .contentShape(Rectangle())
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.resizeLeftRight.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        nameColumnWidth = max(100, nameColumnWidth + value.translation.width)
                                    }
                            )
                            .help("拖拽调节列宽")
                        
                        // 类型列
                        if showFileType {
                            HStack {
                                Text("类型")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Spacer()
                                if sortField == .type {
                                    Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(width: typeColumnWidth, alignment: .trailing)
                            .background(Color(.controlBackgroundColor))
                            .contentShape(Rectangle())
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                            .onTapGesture {
                                if sortField == .type {
                                    isAscending.toggle()
                                } else {
                                    sortField = .type
                                    isAscending = false // 第一次点击降序
                                }
                                loadItems(resetSelection: false)
                            }
                            
                            // 分隔线和拖拽区域
                            Rectangle()
                                .fill(Color.gray.opacity(0.6))
                                .frame(width: 3)
                                .contentShape(Rectangle())
                                .onHover { isHovering in
                                    if isHovering {
                                        NSCursor.resizeLeftRight.set()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                }
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            typeColumnWidth = max(40, typeColumnWidth + value.translation.width)
                                        }
                                )
                                .help("拖拽调节列宽")
                        }
                        
                        // 大小列
                        if showFileSize {
                            HStack {
                                Text("大小")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Spacer()
                                if sortField == .size {
                                    Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(width: sizeColumnWidth)
                            .background(Color(.controlBackgroundColor))
                            .contentShape(Rectangle())
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                            .onTapGesture {
                                if sortField == .size {
                                    isAscending.toggle()
                                } else {
                                    sortField = .size
                                    isAscending = false // 第一次点击降序
                                }
                                loadItems(resetSelection: false)
                            }
                            
                            // 分隔线和拖拽区域
                            Rectangle()
                                .fill(Color.gray.opacity(0.6))
                                .frame(width: 3)
                                .contentShape(Rectangle())
                                .onHover { isHovering in
                                    if isHovering {
                                        NSCursor.resizeLeftRight.set()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                }
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            sizeColumnWidth = max(40, sizeColumnWidth + value.translation.width)
                                        }
                                )
                                .help("拖拽调节列宽")
                        }
                        
                        // 日期列
                        if showFileDate {
                            HStack {
                                Text("日期")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Spacer()
                                if sortField == .date {
                                    Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(width: dateColumnWidth, alignment: .trailing)
                            .background(Color(.controlBackgroundColor))
                            .contentShape(Rectangle())
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                            .onTapGesture {
                                if sortField == .date {
                                    isAscending.toggle()
                                } else {
                                    sortField = .date
                                    isAscending = false // 第一次点击降序
                                }
                                loadItems(resetSelection: false)
                            }
                        }
                        
                        Spacer()
                        }
                        .frame(minWidth: contentMinWidth, alignment: .leading)
                        .frame(height: 28)
                        .background(Color(.controlBackgroundColor))
                        .overlay(
                            Rectangle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                        
                        // 分隔线
                        Divider()
                        
                        // 文件列表 - 包装在ScrollViewReader中以支持自动滚动
                        ScrollViewReader { proxy in
                            List(items, id: \.self) { item in
                                HStack(spacing: 8) {
                            // 多选复选框
                            Button(action: {
                                // 先激活当前面板
                                if !isActive {
                                    print("🔥 复选框点击触发激活")
                                    onActivate()
                                }
                                
                                // 检测修饰键状态
                                let currentEvent = NSApp.currentEvent
                                let modifierFlags = currentEvent?.modifierFlags ?? []
                                let isShiftPressed = modifierFlags.contains(.shift)
                                let isCommandPressed = modifierFlags.contains(.command)
                                
                                print("🔲 复选框点击 - Shift: \(isShiftPressed), Command: \(isCommandPressed)")
                                
                                if isShiftPressed {
                                    // Shift+点击复选框：执行范围选择
                                    print("🔲 复选框Shift+点击，执行范围选择")
                                    handleShiftClick(item: item)
                                } else if isCommandPressed {
                                    // Command+点击复选框：切换选择状态
                                    print("🔲 复选框Command+点击，切换选择")
                                    handleCommandClick(item: item)
                                } else {
                                    // 普通点击复选框：切换选择状态（保持原有行为）
                                    let previousCount = selectedItems.count
                                    if selectedItems.contains(item) {
                                        selectedItems.remove(item)
                                        print("☑️ 复选框取消选择: \(item.lastPathComponent), 选择数: \(previousCount) -> \(selectedItems.count)")
                                    } else {
                                        selectedItems.insert(item)
                                        print("☑️ 复选框添加选择: \(item.lastPathComponent), 选择数: \(previousCount) -> \(selectedItems.count)")
                                    }
                                    
                                    // 普通复选框点击也需要设置锚点以保持一致性
                                    selectionState.setAnchor(item)
                                    selectionState.lastShiftClickItem = item
                                }
                            }) {
                                Image(systemName: selectedItems.contains(item) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedItems.contains(item) ? .accentColor : .gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(width: 20)
                            
                            // 文件图标
                            Image(systemName: isDirectory(item) ? "folder" : "doc")
                                .foregroundColor(isDirectory(item) ? .blue : .gray)
                                .frame(width: 20)
                            
                            // 文件名
                            Text(item.lastPathComponent)
                                .foregroundColor(selectedItems.contains(item) ? Color.accentColor : .primary)
                                .frame(width: nameColumnWidth, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            // 文件类型
                            if showFileType {
                                Text(getFileType(item))
                                    .font(.system(.caption))
                                    .foregroundColor(.secondary)
                                    .frame(width: typeColumnWidth, alignment: .trailing)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            
                            // 文件大小
                            if showFileSize {
                                Text(isDirectory(item) ? "" : formatFileSize(getFileSize(item)))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: sizeColumnWidth, alignment: .trailing)
                            }
                            
                            // 修改日期
                            if showFileDate {
                                Text(getFileDate(item))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: dateColumnWidth, alignment: .trailing)
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 简化的文件点击处理
                            handleFileClick(item: item)
                        }
                        .onDrag {
                            if isDirectory(item) {
                                print("🎯 开始拖拽目录: \(item.lastPathComponent)")
                                return NSItemProvider(object: item as NSURL)
                            } else {
                                print("🚫 文件不支持拖拽: \(item.lastPathComponent)")
                                return NSItemProvider()
                            }
                        }
                        .contextMenu {
                            Button(action: {
                                selectedItems.insert(item)
                            }) {
                                Text("选中")
                            }
                            
                            if selectedItems.contains(item) {
                                Button(action: {
                                    selectedItems.remove(item)
                                }) {
                                    Text("取消选中")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                if isDirectory(item) {
                                    currentURL = item
                                    selectedItems.removeAll()
                                } else {
                                    NSWorkspace.shared.open(item)
                                }
                            }) {
                                Text(isDirectory(item) ? "打开文件夹" : "打开文件")
                            }
                        }
                        }
                        .listStyle(.plain)
                        .frame(minWidth: contentMinWidth, alignment: .leading)
                        
                        // 当选中项改变时，只有在通过键盘选择时才自动滚动到第一个选中项
                        // 如果是通过鼠标点击选择的（项目已经可见），则不滚动
                        .onChange(of: selectedItems) { newSelectedItems in
                            if let firstSelected = newSelectedItems.first {
                                // 只有当是通过键盘选择时才自动滚动
                                if isKeyboardSelection {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo(firstSelected, anchor: .top)
                                    }
                                    
                                    // 重置键盘选择标志
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isKeyboardSelection = false
                                    }
                                }
                            }
                        }
                        }
                    }
                }
            }
            
            // 移除了透明点击覆盖层，因为它会拦截文件点击事件
            // 文件列表和路径栏的点击事件会自行处理激活逻辑
            
            // 键盘输入捕获器 - 用于快速定位文件和键盘导航
            KeyboardInputCapturer(
                onKeyPress: handleKeyPress,
                onSpecialKey: handleSpecialKey,
                isActive: isActive,
                parent: keyboardFocusView
            )
                .frame(width: 0, height: 0)
                .background(Color.clear)
        }
        .frame(minWidth: 300, minHeight: 200)
        .onAppear {
            print("🎯🎯🎯 FileBrowserPane appeared - isActive: \(isActive)")
            NSLog("🎯🎯🎯 FileBrowserPane appeared - isActive: \(isActive)")
            loadItems()
        }
        .onChange(of: currentURL) { newURL in
            NSLog("📍 URL changed to: \(newURL.path)")
            loadItems()
        }
        .onChange(of: showHiddenFiles) { newValue in
            NSLog("👁️ Show hidden files changed to: \(newValue)")
            loadItems()
        }
        .onChange(of: refreshTrigger) { _ in
            NSLog("🔄 Refresh trigger changed, reloading items")
            loadItems(resetSelection: false)
        }
    }
}

/// 路径段视图 - 显示路径的单个段（图标 + 名称），支持点击和悬停效果
struct PathSegmentView: View {
    let name: String
    let icon: NSImage?
    let onTap: () -> Void
    let isCurrentDirectory: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
            
            Text(name)
                .font(.system(size: 12))
                .foregroundColor(isCurrentDirectory ? .white : .primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    isCurrentDirectory ? 
                    Color(.controlAccentColor) : 
                    (isHovering ? Color(.controlAccentColor).opacity(0.2) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// 路径栏视图：当路径过长时，自动从左侧用“...”替换，保证右侧末端目录完整显示
struct PathBarView: View {
    struct DisplayComponent: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
        let icon: NSImage?
    }
    
    let components: [(name: String, url: URL, icon: NSImage?)]
    let onActivate: () -> Void
    let setURL: (URL) -> Void
    let isActive: Bool
    
    private let font: NSFont = .systemFont(ofSize: 12)
    private let chevronWidth: CGFloat = 12
    private let iconWidth: CGFloat = 16
    private let segmentHPadding: CGFloat = 12 // 左右各6
    private let iconTextSpacing: CGFloat = 4
    
    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let display = computeDisplay(components: components, availableWidth: availableWidth)
            
            HStack(spacing: 4) {
                ForEach(Array(display.enumerated()), id: \.element.id) { idx, comp in
                    PathSegmentView(
                        name: comp.name,
                        icon: comp.name == "…" ? nil : comp.icon,
                        onTap: {
                            onActivate()
                            setURL(comp.url)
                        },
                        isCurrentDirectory: isActive && idx == display.count - 1
                    )
                    
                    if idx < display.count - 1 {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 2)
                    }
                }
            }
        }
        .frame(height: 24)
    }
    
    private func textWidth(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return ceil(size.width)
    }
    
    private func segmentWidth(name: String, hasIcon: Bool) -> CGFloat {
        var width = segmentHPadding + textWidth(name)
        if hasIcon {
            width += iconWidth + iconTextSpacing
        }
        return width
    }
    
    private func totalWidth(of comps: [DisplayComponent]) -> CGFloat {
        guard !comps.isEmpty else { return 0 }
        let segmentsWidth = comps.enumerated().reduce(CGFloat(0)) { acc, pair in
            let idx = pair.offset
            let c = pair.element
            let w = segmentWidth(name: c.name, hasIcon: c.icon != nil && c.name != "…")
            let sep = idx < comps.count - 1 ? chevronWidth : 0
            return acc + w + sep
        }
        return segmentsWidth
    }
    
    private func truncateMiddle(_ text: String, toWidth target: CGFloat) -> String {
        if textWidth(text) <= target { return text }
        let scalars = Array(text)
        if scalars.count <= 3 { return scalars.map(String.init).joined() }
        
        var left = Int(Double(scalars.count) * 0.45)
        var right = scalars.count - left
        left = max(1, left)
        right = max(1, right)
        
        func build(_ l: Int, _ r: Int) -> String {
            let prefix = String(scalars.prefix(l))
            let suffix = String(scalars.suffix(r))
            return prefix + "..." + suffix
        }
        
        var current = build(left, right)
        while textWidth(current) > target && left > 1 && right > 1 {
            left -= 1
            right -= 1
            current = build(left, right)
        }
        return current
    }
    
    private func computeDisplay(components: [(name: String, url: URL, icon: NSImage?)], availableWidth: CGFloat) -> [DisplayComponent] {
        var display: [DisplayComponent] = components.map { DisplayComponent(name: $0.name, url: $0.url, icon: $0.icon) }
        var width = totalWidth(of: display)
        if width <= availableWidth { return display }
        
        let ellipsisWidth = segmentWidth(name: "…", hasIcon: false)
        
        var i = 0
        while i < display.count - 1 && width > availableWidth {
            let original = display[i]
            let originalWidth = segmentWidth(name: original.name, hasIcon: original.icon != nil)
            display[i] = DisplayComponent(name: "…", url: original.url, icon: nil)
            width = width - originalWidth + ellipsisWidth
            i += 1
        }
        
        if width > availableWidth, i < display.count {
            let idx = i
            let comp = display[idx]
            let currentSegWidth = segmentWidth(name: comp.name, hasIcon: comp.icon != nil)
            let needReduce = width - availableWidth
            let targetSegWidth = max(ellipsisWidth, currentSegWidth - needReduce)
            let base = segmentHPadding + (comp.icon != nil ? (iconWidth + iconTextSpacing) : 0)
            let targetTextWidth = max(0, targetSegWidth - base)
            let newName = truncateMiddle(comp.name, toWidth: targetTextWidth)
            display[idx] = DisplayComponent(name: newName, url: comp.url, icon: comp.icon)
        }
        
        return display
    }
}
