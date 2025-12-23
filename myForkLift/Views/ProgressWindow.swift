import SwiftUI
import Foundation

// MARK: - 进度条窗口组件

/// 设备操作状态
enum DeviceOperationStatus {
    case pending
    case inProgress
    case success
    case failed
    
    var icon: String {
        switch self {
        case .pending:
            return "clock"
        case .inProgress:
            return "arrow.clockwise"
        case .success:
            return "checkmark.circle"
        case .failed:
            return "xmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .inProgress:
            return .blue
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
    
    var description: String {
        switch self {
        case .pending:
            return "等待"
        case .inProgress:
            return "等待弹出"
        case .success:
            return "成功"
        case .failed:
            return "失败"
        }
    }
}

/// 设备操作信息
struct DeviceOperationInfo: Identifiable {
    let id = UUID()
    let deviceName: String
    let mountPoint: String
    let deviceType: String
    var status: DeviceOperationStatus
    var errorMessage: String? = nil
}

/// 进度窗口数据模型
struct ProgressInfo: Identifiable {
    let id = UUID()
    var title: String
    var isCompleted: Bool = false
    var isCancelled: Bool = false
    var deviceOperations: [DeviceOperationInfo] = []
    var operationLog: [String] = []
}

/// 进度窗口视图
struct ProgressWindow: View {
    @Binding var progressInfo: ProgressInfo
    var onCancel: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 10) {
            // 标题
            Text(progressInfo.title)
                .font(.title3)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 设备操作列表 - 滚动显示
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(progressInfo.deviceOperations) { operation in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: operation.status.icon)
                                    .foregroundColor(operation.status.color)
                                    .font(.system(size: 16))
                                
                                VStack(alignment: .leading) {
                                    Text(operation.deviceName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    
                                    // 设备详细信息
                                    HStack(spacing: 16) {
                                        Text("挂载点: \(operation.mountPoint)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("类型: \(operation.deviceType)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // 状态文本
                                Text(operation.status.description)
                                    .font(.caption)
                                    .foregroundColor(operation.status.color)
                            }
                            
                            // 错误信息（如果有）
                            if let errorMessage = operation.errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.leading, 28)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 150, maxHeight: 300)
            .border(Color(.separatorColor), width: 1)
            .cornerRadius(6)
            
            // 按钮
            HStack {
                Spacer()
                
                if !progressInfo.isCompleted && !progressInfo.isCancelled {
                    Button(action: {
                        progressInfo.isCancelled = true
                        onCancel?()
                    }) {
                        Text("取消")
                            .font(.caption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                } else {
                    Button(action: {
                        // 可以添加关闭窗口的逻辑
                    }) {
                        Text("确定")
                            .font(.caption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 400, minHeight: 250)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 12)
    }
}

/// 进度窗口扩展
/// 用于在任何视图上附加进度窗口
struct ProgressWindowModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var progressInfo: ProgressInfo
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
                            
                            // 进度窗口 - 确保居中并保持自身尺寸
                            ProgressWindow(progressInfo: $progressInfo, onCancel: onCancel)
                                .fixedSize()
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.windowBackgroundColor)))
                        }
                    }
                }
            )
    }
}

/// 视图扩展，方便添加进度窗口
extension View {
    func withProgressWindow(isPresented: Binding<Bool>, progressInfo: Binding<ProgressInfo>, onCancel: (() -> Void)? = nil) -> some View {
        self.modifier(ProgressWindowModifier(isPresented: isPresented, progressInfo: progressInfo, onCancel: onCancel))
    }
}


