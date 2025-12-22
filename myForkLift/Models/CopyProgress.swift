//
//  CopyProgress.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import Foundation

/// 文件复制/移动进度数据结构
struct CopyProgress: Identifiable {
    let id = UUID()
    let fileName: String // 显示的文件名（对于目录，这是当前正在复制的文件名）
    var progress: Double
    var bytesPerSecond: Double
    var estimatedTimeRemaining: TimeInterval
    var isCompleted: Bool
    let operation: String // "copy" 或 "move"
    let currentFileIndex: Int? // 当前正在复制的文件索引（从1开始）
    let totalFiles: Int? // 总文件数
    let isDirectoryOperation: Bool // 是否为目录操作
    let currentFileName: String? // 当前正在复制的具体文件名（用于目录操作）
}


