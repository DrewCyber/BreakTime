import Foundation
import AppKit

/// Runs user-provided AppleScript at break start/end
/// (the counterpart of the original app's Break Actions).
enum ScriptRunner {
    static func run(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: trimmed)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
        }
    }
}

/// Plays system sounds (from /System/Library/Sounds) for break start/end.
enum SoundPlayer {
    private static var playing: [String: NSSound] = [:]

    static var systemSoundNames: [String] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/System/Library/Sounds"),
            includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { ["aiff", "aif", "wav", "mp3", "m4a"].contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending }
    }

    static func play(_ name: String, volume: Double) {
        guard !name.isEmpty else { return }
        playing[name]?.stop()
        guard let sound = NSSound(named: name) else { return }
        sound.volume = Float(min(1, max(0, volume)))
        playing[name] = sound
        sound.play()
    }

    static func stopAll() {
        playing.values.forEach { $0.stop() }
        playing.removeAll()
    }
}
