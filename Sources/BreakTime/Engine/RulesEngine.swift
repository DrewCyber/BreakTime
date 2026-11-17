import Foundation
import AppKit

/// Watches the frontmost application and runs script detectors:
/// pause rules freeze the timers, skip rules auto-skip a break when due.
/// App checks run every 3 s; script detectors run on a slower cadence (15 s)
/// with a 5 s timeout each, and their results are cached between runs.
final class RulesEngine: ObservableObject {
    @Published private(set) var pauseRuleName: String?
    @Published private(set) var skipRuleName: String?

    private var appTimer: Timer?
    private var scriptTimer: Timer?
    private var frontmostBundleID: String = ""

    /// Last evaluation results of script rules, keyed by rule id.
    private var scriptResults: [UUID: Bool] = [:]

    var isPausedByRule: Bool { pauseRuleName != nil }

    func start() {
        appTimer?.invalidate()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.checkApps()
            self?.publishMatches()
        }
        RunLoop.main.add(t, forMode: .common)
        appTimer = t

        scriptTimer?.invalidate()
        let st = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.runScriptDetectors()
        }
        RunLoop.main.add(st, forMode: .common)
        scriptTimer = st

        checkApps()
        runScriptDetectors()
    }

    func stop() {
        appTimer?.invalidate()
        appTimer = nil
        scriptTimer?.invalidate()
        scriptTimer = nil
    }

    /// Re-check immediately (after rule edits).
    func recheck() {
        checkApps()
        runScriptDetectors()
    }

    // MARK: App rules

    private func checkApps() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }

    // MARK: Script detectors

    private func runScriptDetectors() {
        let rules = Store.shared.settings.rules.filter { $0.enabled && $0.isScript }
        guard !rules.isEmpty else {
            scriptResults.removeAll()
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var results: [UUID: Bool] = [:]
            for rule in rules {
                results[rule.id] = Self.runShell(rule.script, timeout: 5)
            }
            DispatchQueue.main.async {
                self?.scriptResults = results
                self?.publishMatches()
            }
        }
    }

    /// Runs a shell detector; true when it exits with status 0 within the timeout.
    static func runShell(_ script: String, timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(200_000)
        }
        if process.isRunning {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    // MARK: Matching

    private func publishMatches() {
        let rules = Store.shared.settings.rules.filter { $0.enabled }
        guard !rules.isEmpty else {
            pauseRuleName = nil
            skipRuleName = nil
            return
        }

        func matches(_ rule: Rule) -> Bool {
            if rule.isScript {
                return scriptResults[rule.id] == true
            }
            return !frontmostBundleID.isEmpty && rule.appBundleID == frontmostBundleID
        }

        // a pause match wins over a skip match
        if let pause = rules.first(where: { $0.action == .pause && matches($0) }) {
            pauseRuleName = pause.appName
            skipRuleName = nil
        } else if let skip = rules.first(where: { $0.action == .skip && matches($0) }) {
            pauseRuleName = nil
            skipRuleName = skip.appName
        } else {
            pauseRuleName = nil
            skipRuleName = nil
        }
    }
}
