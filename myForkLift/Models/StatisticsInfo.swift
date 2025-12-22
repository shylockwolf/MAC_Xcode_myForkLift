//
//  StatisticsInfo.swift
//  DWBrowser
//
//  Created by Your Name on 2025/12/22.
//

import Foundation

/// 目录统计进度数据结构
struct StatisticsInfo: Identifiable {
    let id = UUID()
    var totalFiles: Int64
    var totalFolders: Int64
    var totalSize: Int64
    var currentFile: String
    var progress: Double
    var isCompleted: Bool = false
    var isCancelled: Bool = false
}
