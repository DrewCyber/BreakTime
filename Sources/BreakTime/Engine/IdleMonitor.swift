import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

/// Tracks user activity for "natural break" detection, using the method
/// chosen in Advanced:
/// - `.eventSource`: queries the system event source — no permissions needed.
/// - `.eventMonitor`: installs NSEvent monitors that stamp every real input
///   event — more reliable, but needs Accessibility permission; without it we
///   transparently fall back to the event source.
final class ActivityTracker {
    static let shared = ActivityTracker()

    var method: NaturalBreakMethod = .eventSource {
        didSet { methodDidChange() }
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastActivity = Date()
    private var reconcileTimer: Timer?
    private var monitorsInstalled = false

    /// Starts tracker upkeep: the Accessibility permission can be granted at
    /// any moment, so we periodically reconcile the monitors with the
    /// resolved method instead of only reacting to setting changes.
    func start() {
        methodDidChange()
        reconcileTimer?.invalidate()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.reconcile()
        }
        RunLoop.main.add(t, forMode: .common)
        reconcileTimer = t
    }

    private func reconcile() {
        let shouldHaveMonitors = resolvedMethod == .eventMonitor
        if shouldHaveMonitors && !monitorsInstalled {
            installMonitors()
        } else if !shouldHaveMonitors && monitorsInstalled {
            teardownMonitors()
        }
    }

    /// Idle seconds for the active method.
    func idleSeconds() -> TimeInterval {
        switch resolvedMethod {
        case .none:
            return 0
        case .eventSource:
            // kCGAnyInputEventType == ~0: match any input event
            guard let anyEvent = CGEventType(rawValue: UInt32.max) else { return 0 }
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                            eventType: anyEvent)
        case .eventMonitor:
            return Date().timeIntervalSince(lastActivity)
        }
    }

    /// Event Monitor needs Accessibility; without the permission its global
    /// monitors never fire, so we silently fall back to the event source.
    var resolvedMethod: NaturalBreakMethod {
        if method == .eventMonitor && !Self.isTrustedForAccessibility {
            return .eventSource
        }
        return method
    }

    static var isTrustedForAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that guides the user to grant Accessibility.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Monitors

    private func methodDidChange() {
        teardownMonitors()
        guard resolvedMethod == .eventMonitor else { return }
        installMonitors()
    }

    private func installMonitors() {
        let events: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .leftMouseDragged,
            .rightMouseDown, .rightMouseDragged, .otherMouseDown, .otherMouseDragged,
            .keyDown, .scrollWheel, .flagsChanged,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.lastActivity = Date()
        }
        // global monitors don't see events delivered to our own app
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.lastActivity = Date()
            return event
        }
        lastActivity = Date()
        monitorsInstalled = true
    }

    private func teardownMonitors() {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = nil
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        monitorsInstalled = false
    }
}
