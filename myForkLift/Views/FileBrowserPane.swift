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

/// 文件浏览器面板
struct FileBrowserPane: View {
    @Binding var currentURL: URL
    @Binding var showHiddenFiles: Bool
    @Binding var selectedItems: Set<URL>
    let isActive: Bool
    let onActivate: () -> Void
    let refreshTrigger: UUID
    let panelId: String // 用于识别是左面板还是右面板
    @State private var items: [URL] = []
    @State private var lastTapTime: Date = Date.distantPast
    @State private var lastTapItem: URL? = nil
    @State private var lastShiftClickItem: URL? = nil
    @State private var cancellables = Set<AnyCancellable>()
    
    // 文件信息显示选项 - 从外部传入
    @Binding var showFileSize: Bool
    @Binding var showFileDate: Bool
    @Binding var showFileType: Bool
    
    // 列宽度状态
    @State private var nameColumnWidth: CGFloat = 300
    @State private var typeColumnWidth: CGFloat = 80
    @State private var sizeColumnWidth: CGFloat = 60
    @State private var dateColumnWidth: CGFloat = 120
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
    
    // 获取文件修改日期的辅助函数
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
    
    // 将URL路径分割成可点击的路径段
    private func getPathComponents(_ url: URL) -> [(name: String, url: URL, icon: NSImage?)] {
        var components: [(name: String, url: URL, icon: NSImage?)] = []
        
        // 处理本地路径
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
        
        return components
    }
    
    // 简化的文件点击处理
    private func handleFileClick(item: URL) {
        // 激活窗口
        if !isActive {
            print("🔥 文件点击触发激活")
            onActivate()
        }
        
        // 获取当前事件检测Shift键
        let currentEvent = NSApp.currentEvent
        let isShiftPressed = currentEvent?.modifierFlags.contains(.shift) ?? false
        
        print("📁 点击文件: \(item.lastPathComponent)")
        print("⌨️ Shift键: \(isShiftPressed)")
        
        // 检测双击
        let currentTime = Date()
        let timeSinceLastTap = currentTime.timeIntervalSince(lastTapTime)
        let isDoubleClick = timeSinceLastTap < 0.2 && lastTapItem == item
        
        if isDoubleClick {
            // 双击处理
            print("🖱️ 双击")
            if isDirectory(item) {
                currentURL = item
                selectedItems.removeAll()
                lastShiftClickItem = nil
            } else {
                // 1. 选中这个文件
                // 2. 把其它选中的文件都取消
                selectedItems.removeAll()
                selectedItems.insert(item)
                // 3. 打开这个文件
                NSWorkspace.shared.open(item)
            }
        } else if isShiftPressed {
            // Shift+点击：范围选择
            print("🎯 Shift+点击 - 执行范围选择")
            performRangeSelection(fromItem: lastShiftClickItem, toItem: item)
            lastShiftClickItem = item
        } else {
            // 普通点击：切换单个选择
            print("👆 普通点击")
            if selectedItems.contains(item) {
                selectedItems.remove(item)
            } else {
                selectedItems.insert(item)
            }
            lastShiftClickItem = item
        }
        
        lastTapTime = currentTime
        lastTapItem = item
    }
    
    // 执行范围选择（Shift+点击）
    private func performRangeSelection(fromItem: URL?, toItem: URL) {
        guard let fromItem = fromItem else {
            // 如果没有起始点，直接选择当前项
            selectedItems.insert(toItem)
            return
        }
        
        // 找到两个项目在列表中的索引
        guard let fromIndex = items.firstIndex(of: fromItem),
              let toIndex = items.firstIndex(of: toItem) else {
            print("❌ 无法找到项目的索引")
            selectedItems.insert(toItem) // 回退到单个选择
            return
        }
        
        print("🎯 范围选择: \(fromItem.lastPathComponent) [\(fromIndex)] -> \(toItem.lastPathComponent) [\(toIndex)]")
        
        // 清空当前选择
        selectedItems.removeAll()
        
        // 计算选择范围
        let startIndex = min(fromIndex, toIndex)
        let endIndex = max(fromIndex, toIndex)
        
        // 选择范围内的所有项目
        for index in startIndex...endIndex {
            selectedItems.insert(items[index])
        }
        
        NSLog("✅ 范围选择完成，选中了 \(selectedItems.count) 个项目")
    }
    
    private func loadItems() {
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
                if isDirA != isDirB {
                    return isDirA
                } else {
                    return a.lastPathComponent.localizedCompare(b.lastPathComponent) == .orderedAscending
                }
            }
            
            NSLog("✅ Successfully loaded \(sortedItems.count) items for \(currentURL.path)")
            
            DispatchQueue.main.async {
                self.items = sortedItems
                // 切换目录时重置Shift选择记录
                self.lastShiftClickItem = nil
            }
        } catch {
            NSLog("❌ Error loading directory contents for \(currentURL.path): \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.items = []
                self.lastShiftClickItem = nil
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 内容层 - 放在最底层，确保能接收点击事件
            VStack(spacing: 0) {
                // 可点击的路径显示栏
                HStack {
                    HStack(spacing: 4) {
                        let pathComponents = getPathComponents(currentURL)
                        
                        ForEach(0..<pathComponents.count, id: \.self) { index in
                            let component = pathComponents[index]
                            
                            PathSegmentView(
                                name: component.name,
                                icon: component.icon,
                                onTap: {
                                    onActivate()
                                    NSLog("📍 Path segment clicked: \(component.name), URL: \(component.url.path)")
                                    currentURL = component.url
                                }
                            )
                            
                            // 分隔符 - 使用 SF Symbols
                            if index < pathComponents.count - 1 {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Spacer()
                    Text("\(items.count) items")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .background(Color(.controlBackgroundColor))
                .contentShape(Rectangle())
                
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
                        }
                        .frame(width: nameColumnWidth)
                        .background(Color(.controlBackgroundColor))
                        .onHover { isHovering in
                            if isHovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
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
                            }
                            .frame(width: typeColumnWidth, alignment: .trailing)
                            .background(Color(.controlBackgroundColor))
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
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
                            }
                            .frame(width: sizeColumnWidth)
                            .background(Color(.controlBackgroundColor))
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
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
                            }
                            .frame(width: dateColumnWidth, alignment: .trailing)
                            .background(Color(.controlBackgroundColor))
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
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
                        
                        // 文件列表
                        List(items, id: \.self) { item in
                        HStack(spacing: 8) {
                            // 多选复选框
                            Button(action: {
                                if selectedItems.contains(item) {
                                    selectedItems.remove(item)
                                } else {
                                    selectedItems.insert(item)
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
                    }
                }
            }
            
            // 透明点击覆盖层 - 放在最顶层，但只有非激活时才显示
            if !isActive {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("🎯🎯🎯 空白区域被点击了！当前状态: 未激活")
                        NSLog("🎯🎯🎯 空白区域被点击了！当前状态: 未激活")
                        print("🔥🔥🔥 空白区域触发激活")
                        onActivate()
                        selectedItems.removeAll()
                    }
            }
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
            loadItems()
        }
    }
}

/// 路径段视图 - 显示路径的单个段（图标 + 名称），支持点击和悬停效果
struct PathSegmentView: View {
    let name: String
    let icon: NSImage?
    let onTap: () -> Void
    
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
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(.controlAccentColor).opacity(0.2) : Color.clear)
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
