//
//  ContentView+ExternalDevices.swift
//  DWBrowser
//
//  将外部设备检测与推出逻辑从 ContentView 主体拆分出来。
//

import Foundation
import AppKit

extension ContentView {
    // 检测外部设备
    func detectExternalDevices() {
        let detectedDevices = ExternalDeviceService.detectDevices()
        
        if externalDevices != detectedDevices {
            print("🔄 外部设备列表发生变化")
            print("📋 之前的设备: \(externalDevices.map { $0.name })")
            print("📋 当前设备: \(detectedDevices.map { $0.name })")
            
            externalDevices = detectedDevices
        } else {
            print("📋 外部设备列表无变化")
        }
    }
    
    // 设置设备监听
    func setupDeviceMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async {
                self.detectExternalDevices()
            }
        }
        
        print("🔔 设备监听已启动，每2秒检查一次")
    }
    
    // 推出外部设备
    func ejectDevice(device: ExternalDevice) {
        print("🔌 开始推出单个设备: \(device.name)")
        print("🔌 挂载点: \(device.mountPoint)")
        print("🔌 设备URL: \(device.url.path)")
        print("🔌 设备类型: \(device.deviceType)")
        
        let mountExists = FileManager.default.fileExists(atPath: device.mountPoint)
        print("🔌 挂载点存在: \(mountExists)")
        
        if !mountExists {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "设备不存在"
                alert.informativeText = "设备 \(device.name) 的挂载点不存在，可能已经被推出了"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
            return
        }
        
        guard device.mountPoint.starts(with: "/Volumes/") || device.mountPoint == "/" else {
            print("❌ 无效的挂载点: \(device.mountPoint)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "推出失败"
                alert.informativeText = "无效的设备挂载点"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
            return
        }
        
        print("🔌 直接使用diskutil unmount命令")
        ExternalDeviceService.ejectWithDiskutil(device: device, command: "unmount") { success, errorOutput in
            if success {
                self.handleEjectSuccess(device: device)
            } else {
                self.handleEjectFailure(device: device, errorOutput: errorOutput)
            }
        }
    }
    
    // 处理推出成功
    func handleEjectSuccess(device: ExternalDevice) {
        print("✅ 设备推出成功: \(device.name)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.detectExternalDevices()
        }
    }
    
    // 处理推出失败
    func handleEjectFailure(device: ExternalDevice, errorOutput: String) {
        print("❌ 设备推出失败: \(device.name)")
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "设备推出失败"
            
            let errorMessage = errorOutput.isEmpty ?
                "无法推出 \(device.name)，请确保设备没有被使用" :
                "错误信息: \(errorOutput)"
            
            alert.informativeText = errorMessage
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    // 推出所有外部设备
    func ejectAllDevices() {
        guard !externalDevices.isEmpty else {
            print("⚠️ 没有外部设备需要推出")
            
            let alert = NSAlert()
            alert.messageText = "没有外部设备"
            alert.informativeText = "当前没有连接的外部设备需要推出"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        print("🔌 开始批量推出 \(externalDevices.count) 个设备")
        
        // 初始化设备操作信息列表
        let deviceOperations = externalDevices.map { device -> DeviceOperationInfo in
            return DeviceOperationInfo(
                deviceName: device.name,
                mountPoint: device.mountPoint,
                deviceType: device.deviceType.description,
                status: .pending
            )
        }
        
        // 显示进度窗口
        DispatchQueue.main.async {
            self.progressInfo = ProgressInfo(
                title: "正在推出所有设备",
                deviceOperations: deviceOperations
            )
            self.isProgressWindowPresented = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            let totalDevices = self.externalDevices.count
            
            for (index, device) in self.externalDevices.enumerated() {
                print("🔌 开始推出设备: \(device.name)")
                print("🔌 挂载点: \(device.mountPoint)")
                
                // 更新设备状态为正在进行
                DispatchQueue.main.async {
                    self.progressInfo.deviceOperations[index].status = .inProgress
                }
                
                var errorMessage: String? = nil
                var operationSuccess = false
                
                if !FileManager.default.fileExists(atPath: device.mountPoint) {
                    print("⚠️ 设备挂载点不存在: \(device.name)，可能已经被弹出")
                    // 挂载点不存在，视为推出成功
                    operationSuccess = true
                    successCount += 1
                } else {
                    let workspaceResult = NSWorkspace.shared.unmountAndEjectDevice(atPath: device.mountPoint)
                    
                    if workspaceResult {
                        print("✅ NSWorkspace推出成功: \(device.name)")
                        operationSuccess = true
                        successCount += 1
                    } else {
                        print("❌ NSWorkspace推出失败，尝试diskutil: \(device.name)")
                        
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                        task.arguments = ["eject", device.mountPoint]
                        
                        let errorPipe = Pipe()
                        task.standardError = errorPipe
                        
                        do {
                            try task.run()
                            task.waitUntilExit()
                            
                            if task.terminationStatus == 0 {
                                print("✅ diskutil推出成功: \(device.name)")
                                operationSuccess = true
                                successCount += 1
                            } else {
                                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                                if let message = String(data: errorData, encoding: .utf8), !message.isEmpty {
                                    print("❌ diskutil推出失败: \(device.name) - \(message)")
                                    errorMessage = message
                                } else {
                                    print("❌ diskutil推出失败: \(device.name) - 未知错误")
                                    errorMessage = "未知错误"
                                }
                            }
                        } catch {
                            print("❌ 执行diskutil命令失败: \(device.name) - \(error.localizedDescription)")
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                
                // 更新设备状态
                DispatchQueue.main.async {
                    if operationSuccess {
                        self.progressInfo.deviceOperations[index].status = .success
                    } else {
                        self.progressInfo.deviceOperations[index].status = .failed
                        self.progressInfo.deviceOperations[index].errorMessage = errorMessage
                    }
                }
                
                // 添加操作日志
                let logMessage = "\(operationSuccess ? "✅" : "❌") \(device.name): \(operationSuccess ? "推出成功" : "推出失败")"
                print(logMessage)
                
                DispatchQueue.main.async {
                    self.progressInfo.operationLog.append(logMessage)
                }
                
                // 检查是否被取消
                if Thread.isMainThread {
                    if self.progressInfo.isCancelled {
                        break
                    }
                } else {
                    var isCancelled = false
                    DispatchQueue.main.sync {
                        isCancelled = self.progressInfo.isCancelled
                    }
                    if isCancelled {
                        break
                    }
                }
            }
            
            // 更新最终状态
            DispatchQueue.main.async {
                if self.progressInfo.isCancelled {
                    self.progressInfo.title = "操作已取消"
                } else {
                    self.progressInfo.title = "推出完成"
                    self.progressInfo.isCompleted = true
                }
                
                // 所有设备都推出完成后，自动关闭窗口
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.isProgressWindowPresented = false
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.detectExternalDevices()
            }
        }
    }
}


