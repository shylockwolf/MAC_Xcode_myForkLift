//
//  SidebarView.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Dispatch

// Drag and Drop delegate for reordering items
struct DragRelocateDelegate<Item: Equatable>: DropDelegate {
    let item: Item
    @Binding var items: [Item]
    let currentIndex: Int
    
    // 移除dropEntered中的重排逻辑，避免拖拽过程中频繁重排导致闪烁
    func dropEntered(info: DropInfo) {
        // 空实现，不在拖拽过程中进行重排
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // 只在释放鼠标时进行一次实际重排
        guard let fromIndex = getSourceIndex(from: info) else { return false }
        
        // Only reorder if we're at a different position
        if fromIndex != currentIndex {
            // Remove the item from its original position
            let movedItem = items.remove(at: fromIndex)
            // Insert it at the new position
            items.insert(movedItem, at: currentIndex)
        }
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    // 获取源索引，使用semaphore确保同步获取数据
    private func getSourceIndex(from info: DropInfo) -> Int? {
        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else { return nil }
        
        var sourceIndex: Int?
        let semaphore = DispatchSemaphore(value: 0)
        
        // 使用completion handler获取数据
        provider.loadDataRepresentation(forTypeIdentifier: "public.plain-text") { data, error in
            if let data = data, let string = String(data: data, encoding: .utf8) {
                sourceIndex = Int(string)
            }
            semaphore.signal()
        }
        
        // 等待数据加载完成
        _ = semaphore.wait(timeout: .now() + 0.1)
        
        return sourceIndex
    }
}

// 获取主盘剩余空间的辅助函数
extension URL {
    func getFreeDiskSpace() -> Int64? {
        do {
            let values = try self.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            return nil
        }
    }
    
    // 格式化字节数为可读字符串
    func formatBytes(bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", size, units[unitIndex])
    }
}

struct SidebarView: View {
    @Binding var activePane: Pane
    @Binding var leftPaneURL: URL
    @Binding var rightPaneURL: URL
    @Binding var externalDevices: [ExternalDevice]
    @Binding var favorites: [FavoriteItem]
    @Binding var openedFiles: [URL]
    
    let onEjectDevice: (ExternalDevice) -> Void
    let onEjectAllDevices: () -> Void
    let onFavoriteRemoved: (FavoriteItem) -> Void
    let onFavoriteReorder: (_ providers: [NSItemProvider], _ targetFavorite: FavoriteItem) -> Bool
    let onDropToFavorites: (_ providers: [NSItemProvider]) -> Bool
    let onOpenedFileRemoved: (URL) -> Void
    
    // 获取文件的实际系统图标
    private func getFileIcon(for url: URL) -> NSImage {
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Devices").font(.caption).foregroundColor(.secondary)
                Spacer()
                
                // 全部弹出按钮（只有当有外部设备时才显示）
                if !externalDevices.isEmpty {
                    Button(action: {
                        onEjectAllDevices()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "eject.circle")
                                .font(.caption)
                            Text("Eject All")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
        }
    }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // 统一的设备列表（包括系统设备和外部设备）
            let allDevices = [ExternalDevice(name: "Macintosh HD", url: URL(fileURLWithPath: "/"), volumeName: "Macintosh HD", mountPoint: "/", deviceType: .externalDrive)] + externalDevices
            
            ForEach(allDevices) { device in
                HStack {
                    Image(systemName: device.icon)
                        .foregroundColor(device.deviceType == .usb ? .orange : device.name == "Macintosh HD" ? .blue : .blue)
                    Text(device.name)
                        .lineLimit(1)
                    
                    // 显示主盘剩余空间信息
                    if device.name == "Macintosh HD" {
                        if let freeSpace = device.url.getFreeDiskSpace() {
                            Text(device.url.formatBytes(bytes: freeSpace))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .padding(.leading, 8)
                        }
                    }
                    
                    Spacer()
                    
                    // 只为外部设备显示弹出按钮
                    if device.name != "Macintosh HD" {
                        Button(action: {
                            onEjectDevice(device)
                        }) {
                            Image(systemName: "eject")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("推出设备")
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    // 只更新当前激活的面板
                    switch activePane {
                    case .left:
                        leftPaneURL = device.url
                    case .right:
                        rightPaneURL = device.url
                    }
                }
                .contextMenu {
                    Button(action: {
                        // 在Finder中显示
                        NSWorkspace.shared.selectFile(device.url.path, inFileViewerRootedAtPath: device.url.path)
                    }) {
                        Text("在Finder中显示")
                        Image(systemName: "folder")
                    }
                    
                    // 只有非系统设备才显示推出按钮
                    if device.name != "Macintosh HD" {
                        Button(action: {
                            // 推出设备
                            onEjectDevice(device)
                        }) {
                            Text("推出")
                            Image(systemName: "eject")
                        }
                    }
                }
            }
            
            Divider()
            
            // 收藏夹标题和拖拽区域
            VStack(alignment: .leading, spacing: 4) {
                Text("Favorites").font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                
                // 收藏夹列表
                ForEach(favorites) { favorite in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.gray.opacity(0.5))
                            .font(.caption)
                        Image(systemName: favorite.icon)
                        .foregroundColor(.blue)
                        Text(favorite.name)
                        Spacer()
                        // 删除按钮
                        Button(action: {
                            onFavoriteRemoved(favorite)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                    .onDrag {
                        NSItemProvider(object: favorite.name as NSString)
                    }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        onFavoriteReorder(providers, favorite)
                    }
                    .onTapGesture {
                        
                        // 只更新当前激活的面板
                        switch activePane {
                        case .left:
                            leftPaneURL = favorite.url
                        case .right:
                            rightPaneURL = favorite.url
                        }
                    }
                }
                
                // 拖拽接收区域
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 20)
                    .overlay(
                        Image(systemName: "paperclip.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    )
                    .cornerRadius(6)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        onDropToFavorites(providers)
                    }
                
                // 从菜单打开的文件列表区域
                if !openedFiles.isEmpty {
                    Text("Opened Files").font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    
                    // 使用网格布局实现横向排列，自动换行
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 8)], spacing: 8) {
                        ForEach(Array(openedFiles.enumerated()), id: \.1) { index, url in
                            HStack {
                                Image(nsImage: getFileIcon(for: url))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // 直接打开文件
                                NSWorkspace.shared.open(url)
                            }
                            .onDrag { NSItemProvider(object: String(index) as NSString) }
                            .onDrop(of: [.text], delegate: DragRelocateDelegate(
                                item: url,
                                items: $openedFiles,
                                currentIndex: index
                            ))
                            .contextMenu {
                                Button("删除") {
                                    onOpenedFileRemoved(url)
                                }
                                Button("放弃") {
                                    // 放弃操作，不执行任何动作
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            
            Spacer()
        }
        .frame(width: 210)
        .background(Color(.controlBackgroundColor))
        .overlay(Divider(), alignment: .trailing)
    }
}
