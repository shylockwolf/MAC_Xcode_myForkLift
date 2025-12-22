//
//  StatisticsWindow.swift
//  DWBrowser
//
//  Created by Your Name on 2025/12/22.
//

import SwiftUI
import Foundation

/// 目录统计窗口视图
struct StatisticsWindow: View {
    @Binding var statisticsInfo: StatisticsInfo
    var onOK: (() -> Void)?
    var onCancel: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 12) {
            // 标题
            Text("目录统计")
                .font(.title3)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 进度条
            ProgressView(value: statisticsInfo.progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 16)
            

            
            // 统计信息
            HStack {
                VStack(alignment: .leading) {
                    Text("文件总数:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("文件夹数:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("总大小:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .trailing) {
                    Text("\(statisticsInfo.totalFiles)")
                        .font(.caption)
                    Text("\(statisticsInfo.totalFolders)")
                        .font(.caption)
                    Text(formatBytes(bytes: Double(statisticsInfo.totalSize)))
                        .font(.caption)
                }
                Spacer()
            }
            
            // 按钮
            HStack {
                Button(action: {
                    statisticsInfo.isCompleted = true
                    onOK?()
                }) {
                    Text("OK")
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .disabled(statisticsInfo.isCompleted && statisticsInfo.isCancelled)
                
                Spacer()
                
                if !statisticsInfo.isCompleted && !statisticsInfo.isCancelled {
                    Button(action: {
                        statisticsInfo.isCancelled = true
                        onCancel?()
                    }) {
                        Text("取消")
                            .font(.caption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 320, minHeight: 150)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 12)
    }
    
    /// 格式化字节数显示
    private func formatBytes(bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = bytes
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", size, units[unitIndex])
    }
}

/// 统计窗口扩展
/// 用于在任何视图上附加统计窗口
struct StatisticsWindowModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var statisticsInfo: StatisticsInfo
    var onOK: (() -> Void)?
    var onCancel: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isPresented {
                        ZStack {
                            // 半透明背景
                            Color.black.opacity(0.3)
                                .edgesIgnoringSafeArea(.all)
                                .onTapGesture {
                                    // 点击背景不关闭窗口
                                }
                            
                            // 统计窗口 - 确保居中并保持自身尺寸
                            StatisticsWindow(
                                statisticsInfo: $statisticsInfo,
                                onOK: onOK,
                                onCancel: onCancel
                            )
                            .fixedSize()
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.windowBackgroundColor)))
                        }
                    }
                }
            )
    }
}

/// 视图扩展，方便添加统计窗口
extension View {
    func withStatisticsWindow(
        isPresented: Binding<Bool>, 
        statisticsInfo: Binding<StatisticsInfo>, 
        onOK: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        self.modifier(StatisticsWindowModifier(
            isPresented: isPresented, 
            statisticsInfo: statisticsInfo,
            onOK: onOK,
            onCancel: onCancel
        ))
    }
}
