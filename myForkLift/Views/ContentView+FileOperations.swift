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
        } else {
            showAlertSimple(title: "复制失败", message: "无法将选中项复制到剪贴板")
        }
    }
    
    // 取消复制操作
    func cancelCopyOperation() {
        isCopyOperationCancelled = true
        showCopyProgress = false
        copyProgress = nil
        
        // 清空选择
        viewModel.clearAllSelections()
        
        // 刷新文件面板
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.viewModel.triggerRefresh()
        }
    }
    
    // 复制选中文件到另一个窗口激活的目录（支持多选，带进度显示）
    func copyToAnotherPane() {
        // 重置所有与复制操作相关的状态，确保新操作能正常开始
        isCopyOperationCancelled = false
        showCopyProgress = false
        copyProgress = nil
        maxProgress = 0.0 // 重置最大进度值，确保新操作从0开始
        
        let sourceItems = Array(viewModel.getCurrentSelectedItems())
        
        guard !sourceItems.isEmpty else {
            return
        }
        
        let targetURL = viewModel.activePane == .right ? leftPaneURL : rightPaneURL
        
        // 确保目标目录存在
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
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
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
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
                        progress: 0.01,
                        bytesPerSecond: 0,
                        estimatedTimeRemaining: 0,
                        isCompleted: false,
                        operation: "copy",
                        currentFileIndex: index + 1,
                        totalFiles: sourceItems.count,
                        isDirectoryOperation: false,
                        currentFileName: nil
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
                        // 使用带进度的目录复制方法，显示具体文件名
                        var lastProgressUpdate = Date()
                        var lastSpeedTime = Date()
                        var lastSpeedBytes: Int64 = 0
                        var currentSpeed: Double = 0.0
                        var speedSamples: [Double] = [] // 存储最近的速度样本，用于计算平均速度
                        let maxSpeedSamples = 10 // 最多保留10个样本
                        
                        DispatchQueue.main.async {
                            self.copyProgress = CopyProgress(
                                fileName: sourceURL.lastPathComponent,
                                progress: 0.01,
                                bytesPerSecond: 0,
                                estimatedTimeRemaining: 0,
                                isCompleted: false,
                                operation: "copy",
                                currentFileIndex: index + 1,
                                totalFiles: sourceItems.count,
                                isDirectoryOperation: true,
                                currentFileName: "准备中..."
                            )
                        }
                        
                        try FileOperationService.copyDirectoryWithProgress(
                            from: sourceURL,
                            to: destinationURL,
                            bufferSize: 1024 * 1024,
                            onProgress: { bytes, currentFileName in
                                let currentTime = Date()
                                let totalProgress = totalBytes > 0 ? Double(completedBytes + bytes) / Double(totalBytes) : 1.0
                                
                                let speedTimeElapsed = currentTime.timeIntervalSince(lastSpeedTime)
                                let speedBytesTransferred = Int64(bytes) - lastSpeedBytes
                                var bytesPerSecond: Double = 0.0
                                
                                if speedTimeElapsed > 0.1 {
                                    let currentSpeedSample = Double(speedBytesTransferred) / speedTimeElapsed
                                    
                                    // 添加到速度样本数组
                                    speedSamples.append(currentSpeedSample)
                                    if speedSamples.count > maxSpeedSamples {
                                        speedSamples.removeFirst() // 移除最旧的样本
                                    }
                                    
                                    // 计算平均速度
                                    bytesPerSecond = speedSamples.reduce(0, +) / Double(speedSamples.count)
                                    currentSpeed = bytesPerSecond
                                    
                                    lastSpeedTime = currentTime
                                    lastSpeedBytes = Int64(bytes)
                                } else if speedBytesTransferred > 0 {
                                    if currentSpeed > 0 {
                                        bytesPerSecond = currentSpeed
                                    } else {
                                        bytesPerSecond = 10 * 1024 * 1024
                                    }
                                } else if bytes > 0 {
                                    bytesPerSecond = 10 * 1024 * 1024
                                }
                                
                                let timeSinceLastUpdate = currentTime.timeIntervalSince(lastProgressUpdate)
                                let shouldUpdate = timeSinceLastUpdate >= 0.2 || currentFileName == "完成"
                                
                                if shouldUpdate {
                                    // 确保进度条只前进不后退
                                    let displayProgress = totalProgress > self.maxProgress ? totalProgress : self.maxProgress
                                    if displayProgress > self.maxProgress {
                                        self.maxProgress = displayProgress
                                    }
                                    
                                    DispatchQueue.main.async {
                                        self.copyProgress = CopyProgress(
                                            fileName: sourceURL.lastPathComponent,
                                            progress: displayProgress,
                                            bytesPerSecond: bytesPerSecond,
                                            estimatedTimeRemaining: bytesPerSecond > 0 ?
                                                Double((fileSizes[sourceURL] ?? 0) - bytes) / bytesPerSecond : 0,
                                            isCompleted: currentFileName == "完成",
                                            operation: "copy",
                                            currentFileIndex: index + 1,
                                            totalFiles: sourceItems.count,
                                            isDirectoryOperation: true,
                                            currentFileName: currentFileName == "完成" ? sourceURL.lastPathComponent : currentFileName
                                        )
                                    }
                                    lastProgressUpdate = currentTime
                                }
                            },
                            shouldCancel: {
                                return self.isCopyOperationCancelled
                            }
                        )
                    } else {
                        // 本地文件之间复制
                    // 复制文件（使用自定义进度方法）
                    var speedSamples: [Double] = [] // 存储最近的速度样本，用于计算平均速度
                    let maxSpeedSamples = 10 // 最多保留10个样本
                    
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
                                let currentSpeedSample = Double(speedBytesTransferred) / speedTimeElapsed
                                
                                // 添加到速度样本数组
                                speedSamples.append(currentSpeedSample)
                                if speedSamples.count > maxSpeedSamples {
                                    speedSamples.removeFirst() // 移除最旧的样本
                                }
                                
                                // 计算平均速度
                                bytesPerSecond = speedSamples.reduce(0, +) / Double(speedSamples.count)
                                currentSpeed = bytesPerSecond
                                
                                lastSpeedTime = currentTime
                                lastSpeedBytes = Int64(bytes)
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
                                    // 确保进度条只前进不后退
                                    let displayProgress = totalProgress > self.maxProgress ? totalProgress : self.maxProgress
                                    if displayProgress > self.maxProgress {
                                        self.maxProgress = displayProgress
                                    }
                                    
                                    DispatchQueue.main.async {
                                        self.copyProgress = CopyProgress(
                                            fileName: sourceURL.lastPathComponent,
                                            progress: displayProgress,
                                            bytesPerSecond: bytesPerSecond,
                                            estimatedTimeRemaining: estimatedTimeRemaining,
                                            isCompleted: false,
                                            operation: "copy",
                                            currentFileIndex: index + 1,
                                            totalFiles: sourceItems.count,
                                            isDirectoryOperation: false,
                                            currentFileName: nil
                                        )
                                    }
                                    lastProgressUpdate = currentTime
                                }
                            },
                            shouldCancel: {
                                return self.isCopyOperationCancelled
                            }
                        )
                    }
                    
                    let currentTotalCompleted = fileSizes[sourceURL] ?? fileSize
                    completedBytes += currentTotalCompleted
                    
                    DispatchQueue.main.async {
                        // 使用实际已完成字节数计算进度
                        let finalProgress = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 1.0
                        // 确保进度条只前进不后退
                        let displayProgress = finalProgress > self.maxProgress ? finalProgress : self.maxProgress
                        if displayProgress > self.maxProgress {
                            self.maxProgress = displayProgress
                        }
                        
                        self.copyProgress = CopyProgress(
                            fileName: sourceURL.lastPathComponent,
                            progress: displayProgress,
                            bytesPerSecond: 0,
                            estimatedTimeRemaining: 0,
                            isCompleted: true,
                            operation: "copy",
                            currentFileIndex: index + 1,
                            totalFiles: sourceItems.count,
                            isDirectoryOperation: false,
                            currentFileName: nil
                        )
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if index == sourceItems.count - 1 {
                                self.showCopyProgress = false
                            }
                        }
                    }
                    
                    successCount += 1
                    
                } catch {
                    // 检查是否为取消操作，如果是则不显示错误消息
                    let nsError = error as NSError
                    if nsError.code == -999 && nsError.domain == "DWBrowser" {
                        // 不添加到错误消息列表
                        // 取消所有文件的复制，跳出循环
                        break
                    } else {
                        let errorMessage = "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
                        DispatchQueue.main.async {
                            errorMessages.append(errorMessage)
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = sourceItems.count == 1 ?
                        "成功复制 \(successCount) 个文件" :
                        "成功复制 \(successCount) 个文件（共 \(sourceItems.count) 个）"
                }
                
                if !errorMessages.isEmpty {
                    let fullMessage = "复制过程中发生以下错误：\n\n" + errorMessages.joined(separator: "\n")
                    self.showAlertSimple(title: "部分复制失败", message: fullMessage)
                }
                
                self.viewModel.clearAllSelections()
                
                // 重新获取targetPaneURL进行刷新检查
                let targetPaneURL = self.viewModel.activePane == .right ? self.leftPaneURL : self.rightPaneURL
                
                // 普通刷新
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
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            var errorMessages: [String] = []
            
            for itemURL in itemsToTrash {
                if FileOperationService.moveItemToTrashSync(itemURL) {
                    successCount += 1
                } else {
                    let errorMessage = "\(itemURL.lastPathComponent): 移动失败"
                    errorMessages.append(errorMessage)
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = itemsToTrash.count == 1 ?
                        "成功将 \(successCount) 个文件移到垃圾箱" :
                        "成功将 \(successCount) 个文件移到垃圾箱（共 \(itemsToTrash.count) 个）"
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
        // 重置所有与移动操作相关的状态，确保新操作能正常开始
        isCopyOperationCancelled = false
        showCopyProgress = false
        copyProgress = nil
        maxProgress = 0.0 // 重置最大进度值，确保新操作从0开始
        
        let sourceItems = Array(viewModel.getCurrentSelectedItems())
        
        guard !sourceItems.isEmpty else {
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, sourceURL) in sourceItems.enumerated() {
                let destinationURL = targetPaneURL.appendingPathComponent(sourceURL.lastPathComponent)
                
                let fileExists = FileManager.default.fileExists(atPath: destinationURL.path)
                
                // 调试信息
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
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
                        progress: 0.01,
                        bytesPerSecond: 0,
                        estimatedTimeRemaining: 0,
                        isCompleted: false,
                        operation: "move",
                        currentFileIndex: index + 1,
                        totalFiles: sourceItems.count,
                        isDirectoryOperation: false,
                        currentFileName: nil
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
                                progress: 0.01,
                                bytesPerSecond: 0,
                                estimatedTimeRemaining: 0,
                                isCompleted: false,
                                operation: "move",
                                currentFileIndex: index + 1,
                                totalFiles: sourceItems.count,
                                isDirectoryOperation: true,
                                currentFileName: "准备中..."
                            )
                        }
                        
                        // 本地目录移动 - 使用复制+删除的方式以支持进度显示
                        var speedSamples: [Double] = [] // 存储最近的速度样本，用于计算平均速度
                        let maxSpeedSamples = 10 // 最多保留10个样本
                        
                        try FileOperationService.copyDirectoryWithProgress(
                            from: sourceURL,
                            to: destinationURL,
                            bufferSize: 1024 * 1024,
                            onProgress: { bytes, currentFileName in
                                let currentTime = Date()
                                let totalProgress = totalBytes > 0 ? Double(completedBytes + bytes) / Double(totalBytes) : 1.0
                                
                                let speedTimeElapsed = currentTime.timeIntervalSince(lastSpeedTime)
                                let speedBytesTransferred = Int64(bytes) - lastSpeedBytes
                                var bytesPerSecond: Double = 0.0
                                
                                if speedTimeElapsed > 0.1 {
                                    let currentSpeedSample = Double(speedBytesTransferred) / speedTimeElapsed
                                    
                                    // 添加到速度样本数组
                                    speedSamples.append(currentSpeedSample)
                                    if speedSamples.count > maxSpeedSamples {
                                        speedSamples.removeFirst() // 移除最旧的样本
                                    }
                                    
                                    // 计算平均速度
                                    bytesPerSecond = speedSamples.reduce(0, +) / Double(speedSamples.count)
                                    currentSpeed = bytesPerSecond
                                    
                                    lastSpeedTime = currentTime
                                    lastSpeedBytes = Int64(bytes)
                                } else if speedBytesTransferred > 0 {
                                    if currentSpeed > 0 {
                                        bytesPerSecond = currentSpeed
                                    } else {
                                        bytesPerSecond = 10 * 1024 * 1024
                                    }
                                } else if bytes > 0 {
                                    bytesPerSecond = 10 * 1024 * 1024
                                }
                                
                                let timeSinceLastUpdate = currentTime.timeIntervalSince(lastProgressUpdate)
                                let shouldUpdate = timeSinceLastUpdate >= 0.2 || currentFileName == "完成"
                                
                                if shouldUpdate {
                                    // 确保进度条只前进不后退
                                    let displayProgress = totalProgress > self.maxProgress ? totalProgress : self.maxProgress
                                    if displayProgress > self.maxProgress {
                                        self.maxProgress = displayProgress
                                    }
                                    
                                    DispatchQueue.main.async {
                                        self.copyProgress = CopyProgress(
                                            fileName: sourceURL.lastPathComponent,
                                            progress: displayProgress,
                                            bytesPerSecond: bytesPerSecond,
                                            estimatedTimeRemaining: bytesPerSecond > 0 ?
                                                Double((fileSizes[sourceURL] ?? 0) - bytes) / bytesPerSecond : 0,
                                            isCompleted: currentFileName == "完成",
                                            operation: "move",
                                            currentFileIndex: index + 1,
                                            totalFiles: sourceItems.count,
                                            isDirectoryOperation: true,
                                            currentFileName: currentFileName == "完成" ? sourceURL.lastPathComponent : currentFileName
                                        )
                                    }
                                    lastProgressUpdate = currentTime
                                }
                            },
                            shouldCancel: {
                                return self.isCopyOperationCancelled
                            }
                        )
                        
                        // 移动完成后删除源目录
                        if !isCopyOperationCancelled {
                            try FileManager.default.removeItem(at: sourceURL)
                        }
                        
                        DispatchQueue.main.async {
                            // 使用实际已完成字节数计算进度
                            let finalProgress = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 1.0
                            // 确保进度条只前进不后退
                            let displayProgress = finalProgress > self.maxProgress ? finalProgress : self.maxProgress
                            if displayProgress > self.maxProgress {
                                self.maxProgress = displayProgress
                            }
                            
                            self.copyProgress = CopyProgress(
                                fileName: sourceURL.lastPathComponent,
                                progress: displayProgress,
                                bytesPerSecond: 0,
                                estimatedTimeRemaining: 0,
                                isCompleted: true,
                                operation: "move",
                                currentFileIndex: index + 1,
                                totalFiles: sourceItems.count,
                                isDirectoryOperation: true,
                                currentFileName: sourceURL.lastPathComponent
                            )
                        }
                    } else {
                        // 本地文件移动
                        var speedSamples: [Double] = [] // 存储最近的速度样本，用于计算平均速度
                        let maxSpeedSamples = 10 // 最多保留10个样本
                        
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
                                    let currentSpeedSample = Double(speedBytesTransferred) / speedTimeElapsed
                                    
                                    // 添加到速度样本数组
                                    speedSamples.append(currentSpeedSample)
                                    if speedSamples.count > maxSpeedSamples {
                                        speedSamples.removeFirst() // 移除最旧的样本
                                    }
                                    
                                    // 计算平均速度
                                    bytesPerSecond = speedSamples.reduce(0, +) / Double(speedSamples.count)
                                    currentSpeed = bytesPerSecond
                                    
                                    lastSpeedTime = currentTime
                                    lastSpeedBytes = Int64(bytes)
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
                                    // 确保进度条只前进不后退
                                    let displayProgress = totalProgress > self.maxProgress ? totalProgress : self.maxProgress
                                    if displayProgress > self.maxProgress {
                                        self.maxProgress = displayProgress
                                    }
                                    
                                    DispatchQueue.main.async {
                                        self.copyProgress = CopyProgress(
                                            fileName: sourceURL.lastPathComponent,
                                            progress: displayProgress,
                                            bytesPerSecond: bytesPerSecond,
                                            estimatedTimeRemaining: estimatedTimeRemaining,
                                            isCompleted: false,
                                            operation: "move",
                                            currentFileIndex: index + 1,
                                            totalFiles: sourceItems.count,
                                            isDirectoryOperation: false,
                                            currentFileName: nil
                                        )
                                    }
                                    lastProgressUpdate = currentTime
                                }
                            },
                            shouldCancel: {
                                return self.isCopyOperationCancelled
                            }
                        )
                    }
                    
                    // 使用正确的文件大小更新已完成字节数
                    let currentTotalCompleted = fileSizes[sourceURL] ?? fileSize
                    completedBytes += currentTotalCompleted
                    
                    DispatchQueue.main.async {
                        // 使用实际已完成字节数计算进度
                        let finalProgress = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 1.0
                        // 确保进度条只前进不后退
                        let displayProgress = finalProgress > self.maxProgress ? finalProgress : self.maxProgress
                        if displayProgress > self.maxProgress {
                            self.maxProgress = displayProgress
                        }
                        
                        self.copyProgress = CopyProgress(
                            fileName: sourceURL.lastPathComponent,
                            progress: displayProgress,
                            bytesPerSecond: 0,
                            estimatedTimeRemaining: 0,
                            isCompleted: true,
                            operation: "move",
                            currentFileIndex: index + 1,
                            totalFiles: sourceItems.count,
                            isDirectoryOperation: false,
                            currentFileName: nil
                        )
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if index == sourceItems.count - 1 {
                                self.showCopyProgress = false
                            }
                        }
                    }
                    
                    successCount += 1
                } catch {
                    // 检查是否为取消操作，如果是则不显示错误消息
                    let nsError = error as NSError
                    if nsError.code == -999 && nsError.domain == "DWBrowser" {
                        // 不添加到错误消息列表
                        // 取消所有文件的移动，跳出循环
                        break
                    } else {
                        let errorMessage = "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
                        DispatchQueue.main.async {
                            errorMessages.append(errorMessage)
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = sourceItems.count == 1 ?
                        "成功移动 \(successCount) 个文件" :
                        "成功移动 \(successCount) 个文件（共 \(sourceItems.count) 个）"
                }
                
                if !errorMessages.isEmpty {
                    let fullMessage = "移动过程中发生以下错误：\n\n" + errorMessages.joined(separator: "\n")
                    self.showAlertSimple(title: "部分移动失败", message: fullMessage)
                }
                
                self.viewModel.clearAllSelections()
                
                // 重新获取targetPaneURL进行刷新检查
                let targetPaneURL = self.viewModel.activePane == .right ? self.leftPaneURL : self.rightPaneURL
                
                // 普通刷新
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
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.triggerRefresh()
                }
            } catch {
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
            showAlertSimple(title: "粘贴失败", message: "剪贴板中没有可粘贴的文件")
            return
        }
        
        let targetURL = getCurrentPaneURL()
        let activePane = viewModel.activePane
        
        // 确保目标目录存在
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
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
                    
                    successCount += 1
                } catch {
                    let errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
                    DispatchQueue.main.async {
                        errorMessages.append(errorMessage)
                    }
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = urls.count == 1 ?
                        "成功粘贴 \(successCount) 个文件" :
                        "成功粘贴 \(successCount) 个文件（共 \(urls.count) 个）"
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
