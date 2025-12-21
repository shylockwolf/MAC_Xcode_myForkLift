//
//  ContentView+FileOperations.swift
//  DWBrowser
//
//  将文件复制/移动/删除/新建文件夹等操作从 ContentView 主体拆分出来，
//  保持 ContentView 更加简洁。
//

import SwiftUI
import Foundation
import AppKit

extension ContentView {
    // 获取当前激活面板的URL
    func getCurrentPaneURL() -> URL {
        return viewModel.activePane == .left ? leftPaneURL : rightPaneURL
    }
    
    // 检查是否为目录
    func isDirectory(_ url: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDir)
        return isDir.boolValue
    }
    
    func renameItem() {
        let selectedItems = Array(viewModel.getCurrentSelectedItems())
        guard selectedItems.count == 1, let item = selectedItems.first else {
            return
        }
        
        let oldName = item.lastPathComponent
        let parentURL = item.deletingLastPathComponent()
        
        let textField = NSTextField(string: oldName)
        textField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        
        let alert = NSAlert()
        alert.messageText = "重命名"
        alert.informativeText = "请输入新的名称："
        alert.accessoryView = textField
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        
        var newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        
        if newName == oldName { return }
        if newName.contains("/") || newName.contains(":") { 
            showAlertSimple(title: "重命名失败", message: "名称不能包含 / 或 :")
            return 
        }
        
        let newURL = parentURL.appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: newURL.path) {
            showAlertSimple(title: "重命名失败", message: "目标名称已存在")
            return
        }
        
        do {
            try FileManager.default.moveItem(at: item, to: newURL)
            
            switch viewModel.activePane {
            case .left:
                viewModel.leftSelectedItems = [newURL]
            case .right:
                viewModel.rightSelectedItems = [newURL]
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                viewModel.triggerRefresh()
            }
        } catch {
            showAlertSimple(title: "重命名失败", message: error.localizedDescription)
        }
    }
    
    // 获取文件大小的辅助函数
    func getFileSize(_ url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    // 复制选中文件到系统剪贴板
    func copyItem() {
        // 检查当前激活面板的选中项
        var sourceItems = Array(viewModel.getCurrentSelectedItems())
        
        // 如果当前激活面板没有选中项，检查另一个面板
        if sourceItems.isEmpty {
            let otherItems = viewModel.activePane == .left ? 
                Array(viewModel.rightSelectedItems) : 
                Array(viewModel.leftSelectedItems)
            
            if !otherItems.isEmpty {
                // 如果另一个面板有选中项，切换激活面板并使用那些选中项
                viewModel.setActivePane(viewModel.activePane == .left ? .right : .left)
                sourceItems = otherItems
            }
        }
        
        guard !sourceItems.isEmpty else {
            print("❌ 没有选中项可复制")
            showAlertSimple(title: "复制失败", message: "没有选中项可复制到剪贴板")
            return
        }
        
        // 将选中的文件URL复制到系统剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // 将URL转换为NSURL数组，因为NSPasteboard需要NSURL类型
        let nsUrls = sourceItems.map { $0 as NSURL }
        
        // 将URL写入剪贴板
        let success = pasteboard.writeObjects(nsUrls)
        
        if success {
            let count = sourceItems.count
            let message = count == 1 ? 
                "已复制1个项目到剪贴板" : 
                "已复制\(count)个项目到剪贴板"
            print("✅ \(message)")
        } else {
            print("❌ 无法复制到剪贴板")
            showAlertSimple(title: "复制失败", message: "无法将选中项复制到剪贴板")
        }
    }
    
    // 复制选中文件到另一个窗口激活的目录（支持多选，带进度显示）
    func copyToAnotherPane() {
        let sourceItems = Array(viewModel.getCurrentSelectedItems())
        
        guard !sourceItems.isEmpty else {
            print("❌ 没有选中项可复制")
            return
        }
        
        let targetURL = viewModel.activePane == .right ? leftPaneURL : rightPaneURL
        
        // 确保目标目录存在
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ 无法创建目标目录: \(targetURL.path) - \(error.localizedDescription)")
            showAlertSimple(title: "复制失败", message: "无法访问目标目录: \(error.localizedDescription)")
            return
        }
        
        var totalBytes: Int64 = 0
        var fileSizes: [URL: Int64] = [:]
        for sourceURL in sourceItems {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                var dirTotal: Int64 = 0
                if let enumerator = FileManager.default.enumerator(at: sourceURL, includingPropertiesForKeys: nil) {
                    for case let u as URL in enumerator {
                        var isDir2: ObjCBool = false
                        FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir2)
                        if !isDir2.boolValue {
                            let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
                            dirTotal += (attrs?[.size] as? Int64) ?? 0
                        }
                    }
                }
                fileSizes[sourceURL] = dirTotal
                totalBytes += dirTotal
            } else {
                let size = getFileSize(sourceURL)
                fileSizes[sourceURL] = size
                totalBytes += size
            }
        }
        
        var successCount = 0
        var errorMessages: [String] = []
        var completedBytes: Int64 = 0
        
        // 首先检查所有文件，收集重名文件
        var duplicateFiles: [URL] = []
        for sourceURL in sourceItems {
            let destinationURL = targetURL.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                duplicateFiles.append(sourceURL)
            }
        }
        
        // 如果有重名文件，显示一次性确认对话框
        var shouldReplaceAll = false
        if !duplicateFiles.isEmpty {
            let alert = NSAlert()
            alert.messageText = "确认覆盖"
            
            // 构建重名文件列表
            var fileList = ""
            for (index, file) in duplicateFiles.enumerated() {
                if index < 5 { // 最多显示5个文件名
                    fileList += "- \(file.lastPathComponent)\n"
                }
            }
            if duplicateFiles.count > 5 {
                fileList += "- ... 以及其他 \(duplicateFiles.count - 5) 个文件"
            }
            
            alert.informativeText = "检测到 \(duplicateFiles.count) 个文件在目标位置已存在，是否全部覆盖？\n\n\(fileList)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "全部覆盖")
            alert.addButton(withTitle: "全部放弃")
            let response = alert.runModal()
            shouldReplaceAll = (response == .alertFirstButtonReturn)
        }
        
        // 开始后台复制任务
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, sourceURL) in sourceItems.enumerated() {
                let destinationURL = targetURL.appendingPathComponent(sourceURL.lastPathComponent)
                
                // 检查目标位置是否已存在同名文件
                let fileExists = FileManager.default.fileExists(atPath: destinationURL.path)
                
                // 调试信息
                print("🔧 移动操作: \(sourceURL.path) -> \(destinationURL.path)")
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                print("🔧 源文件类型: \(isDirectory.boolValue ? "目录" : "文件")")
                print("🔧 源文件大小: \(getFileSize(sourceURL)) 字节")
                if fileExists {
                    if !shouldReplaceAll {
                        DispatchQueue.main.async {
                            errorMessages.append("\(sourceURL.lastPathComponent): 用户选择放弃覆盖")
                        }
                        continue
                    }
                    // 如果选择覆盖，先删除目标文件
                    do {
                        try FileManager.default.removeItem(at: destinationURL)
                    } catch {
                        DispatchQueue.main.async {
                            errorMessages.append("\(sourceURL.lastPathComponent): 无法删除已存在的文件: \(error.localizedDescription)")
                        }
                        continue
                    }
                }
                
                // 获取文件大小用于计算进度
                let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
                let fileSize = fileAttributes?[.size] as? Int64 ?? 0
                
                // 显示进度窗口
                DispatchQueue.main.async {
                    self.copyProgress = CopyProgress(
                        fileName: sourceURL.lastPathComponent,
                        progress: 0.0,
                        bytesPerSecond: 0,
                        estimatedTimeRemaining: 0,
                        isCompleted: false,
                        operation: "copy",
                        currentFileIndex: index + 1,
                        totalFiles: sourceItems.count
                    )
                    self.showCopyProgress = true
                }
                
                do {
                    var lastProgressUpdate = Date()
                    var lastSpeedTime = Date()
                    var lastSpeedBytes: Int64 = 0
                    var currentSpeed: Double = 0.0
                    
                    // 检查是否是目录
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                    
                    if isDirectory.boolValue {
                        // 本地目录之间复制
                        // 复制本地目录（使用系统方法，显示简单进度）
                        DispatchQueue.main.async {
                            self.copyProgress = CopyProgress(
                                fileName: sourceURL.lastPathComponent,
                                progress: 0.0,
                                bytesPerSecond: 0,
                                estimatedTimeRemaining: 0,
                                isCompleted: false,
                                operation: "copy",
                                currentFileIndex: index + 1,
                                totalFiles: sourceItems.count
                            )
                        }
                        
                        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                        
                        DispatchQueue.main.async {
                            self.copyProgress = CopyProgress(
                                fileName: sourceURL.lastPathComponent,
                                progress: 1.0,
                                bytesPerSecond: 0,
                                estimatedTimeRemaining: 0,
                                isCompleted: true,
                                operation: "copy",
                                currentFileIndex: index + 1,
                                totalFiles: sourceItems.count
                            )
                        }
                    } else {
                        // 本地文件之间复制
                        // 复制文件（使用自定义进度方法）
                        try FileOperationService.copyFileWithProgress(
                            from: sourceURL,
                            to: destinationURL,
                            bufferSize: 1024 * 1024, // 1MB buffer
                            onProgress: { bytes in
                                let currentTime = Date()
                                let totalProgress = totalBytes > 0 ? Double(completedBytes + bytes) / Double(totalBytes) : 1.0
                                
                                let speedTimeElapsed = currentTime.timeIntervalSince(lastSpeedTime)
                                let speedBytesTransferred = Int64(bytes) - lastSpeedBytes
                                var bytesPerSecond: Double = 0.0
                                
                                if speedTimeElapsed > 0.1 {
                                    bytesPerSecond = Double(speedBytesTransferred) / speedTimeElapsed
                                    lastSpeedTime = currentTime
                                    lastSpeedBytes = Int64(bytes)
                                    currentSpeed = bytesPerSecond
                                } else if speedBytesTransferred > 0 {
                                    if currentSpeed > 0 {
                                        bytesPerSecond = currentSpeed
                                    } else {
                                        bytesPerSecond = 10 * 1024 * 1024
                                    }
                                } else if bytes > 0 {
                                    bytesPerSecond = 10 * 1024 * 1024
                                }
                                
                                let currentFileRemaining = fileSize - bytes
                                var totalRemainingBytes: Int64 = currentFileRemaining
                                
                                for i in (index + 1)..<sourceItems.count {
                                    totalRemainingBytes += fileSizes[sourceItems[i]] ?? 0
                                }
                                
                                let estimatedTimeRemaining = bytesPerSecond > 0 ?
                                    Double(totalRemainingBytes) / bytesPerSecond : 0
                                
                                let timeSinceLastUpdate = currentTime.timeIntervalSince(lastProgressUpdate)
                                let shouldUpdate = timeSinceLastUpdate >= 0.2 || bytes == fileSize
                                
                                if shouldUpdate {
                                    DispatchQueue.main.async {
                                        self.copyProgress = CopyProgress(
                                            fileName: sourceURL.lastPathComponent,
                                            progress: totalProgress,
                                            bytesPerSecond: bytesPerSecond,
                                            estimatedTimeRemaining: estimatedTimeRemaining,
                                            isCompleted: false,
                                            operation: "copy",
                                            currentFileIndex: index + 1,
                                            totalFiles: sourceItems.count
                                        )
                                    }
                                    lastProgressUpdate = currentTime
                                }
                            }
                        )
                    }
                    
                    let currentTotalCompleted = fileSizes[sourceURL] ?? fileSize
                    completedBytes += currentTotalCompleted
                    
                    DispatchQueue.main.async {
                        self.copyProgress = CopyProgress(
                            fileName: sourceURL.lastPathComponent,
                            progress: 1.0,
                            bytesPerSecond: 0,
                            estimatedTimeRemaining: 0,
                            isCompleted: true,
                            operation: "copy",
                            currentFileIndex: index + 1,
                            totalFiles: sourceItems.count
                        )
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if index == sourceItems.count - 1 {
                                self.showCopyProgress = false
                            }
                        }
                    }
                    
                    print("✅ 成功复制: \(sourceURL.lastPathComponent) 到 \(targetURL.path)")
                    successCount += 1
                    
                } catch {
                    let errorMessage = "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
                    DispatchQueue.main.async {
                        errorMessages.append(errorMessage)
                    }
                    print("❌ 复制失败: \(errorMessage)")
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = sourceItems.count == 1 ?
                        "成功复制 \(successCount) 个文件" :
                        "成功复制 \(successCount) 个文件（共 \(sourceItems.count) 个）"
                    print("✅ \(message)")
                }
                
                if !errorMessages.isEmpty {
                    let fullMessage = "复制过程中发生以下错误：\n\n" + errorMessages.joined(separator: "\n")
                    self.showAlertSimple(title: "部分复制失败", message: fullMessage)
                }
                
                self.viewModel.clearAllSelections()
                
                // 重新获取targetPaneURL进行刷新检查
                let targetPaneURL = self.viewModel.activePane == .right ? self.leftPaneURL : self.rightPaneURL
                
                // 普通刷新
                print("🔧🔄 普通刷新")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.viewModel.triggerRefresh()
                }
            }
        }
    }
    
    // 删除选中文件（移到垃圾箱）
    func deleteItem() {
        let itemsToTrash = viewModel.getCurrentSelectedItems()
        
        guard !itemsToTrash.isEmpty else {
            print("❌ 没有选中项可移到垃圾箱")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            var errorMessages: [String] = []
            
            for itemURL in itemsToTrash {
                if FileOperationService.moveItemToTrashSync(itemURL) {
                    print("✅ 成功移到垃圾箱: \(itemURL.lastPathComponent)")
                    successCount += 1
                } else {
                    let errorMessage = "\(itemURL.lastPathComponent): 移动失败"
                    errorMessages.append(errorMessage)
                    print("❌ 移到垃圾箱失败: \(itemURL.lastPathComponent)")
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = itemsToTrash.count == 1 ?
                        "成功将 \(successCount) 个文件移到垃圾箱" :
                        "成功将 \(successCount) 个文件移到垃圾箱（共 \(itemsToTrash.count) 个）"
                    print("✅ \(message)")
                }
                
                self.viewModel.clearAllSelections()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.viewModel.triggerRefresh()
                    self.isRefreshing = false
                }
            }
        }
    }
    

    
    // 移动选中文件到另一个窗口激活的目录（支持多选）
    
    // 移动选中文件到另一个窗口激活的目录（支持多选）
    func moveItem() {
        let sourceItems = Array(viewModel.getCurrentSelectedItems())
        
        guard !sourceItems.isEmpty else {
            print("❌ 没有选中项可移动")
            return
        }
        
        let sourcePaneURL = getCurrentPaneURL()
        let targetPaneURL = viewModel.activePane == .right ? leftPaneURL : rightPaneURL
        
        if sourcePaneURL.path == targetPaneURL.path {
            showAlertSimple(title: "移动失败", message: "不能在同一目录内移动")
            return
        }
        
        var duplicateFiles: [URL] = []
        for sourceURL in sourceItems {
            let destinationURL = targetPaneURL.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                duplicateFiles.append(sourceURL)
            }
        }
        
        var shouldOverwriteAll = false
        var shouldSkipAll = false
        
        if !duplicateFiles.isEmpty {
            let alert = NSAlert()
            alert.messageText = "确认移动文件"
            
            let duplicateCount = duplicateFiles.count
            var duplicateInfo = "发现 \(duplicateCount) 个文件在目标位置已存在：\n\n"
            
            let displayCount = min(5, duplicateCount)
            for i in 0..<displayCount {
                duplicateInfo += "• \(duplicateFiles[i].lastPathComponent)\n"
            }
            
            if duplicateCount > 5 {
                duplicateInfo += "• ... 还有 \(duplicateCount - 5) 个文件\n"
            }
            
            duplicateInfo += "\n您希望如何处理这些文件？"
            alert.informativeText = duplicateInfo
            
            alert.addButton(withTitle: "全部覆盖")
            alert.addButton(withTitle: "全部放弃")
            alert.addButton(withTitle: "取消")
            
            let response = alert.runModal()
            
            switch response {
            case .alertFirstButtonReturn:
                shouldOverwriteAll = true
            case .alertSecondButtonReturn:
                shouldSkipAll = true
            default:
                return
            }
        }
        
        var totalBytes: Int64 = 0
        var fileSizes: [URL: Int64] = [:]
        
        for sourceURL in sourceItems {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                fileSizes[sourceURL] = 1024 * 1024
                totalBytes += 1024 * 1024
            } else {
                let size = getFileSize(sourceURL)
                fileSizes[sourceURL] = size
                totalBytes += size
            }
        }
        
        var successCount = 0
        var errorMessages: [String] = []
        var completedBytes: Int64 = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, sourceURL) in sourceItems.enumerated() {
                let destinationURL = targetPaneURL.appendingPathComponent(sourceURL.lastPathComponent)
                
                let fileExists = FileManager.default.fileExists(atPath: destinationURL.path)
                
                // 调试信息
                print("🔧 移动操作: \(sourceURL.path) -> \(destinationURL.path)")
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                print("🔧 源文件类型: \(isDirectory.boolValue ? "目录" : "文件")")
                print("🔧 源文件大小: \(getFileSize(sourceURL)) 字节")
                if fileExists {
                    if shouldSkipAll {
                        DispatchQueue.main.async {
                            errorMessages.append("\(sourceURL.lastPathComponent): 用户选择放弃覆盖")
                        }
                        continue
                    }
                    
                    if shouldOverwriteAll {
                        do {
                            try FileManager.default.removeItem(at: destinationURL)
                        } catch {
                            DispatchQueue.main.async {
                                errorMessages.append("\(sourceURL.lastPathComponent): 无法删除已存在的文件: \(error.localizedDescription)")
                            }
                            continue
                        }
                    }
                }
                
                let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
                let fileSize = fileAttributes?[.size] as? Int64 ?? 0
                
                DispatchQueue.main.async {
                    self.copyProgress = CopyProgress(
                        fileName: sourceURL.lastPathComponent,
                        progress: 0.0,
                        bytesPerSecond: 0,
                        estimatedTimeRemaining: 0,
                        isCompleted: false,
                        operation: "move",
                        currentFileIndex: index + 1,
                        totalFiles: sourceItems.count
                    )
                    self.showCopyProgress = true
                }
                
                do {
                    var lastProgressUpdate = Date()
                    var lastSpeedTime = Date()
                    var lastSpeedBytes: Int64 = 0
                    var currentSpeed: Double = 0.0
                    
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                    
                    if isDirectory.boolValue {
                        DispatchQueue.main.async {
                            self.copyProgress = CopyProgress(
                                fileName: sourceURL.lastPathComponent,
                                progress: 0.0,
                                bytesPerSecond: 0,
                                estimatedTimeRemaining: 0,
                                isCompleted: false,
                                operation: "move",
                                currentFileIndex: index + 1,
                                totalFiles: sourceItems.count
                            )
                        }
                        
                        // 本地目录移动
                        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                        
                        DispatchQueue.main.async {
                            self.copyProgress = CopyProgress(
                                fileName: sourceURL.lastPathComponent,
                                progress: 1.0,
                                bytesPerSecond: 0,
                                estimatedTimeRemaining: 0,
                                isCompleted: true,
                                operation: "move",
                                currentFileIndex: index + 1,
                                totalFiles: sourceItems.count
                            )
                        }
                    } else {
                        // 本地文件移动
                        try FileOperationService.moveFileWithProgress(
                            from: sourceURL,
                            to: destinationURL,
                            bufferSize: 1024 * 1024,
                            onProgress: { bytes in
                            let currentTime = Date()
                            let totalProgress = totalBytes > 0 ? Double(completedBytes + bytes) / Double(totalBytes) : 1.0
                            
                            let speedTimeElapsed = currentTime.timeIntervalSince(lastSpeedTime)
                            let speedBytesTransferred = Int64(bytes) - lastSpeedBytes
                            var bytesPerSecond: Double = 0.0
                            
                            if speedTimeElapsed > 0.1 {
                                bytesPerSecond = Double(speedBytesTransferred) / speedTimeElapsed
                                lastSpeedTime = currentTime
                                lastSpeedBytes = Int64(bytes)
                                currentSpeed = bytesPerSecond
                            } else if speedBytesTransferred > 0 {
                                if currentSpeed > 0 {
                                    bytesPerSecond = currentSpeed
                                } else {
                                    bytesPerSecond = 10 * 1024 * 1024
                                }
                            } else if bytes > 0 {
                                bytesPerSecond = 10 * 1024 * 1024
                            }
                            
                            let currentFileRemaining = fileSize - bytes
                            var totalRemainingBytes: Int64 = currentFileRemaining
                            
                            for i in (index + 1)..<sourceItems.count {
                                totalRemainingBytes += fileSizes[sourceItems[i]] ?? 0
                            }
                            
                            let estimatedTimeRemaining = bytesPerSecond > 0 ?
                                Double(totalRemainingBytes) / bytesPerSecond : 0
                            
                            let timeSinceLastUpdate = currentTime.timeIntervalSince(lastProgressUpdate)
                            let shouldUpdate = timeSinceLastUpdate >= 0.2 || bytes == fileSize
                            
                            if shouldUpdate {
                                DispatchQueue.main.async {
                                    self.copyProgress = CopyProgress(
                                        fileName: sourceURL.lastPathComponent,
                                        progress: totalProgress,
                                        bytesPerSecond: bytesPerSecond,
                                        estimatedTimeRemaining: estimatedTimeRemaining,
                                        isCompleted: false,
                                        operation: "move",
                                        currentFileIndex: index + 1,
                                        totalFiles: sourceItems.count
                                    )
                                }
                                lastProgressUpdate = currentTime
                            }
                        }
                    )
                    }
                    
                    completedBytes += fileSize
                    
                    DispatchQueue.main.async {
                        self.copyProgress = CopyProgress(
                            fileName: sourceURL.lastPathComponent,
                            progress: 1.0,
                            bytesPerSecond: 0,
                            estimatedTimeRemaining: 0,
                            isCompleted: true,
                            operation: "move",
                            currentFileIndex: index + 1,
                            totalFiles: sourceItems.count
                        )
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if index == sourceItems.count - 1 {
                                self.showCopyProgress = false
                            }
                        }
                    }
                    
                    print("✅ 成功移动: \(sourceURL.lastPathComponent) 到 \(targetPaneURL.path)")
                    successCount += 1
                } catch {
                    let errorMessage = "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
                    print("🔧🔧🔧 移动失败详细错误: \(error)")
                    print("🔧🔧🔧 错误描述: \(errorMessage)")
                    DispatchQueue.main.async {
                        errorMessages.append(errorMessage)
                    }
                    print("❌ 移动失败: \(errorMessage)")
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = sourceItems.count == 1 ?
                        "成功移动 \(successCount) 个文件" :
                        "成功移动 \(successCount) 个文件（共 \(sourceItems.count) 个）"
                    print("✅ \(message)")
                }
                
                if !errorMessages.isEmpty {
                    let fullMessage = "移动过程中发生以下错误：\n\n" + errorMessages.joined(separator: "\n")
                    self.showAlertSimple(title: "部分移动失败", message: fullMessage)
                }
                
                self.viewModel.clearAllSelections()
                
                // 重新获取targetPaneURL进行刷新检查
                let targetPaneURL = self.viewModel.activePane == .right ? self.leftPaneURL : self.rightPaneURL
                
                // 普通刷新
                print("🔧🔄 普通刷新")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.viewModel.triggerRefresh()
                }
            }
        }
    }
    
    // 建立新文件夹
    func createNewFolder() {
        let currentURL = getCurrentPaneURL()
        
        let alert = NSAlert()
        alert.messageText = "新建文件夹"
        alert.informativeText = "请输入文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = "新文件夹"
        alert.accessoryView = textField
        textField.becomeFirstResponder()
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folderName.isEmpty else {
                showAlertSimple(title: "创建失败", message: "文件夹名称不能为空")
                return
            }
            
            let folderURL = currentURL.appendingPathComponent(folderName)
            
            if FileManager.default.fileExists(atPath: folderURL.path) {
                showAlertSimple(title: "创建失败", message: "已存在同名的文件夹")
                return
            }
            
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false, attributes: nil)
                print("✅ 成功创建文件夹: \(folderName)")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.triggerRefresh()
                }
            } catch {
                print("❌ 创建文件夹失败: \(error.localizedDescription)")
                showAlertSimple(title: "创建失败", message: error.localizedDescription)
            }
        }
    }
    
    // 显示简单的警告对话框
    func showAlertSimple(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // 粘贴文件（从剪贴板）
    func pasteItem() {
        let pasteboard = NSPasteboard.general
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            print("❌ 剪贴板中没有文件URL")
            showAlertSimple(title: "粘贴失败", message: "剪贴板中没有可粘贴的文件")
            return
        }
        
        let targetURL = getCurrentPaneURL()
        let activePane = viewModel.activePane
        print("🔥 开始粘贴操作，目标面板: \(activePane == .left ? "左" : "右")，目标目录: \(targetURL.path)")
        
        // 确保目标目录存在
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ 无法创建目标目录: \(targetURL.path) - \(error.localizedDescription)")
            showAlertSimple(title: "粘贴失败", message: "无法访问目标目录: \(error.localizedDescription)")
            return
        }
        
        var duplicateFiles: [URL] = []
        for url in urls {
            let destinationURL = targetURL.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                duplicateFiles.append(url)
            }
        }
        
        var shouldReplaceAll = false
        if !duplicateFiles.isEmpty {
            let alert = NSAlert()
            alert.messageText = "确认覆盖"
            
            let duplicateCount = duplicateFiles.count
            var duplicateInfo = "发现 \(duplicateCount) 个文件在目标位置已存在：\n\n"
            
            let displayCount = min(5, duplicateCount)
            for i in 0..<displayCount {
                duplicateInfo += "• \(duplicateFiles[i].lastPathComponent)\n"
            }
            
            if duplicateCount > 5 {
                duplicateInfo += "• ... 还有 \(duplicateCount - 5) 个文件\n"
            }
            
            duplicateInfo += "\n您希望如何处理这些文件？"
            alert.informativeText = duplicateInfo
            alert.alertStyle = .warning
            alert.addButton(withTitle: "全部覆盖")
            alert.addButton(withTitle: "全部放弃")
            
            let response = alert.runModal()
            shouldReplaceAll = (response == .alertFirstButtonReturn)
        }
        
        var successCount = 0
        var errorMessages: [String] = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            for url in urls {
                let destinationURL = targetURL.appendingPathComponent(url.lastPathComponent)
                
                // 检查目标位置是否已存在同名文件
                let fileExists = FileManager.default.fileExists(atPath: destinationURL.path)
                
                if fileExists {
                    if !shouldReplaceAll {
                        DispatchQueue.main.async {
                            errorMessages.append("\(url.lastPathComponent): 用户选择放弃覆盖")
                        }
                        continue
                    }
                    
                    // 如果选择覆盖，先删除目标文件
                    do {
                        try FileManager.default.removeItem(at: destinationURL)
                    } catch {
                        DispatchQueue.main.async {
                            errorMessages.append("\(url.lastPathComponent): 无法删除已存在的文件: \(error.localizedDescription)")
                        }
                        continue
                    }
                }
                
                do {
                    // 复制文件
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    
                    print("✅ 成功粘贴: \(url.lastPathComponent) 到 \(targetURL.path)")
                    successCount += 1
                } catch {
                    let errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
                    DispatchQueue.main.async {
                        errorMessages.append(errorMessage)
                    }
                    print("❌ 粘贴失败: \(errorMessage)")
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = urls.count == 1 ?
                        "成功粘贴 \(successCount) 个文件" :
                        "成功粘贴 \(successCount) 个文件（共 \(urls.count) 个）"
                    print("✅ \(message)")
                }
                
                if !errorMessages.isEmpty {
                    let fullMessage = "粘贴过程中发生以下错误：\n\n" + errorMessages.joined(separator: "\n")
                    self.showAlertSimple(title: "部分粘贴失败", message: fullMessage)
                }
                
                // 刷新视图
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.viewModel.triggerRefresh()
                }
            }
        }
    }
}
