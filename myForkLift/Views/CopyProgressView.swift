//
//  CopyProgressView.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import SwiftUI
import AppKit

/// 复制/移动进度窗口
struct CopyProgressView: View {
    let progress: CopyProgress
    let onCancel: () -> Void
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 8) {
            let _ = print("🔍 CopyProgressView渲染: \(progress.fileName), 进度: \(progress.progress), 完成: \(progress.isCompleted)")
            // 操作类型和文件名
            HStack {
                Text(progress.operation == "copy" ? "复制" : "移动")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.blue)
                
                if progress.isDirectoryOperation, let currentFileName = progress.currentFileName {
                    // 目录操作时显示当前文件名
                    Text(currentFileName)
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    // 单文件操作或完成状态
                    Text(progress.fileName)
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            
            // 进度条
            ProgressView(value: progress.progress)
                .progressViewStyle(LinearProgressViewStyle())
            
            // 速度、文件计数、剩余时间和取消按钮
            HStack {
                Text(formatBytes(bytesPerSecond: progress.bytesPerSecond) + "/s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 文件计数显示（如：2/5）
                if let currentFileIndex = progress.currentFileIndex, let totalFiles = progress.totalFiles {
                    Text("\(currentFileIndex)/\(totalFiles)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !progress.isCompleted {
                    Text(formatTime(interval: progress.estimatedTimeRemaining))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 取消按钮或完成状态
                if !progress.isCompleted {
                    Button("取消") {
                        print("🔴 取消按钮被点击")
                        onCancel()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(4)
                    .onAppear {
                        print("🔴 取消按钮出现，isCompleted: \(progress.isCompleted)")
                    }
                    .buttonStyle(PlainButtonStyle()) // 确保按钮样式正确应用
                } else {
                    Text("完成")
                        .font(.caption)
                        .foregroundColor(.green)
                        .onAppear {
                            print("🟢 完成状态显示，isCompleted: \(progress.isCompleted)")
                        }
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
    
    private func formatBytes(bytesPerSecond: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var bytes = bytesPerSecond
        var unitIndex = 0
        
        while bytes >= 1024 && unitIndex < units.count - 1 {
            bytes /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", bytes, units[unitIndex])
    }
    
    private func formatTime(interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}


