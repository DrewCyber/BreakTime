import Foundation
import SwiftUI
import AppKit

// MARK: - Color <-> hex

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.11; g = 0.11; b = 0.12
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - UI clock

/// Publishes the current time every second for views that show live
/// countdowns. The scheduler itself stays quiet between events.
final class Clock: ObservableObject {
    static let shared = Clock()

    @Published private(set) var now: Date = Date()
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: - Native menu popup bridge

/// Lets custom SwiftUI buttons open a native NSMenu (full control over
/// the button's look; the menu itself stays fully native with submenus).
final class NativeMenuPopup: NSObject {
    static let shared = NativeMenuPopup()

    @objc func invoke(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}

// MARK: - NSColor <-> hex

extension NSColor {
    convenience init(hexString: String) {
        self.init(Color(hex: hexString))
    }

    var hexStringValue: String {
        (usingColorSpace(.sRGB) ?? self).swiftUIColor.hexString
    }
}

private extension NSColor {
    var swiftUIColor: Color {
        Color(nsColor: self)
    }
}

// MARK: - Time formatting

enum TimeFmt {
    /// Cached formatters — DateFormatter allocation is expensive, and these
    /// are used every second by the menu bar and sidebar.
    static let timeOfDay: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    /// "HH:mm:ss" — exact time with seconds (Next due caption).
    static let timeOfDayWithSeconds: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    /// "1:05" style clock for break durations and countdowns.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Short human countdown like "5 min", "45 sec", "1 hr 5 min".
    static func short(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) sec" }
        if s < 3600 { return "\(s / 60) min" }
        let h = s / 3600, m = (s % 3600) / 60
        return m > 0 ? "\(h) hr \(m) min" : "\(h) hr"
    }

    /// Brief countdown like the original's menu bar label: "1h" (hours only,
    /// minutes appear only once less than an hour remains), "45m", "30s".
    static func brief(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 { return "\(s / 3600)h" }
        if s >= 60 { return "\(s / 60)m" }
        return "\(s)s"
    }

    /// Long form with correct plurals: "1 minute", "5 minutes".
    static func minutesLong(_ minutes: Int) -> String {
        minutes == 1 ? "1 Minute" : "\(minutes) Minutes"
    }

    /// "21 min, 8 secs" style used in the sidebar.
    static func longSeconds(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) secs" }
        if s < 3600 { return "\(s / 60) min, \(s % 60) secs" }
        let h = s / 3600, m = (s % 3600) / 60
        return m > 0 ? "\(h) hr \(m) min" : "\(h) hr"
    }

    /// "done 19 hrs, 5 min ago" style for the second sidebar line.
    static func relAgo(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) sec ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 {
            let h = s / 3600, m = (s % 3600) / 60
            return m > 0 ? "\(h) hr\(h == 1 ? "" : "s"), \(m) min ago" : "\(h) hr\(h == 1 ? "" : "s") ago"
        }
        let d = s / 86400, h = (s % 86400) / 3600
        return h > 0 ? "\(d) day\(d == 1 ? "" : "s"), \(h) hr ago" : "\(d) day\(d == 1 ? "" : "s") ago"
    }
}

// MARK: - Small helpers

extension Date {
    func adding(minutes: Int) -> Date { addingTimeInterval(TimeInterval(minutes) * 60) }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
