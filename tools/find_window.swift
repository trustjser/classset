import Cocoa
import CoreGraphics

// 用法: find_window.swift <应用进程名关键字>
// 输出: <窗口ID> <x> <y> <宽> <高>（取该应用屏幕上最大的可见窗口）
let target = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "class_set"

guard let list = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID,
) as? [[String: Any]] else {
    FileHandle.standardError.write("无法枚举窗口\n".data(using: .utf8)!)
    exit(1)
}

var best: (Int, CGRect)?
for window in list {
    guard let owner = window[kCGWindowOwnerName as String] as? String,
        let number = window[kCGWindowNumber as String] as? Int,
        let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
        let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
    else { continue }
    guard owner.localizedCaseInsensitiveContains(target) else { continue }
    let area = bounds.width * bounds.height
    if best == nil || area > best!.1.width * best!.1.height {
        best = (number, bounds)
    }
}

if let (number, bounds) = best {
    let x = Int(bounds.origin.x)
    let y = Int(bounds.origin.y)
    let w = Int(bounds.width)
    let h = Int(bounds.height)
    print("\(number) \(x) \(y) \(w) \(h)")
} else {
    FileHandle.standardError.write("未找到应用「\(target)」的可见窗口\n".data(using: .utf8)!)
    exit(2)
}
