//
//  FileOperationService.swift
//  DWBrowser
//
//  提供底层文件复制/移动/丢垃圾桶等操作的封装，带进度回调。
//

import Foundation

enum FileOperationService {
    
    /// 带进度的文件复制方法
    static func copyFileWithProgress(
        from sourceURL: URL,
        to destinationURL: URL,
        bufferSize: Int,
        onProgress: @escaping (Int64) -> Void,
        shouldCancel: @escaping () -> Bool // 检查是否应该取消
    ) throws {
        
        // 确保目标目录存在
        let destinationDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)
        
        let sourceSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as! Int64
        
        // 创建临时文件
        let tempURL = destinationURL.appendingPathExtension("tmp")
        
        // 使用流式复制，实时跟踪进度
        guard let inputStream = InputStream(url: sourceURL),
              let outputStream = OutputStream(url: tempURL, append: false) else {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "无法创建文件流"
            ])
        }
        
        inputStream.open()
        outputStream.open()
        
        defer {
            inputStream.close()
            outputStream.close()
        }
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }
        
        var totalBytesRead: Int64 = 0
        var lastProgressTime = Date()
        
        while inputStream.hasBytesAvailable && !shouldCancel() {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                // 读取错误
                if let streamError = inputStream.streamError {
                    throw streamError
                }
                break
            } else if bytesRead == 0 {
                // 文件读取完毕
                break
            }
            
            // 检查是否被取消
            if shouldCancel() {
                throw NSError(domain: "DWBrowser", code: -999, userInfo: [
                    NSLocalizedDescriptionKey: "操作被用户取消"
                ])
            }
            
            // 写入输出流
            var bytesWritten = 0
            while bytesWritten < bytesRead {
                let written = outputStream.write(buffer + bytesWritten, maxLength: bytesRead - bytesWritten)
                if written < 0 {
                    // 写入错误
                    if let streamError = outputStream.streamError {
                        throw streamError
                    }
                    break
                } else if written == 0 {
                    throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "写入文件失败"
                    ])
                }
                bytesWritten += written
            }
            
            totalBytesRead += Int64(bytesRead)
            
        // 更新进度（限制更新频率，避免过于频繁的UI更新）
        let currentTime = Date()
        if currentTime.timeIntervalSince(lastProgressTime) >= 0.05 || totalBytesRead == sourceSize { // 提高更新频率到0.05秒
            onProgress(totalBytesRead)
            lastProgressTime = currentTime
        }
        }
        
        // 检查是否被取消
        if shouldCancel() {
            try? FileManager.default.removeItem(at: tempURL)
            throw NSError(domain: "DWBrowser", code: -999, userInfo: [
                NSLocalizedDescriptionKey: "操作被用户取消"
            ])
        }
        
        // 验证复制结果
        let tempSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as! Int64
        
        if sourceSize != tempSize {
            try? FileManager.default.removeItem(at: tempURL)
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "文件复制不完整：源文件 \(sourceSize) 字节，目标文件 \(tempSize) 字节"
            ])
        }
        
        // 重命名为最终文件名
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
    }
    
    /// 带进度的目录复制方法
    static func copyDirectoryWithProgress(
        from sourceURL: URL,
        to destinationURL: URL,
        bufferSize: Int,
        onProgress: @escaping (Int64, String) -> Void, // (bytes, currentFileName)
        shouldCancel: @escaping () -> Bool // 检查是否应该取消
    ) throws {
        
        // 确保目标目录存在
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        
        var totalBytesCopied: Int64 = 0
        var currentFileName = ""
        
        // 使用枚举器递归遍历目录
        guard let enumerator = FileManager.default.enumerator(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "无法创建目录枚举器"
            ])
        }
        
        // 首先收集所有文件和目录信息
        var itemsToCopy: [(URL, URL, Bool, Int64)] = [] // (source, destination, isDirectory, size)
        
        for case let fileURL as URL in enumerator {
            // 获取相对路径
            let relativePath = fileURL.path.replacingOccurrences(of: sourceURL.path, with: "")
            if relativePath.isEmpty { continue }
            
            let destinationFileURL = destinationURL.appendingPathComponent(String(relativePath.dropFirst()))
            
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
            
            let size: Int64
            if isDirectory.boolValue {
                size = 0
            } else {
                size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
            }
            
            itemsToCopy.append((fileURL, destinationFileURL, isDirectory.boolValue, size))
        }
        
        
        // 逐个复制项目
        for (index, (sourceItemURL, destItemURL, isDir, itemSize)) in itemsToCopy.enumerated() {
            // 检查是否被取消
            if shouldCancel() {
                throw NSError(domain: "DWBrowser", code: -999, userInfo: [
                    NSLocalizedDescriptionKey: "目录复制操作被用户取消"
                ])
            }
            
            currentFileName = sourceItemURL.lastPathComponent
            
            // 更新当前文件名
            onProgress(totalBytesCopied, currentFileName)
            
            if isDir {
                // 创建目录
                try FileManager.default.createDirectory(at: destItemURL, withIntermediateDirectories: true, attributes: nil)
            } else {
                // 复制文件
                
                // 使用流式复制单个文件
                guard let inputStream = InputStream(url: sourceItemURL),
                      let outputStream = OutputStream(url: destItemURL, append: false) else {
                    throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "无法创建文件流: \(currentFileName)"
                    ])
                }
                
                inputStream.open()
                outputStream.open()
                
                defer {
                    inputStream.close()
                    outputStream.close()
                }
                
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer {
                    buffer.deallocate()
                }
                
                var fileBytesRead: Int64 = 0
                var lastProgressTime = Date()
                
                while inputStream.hasBytesAvailable && !shouldCancel() {
                    let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
                    if bytesRead < 0 {
                        if let streamError = inputStream.streamError {
                            throw streamError
                        }
                        break
                    } else if bytesRead == 0 {
                        break
                    }
                    
                    // 检查是否被取消
                    if shouldCancel() {
                        throw NSError(domain: "DWBrowser", code: -999, userInfo: [
                            NSLocalizedDescriptionKey: "操作被用户取消"
                        ])
                    }
                    
                    var bytesWritten = 0
                    while bytesWritten < bytesRead {
                        let written = outputStream.write(buffer + bytesWritten, maxLength: bytesRead - bytesWritten)
                        if written < 0 {
                            if let streamError = outputStream.streamError {
                                throw streamError
                            }
                            break
                        } else if written == 0 {
                            throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                                NSLocalizedDescriptionKey: "写入文件失败: \(currentFileName)"
                            ])
                        }
                        bytesWritten += written
                    }
                    
                    fileBytesRead += Int64(bytesRead)
                    totalBytesCopied += Int64(bytesRead)
                    
                    // 更新进度
                    let currentTime = Date()
                    if currentTime.timeIntervalSince(lastProgressTime) >= 0.2 || fileBytesRead == itemSize {
                        onProgress(totalBytesCopied, currentFileName)
                        lastProgressTime = currentTime
                    }
                }
                
            }
        }
        
        // 最终进度更新
        onProgress(totalBytesCopied, "完成")
    }
    
    /// 带进度的文件移动方法（复制再删除）
    static func moveFileWithProgress(
        from sourceURL: URL,
        to destinationURL: URL,
        bufferSize: Int,
        onProgress: @escaping (Int64) -> Void,
        shouldCancel: @escaping () -> Bool
    ) throws {
        
        do {
            try copyFileWithProgress(from: sourceURL, to: destinationURL, bufferSize: bufferSize, onProgress: onProgress, shouldCancel: shouldCancel)
            
            // 验证目标文件确实存在且大小正确
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                let destSize = try FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as! Int64
                let sourceSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as! Int64
                
                if destSize == sourceSize {
                    try FileManager.default.removeItem(at: sourceURL)
                } else {
                    throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "目标文件大小不正确，取消删除源文件"
                    ])
                }
            } else {
                throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "目标文件不存在，无法完成移动操作"
                ])
            }
        } catch {
            throw error
        }
    }
    
    /// 同步移动文件到垃圾箱，适合在后台线程调用
    @discardableResult
    static func moveItemToTrashSync(_ itemURL: URL) -> Bool {
        do {
            var resultURL: NSURL?
            try FileManager.default.trashItem(at: itemURL, resultingItemURL: &resultURL)
            return true
        } catch {
            return false
        }
    }
}


