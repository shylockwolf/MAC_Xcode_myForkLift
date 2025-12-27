//
//  KeyboardShortcutHandler.swift
//  myForkLift
//
//  Created by on 2025/12/21.
//

import SwiftUI
import Cocoa

struct KeyboardShortcutHandler: NSViewRepresentable {
    var onSelectAll: () -> Void

    class Coordinator: NSObject {
        var onSelectAll: () -> Void
        var eventMonitor: Any?

        init(onSelectAll: @escaping () -> Void) {
            self.onSelectAll = onSelectAll
        }

        @objc func handleSelectAll(_ sender: Any?) {
            onSelectAll()
        }
        
        func startMonitoring() {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) {
                    switch event.charactersIgnoringModifiers {
                    case "a":
                        // Command-A：全选
                        self.handleSelectAll(nil)
                        return nil // 消耗事件
                    default:
                        break
                    }
                }
                return event // 传递其他事件
            }
        }
        
        func stopMonitoring() {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        
        // 开始监听键盘事件
        context.coordinator.startMonitoring()
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectAll: onSelectAll)
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // 停止监听键盘事件
        coordinator.stopMonitoring()
    }
}