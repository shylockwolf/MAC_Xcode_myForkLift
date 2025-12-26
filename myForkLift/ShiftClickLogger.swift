import Foundation

class ShiftClickLogger {
    static let shared = ShiftClickLogger()
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    
    private init() {
        // 在桌面创建日志文件
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        logFileURL = desktopURL.appendingPathComponent("myForkLift_ShiftClick_Debug.log")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        // 清空旧日志
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("--- LOG STARTED ---")
    }
    
    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        
        print(logLine) // 同时输出到控制台
        
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
    
    func logItems(_ items: [URL], prefix: String = "") {
        let names = items.prefix(5).map { $0.lastPathComponent }.joined(separator: ", ")
        let suffix = items.count > 5 ? " +\(items.count - 5) more" : ""
        log("\(prefix) [\(items.count) items]: \(names)\(suffix)")
    }
}