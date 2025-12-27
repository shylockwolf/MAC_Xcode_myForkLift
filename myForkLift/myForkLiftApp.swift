//
//  myForkLiftApp.swift
//  myForkLift
//
//  Created by noone on 2025/11/17.
//

import SwiftUI
import AppKit

@main
struct myForkLiftApp: App {
    @StateObject private var viewModel = ContentViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 800, minHeight: 600)
                .onDisappear {
                    // 应用关闭时保存打开的文件列表
                    viewModel.saveOpenedFiles()
                }
                .onAppear {
                    // 添加应用程序退出监听
                    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) {
                        _ in
                        // 应用程序将要退出时保存打开的文件列表
                        viewModel.saveOpenedFiles()
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("About myForkLift") {
                    showAboutDialog()
                }
                .keyboardShortcut("/")
            }
            
            CommandGroup(after: .newItem) {
                Button("Open File") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
    
    private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "myForkLift"
        alert.informativeText = "Version v1.4.8\n\nAuthor: Shylock Wolf\nCreation Date: 2025-12-27"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func openFile() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        
        openPanel.begin { response in
            if response == .OK {
                // 将选中的文件添加到openedFiles数组中
                var hasChanges = false
                for url in openPanel.urls {
                    // 避免重复添加相同的文件
                    if !viewModel.openedFiles.contains(url) {
                        viewModel.openedFiles.append(url)
                        hasChanges = true
                    }
                }
                // 如果有新文件添加，立即保存
                if hasChanges {
                    viewModel.saveOpenedFiles()
                }
            }
        }
    }
}
