import SwiftUI
import AppKit

/// 自定义NSView来捕获键盘事件
class KeyboardCaptureView: NSView {
    let onKeyPress: (String) -> Void
    let onSpecialKey: (String, NSEvent.ModifierFlags) -> Void
    private var eventMonitor: Any?
    
    init(onKeyPress: @escaping (String) -> Void, onSpecialKey: @escaping (String, NSEvent.ModifierFlags) -> Void) {
        self.onKeyPress = onKeyPress
        self.onSpecialKey = onSpecialKey
        super.init(frame: .zero)
        
        // 使视图可以成为第一响应者
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        self.isHidden = false
        
        // 添加事件监听
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        // 移除事件监听
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    // 重写以允许成为第一响应者
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    override func resignFirstResponder() -> Bool { true }
    
    /// 处理键盘事件
    private func handleKeyEvent(_ event: NSEvent) {
        let modifierFlags = event.modifierFlags
        
        // 首先检查特殊键（方向键等）
        if let specialKey = getSpecialKey(from: event) {
            onSpecialKey(specialKey, modifierFlags)
            return
        }
        
        // 处理字母键
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else {
            return
        }
        
        // 检查是否是字母
        let charSet = CharacterSet.letters
        guard let scalar = chars.unicodeScalars.first, charSet.contains(scalar) else {
            return
        }
        
        // 调用回调
        onKeyPress(chars.lowercased())
    }
    
    /// 获取特殊键的名称
    private func getSpecialKey(from event: NSEvent) -> String? {
        switch event.keyCode {
        case 126: return "up"      // 上箭头
        case 125: return "down"    // 下箭头
        case 123: return "left"    // 左箭头
        case 124: return "right"   // 右箭头
        case 122: return "f1"       // F1
        case 120: return "f2"       // F2
        case 99:  return "f3"       // F3
        case 118: return "f4"       // F4
        case 96:  return "f5"       // F5
        case 97:  return "f6"       // F6
        case 98:  return "f7"       // F7
        case 100: return "f8"      // F8
        case 101: return "f9"      // F9
        case 109: return "f10"      // F10
        case 103: return "f11"      // F11
        case 111: return "f12"      // F12
        case 53:  return "escape"   // Esc
        case 36:  return "return"   // Enter
        case 48:  return "tab"      // Tab
        case 49:  return "space"    // Space
        case 51:  return "delete"   // Delete/Backspace
        case 117: return "deleteForward" // Forward Delete
        default: return nil
        }
    }
}

/// 键盘输入捕获器
struct KeyboardInputCapturer: NSViewRepresentable {
    let onKeyPress: (String) -> Void
    let onSpecialKey: (String, NSEvent.ModifierFlags) -> Void
    let isActive: Bool
    let parent: NSView?
    
    func makeNSView(context: Context) -> KeyboardCaptureView {
        return KeyboardCaptureView(onKeyPress: onKeyPress, onSpecialKey: onSpecialKey)
    }
    
    func updateNSView(_ nsView: KeyboardCaptureView, context: Context) {
        // 确保焦点设置正确
        if isActive {
            DispatchQueue.main.async { [weak nsView] in
                if let window = nsView?.window, window.firstResponder != nsView {
                    window.makeFirstResponder(nsView)
                }
            }
        } else if nsView.window?.firstResponder === nsView {
            // 如果不是激活状态且当前是第一响应者，则放弃焦点
            nsView.window?.makeFirstResponder(nil)
        }
    }
    
    static func dismantleNSView(_ nsView: KeyboardCaptureView, coordinator: ()) {
        // 清理工作已在KeyboardCaptureView的deinit中完成
    }
}