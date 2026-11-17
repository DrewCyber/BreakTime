import Foundation
import Combine
import AppKit

// MARK: - Runtime state

enum BreakPhase: Equatable {
    case idle
    case ready
    case active

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .ready: return "Get Ready"
        case .active: return "Break"
        }
    }
}

struct BreakRuntime: Equatable {
    var nextStart: Date = Date()
    var phase: BreakPhase = .idle
    var phaseEnd: Date = Date()
    /// When set, this break's timer is frozen (idle pause) until activity returns.
    var frozenAt: Date?
    /// The due date this break actually started from (for "From: Last Due").
    var startedDue: Date?
    /// "Reset after a long natural break": set while a long-enough idle period
    /// is in progress; the reset fires when the user becomes active again.
    var naturalResetPending: Bool = false
    /// Count backwards: idle seconds already credited to this break's countdown
    /// during the current idle period (reset when activity returns).
    var naturalCredited: TimeInterval = 0
}

// MARK: - Scheduler

/// Drives all break timers: a 1-second tick advances phases
/// (idle → ready → active → idle), honoring pauses, rules, idle behavior,
/// control limits and mindfulness delays.
final class Scheduler: ObservableObject {
    /// Internal clock for scheduling logic; NOT published — the settings window
    /// must not re-render every second (it would reset fields being edited).
    /// Per-second UI (sidebars, overlay) observes `Clock` instead.
    private(set) var now: Date = Date()
    @Published private(set) var runtimes: [UUID: BreakRuntime] = [:]
    /// Set while previewing a break from Settings; such breaks are not logged as real events.
    @Published private(set) var previewingBreakID: UUID?
    /// Mindfulness: overlay buttons stay locked until this instant.
    @Published private(set) var controlsLockedUntil: Date?

    let store: Store
    let log: ActivityLog
    let rules: RulesEngine

    private var timer: Timer?
    private var pauseStartedAt: Date?
    private var persistCancellable: AnyCancellable?

    init(store: Store, log: ActivityLog, rules: RulesEngine) {
        self.store = store
        self.log = log
        self.rules = rules
        restoreSchedule()
        // persist due dates (debounced) so the schedule survives relaunches
        persistCancellable = $runtimes
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] rts in
                guard let self = self else { return }
                let state = Dictionary(uniqueKeysWithValues:
                    rts.map { ($0.key.uuidString, $0.value.nextStart) })
                self.store.saveScheduleState(state)
            }
        // persist the restored state right away
        let initial = Dictionary(uniqueKeysWithValues:
            runtimes.map { ($0.key.uuidString, $0.value.nextStart) })
        store.saveScheduleState(initial)
    }

    /// Restores persisted due dates so the countdown continues across
    /// relaunches; fully elapsed intervals are caught up without firing.
    private func restoreSchedule() {
        let saved = store.scheduleState
        runtimes = [:]
        for cfg in store.breaks {
            let next: Date
            if let stored = saved[cfg.id.uuidString] {
                var candidate = stored
                let interval = cfg.scheduleMode.nextInterval
                if interval.isFinite {
                    // skip whole intervals missed while the app wasn't running
                    while candidate <= now {
                        let advanced = candidate.addingTimeInterval(interval)
                        if advanced <= now { candidate = advanced } else { break }
                    }
                }
                next = candidate
            } else if cfg.scheduleMode.isManual || cfg.scheduleMode == .once {
                next = .distantFuture
            } else {
                next = cfg.avail.rollIntoWindow(now.addingTimeInterval(cfg.scheduleMode.nextInterval))
            }
            runtimes[cfg.id] = BreakRuntime(nextStart: next)
        }
        pauseStartedAt = nil
        objectWillChange.send()
    }

    // MARK: Lifecycle

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Effective pause

    var pauseReason: String? {
        if rules.pauseRuleName != nil {
            return "Paused (\(rules.pauseRuleName ?? "rule"))"
        }
        if store.settings.pausedUntil == .some(.distantFuture) {
            return "Paused indefinitely"
        }
        if let until = store.settings.pausedUntil, until > now {
            return "Paused (\(TimeFmt.short(until.timeIntervalSince(now))) left)"
        }
        return nil
    }

    var isPaused: Bool { pauseReason != nil }

    // MARK: Public actions

    func pause(forMinutes minutes: Int) {
        pauseStartedAt = now
        store.settings.pausedUntil = minutes < 0
            ? .distantFuture
            : Date().adding(minutes: minutes)
    }

    func resume() {
        store.settings.pausedUntil = nil
    }

    func resetAll() {
        runtimes = [:]
        for cfg in store.breaks {
            let next: Date
            if cfg.scheduleMode.isManual || cfg.scheduleMode == .once {
                next = .distantFuture
            } else {
                next = cfg.avail.rollIntoWindow(Date().addingTimeInterval(cfg.scheduleMode.nextInterval))
            }
            runtimes[cfg.id] = BreakRuntime(nextStart: next)
        }
        OverlayController.shared.hide()
        pauseStartedAt = nil
        objectWillChange.send()
    }

    func beginBreak(_ id: UUID, preview: Bool = false) {
        guard let cfg = store.breakByID(id) else { return }
        guard runtimes[id]?.phase == .idle || runtimes[id]?.phase == nil else { return }
        if !preview, let otherID = activeBreakID, otherID != id {
            finishBreak(id: otherID)
        }
        previewingBreakID = preview ? id : nil
        enterActive(cfg)
    }

    func makeDue(_ id: UUID) {
        guard var rt = runtimes[id], rt.phase == .idle else { return }
        rt.nextStart = now
        rt.frozenAt = nil
        runtimes[id] = rt
    }

    /// Make the break due after a delay (Options ▸ Make Due In submenu).
    func makeDueIn(_ id: UUID, minutes: Int) {
        guard var rt = runtimes[id], rt.phase == .idle else { return }
        rt.nextStart = now.addingTimeInterval(TimeInterval(minutes) * 60)
        rt.frozenAt = nil
        runtimes[id] = rt
    }

    /// Reset just this break's timer (Options ▸ Reset Break).
    func resetBreak(_ id: UUID) {
        guard let cfg = store.breakByID(id), var rt = runtimes[id] else { return }
        rt.phase = .idle
        rt.nextStart = cfg.scheduleMode.isManual ? .distantFuture : rolledFromNow(cfg)
        rt.frozenAt = nil
        rt.naturalResetPending = false
        runtimes[id] = rt
        if OverlayController.shared.breakID == id {
            OverlayController.shared.hide(fade: cfg.controls.fadeOutSeconds)
        }
    }

    /// Set the exact next-due date (editable "Next due" field on the Schedule tab).
    func setNextStart(_ id: UUID, to date: Date) {
        guard runtimes[id] != nil else { return }
        runtimes[id]!.nextStart = date
    }

    /// End the current break early (the overlay's End Break button): counts as taken.
    func endBreakEarly(_ id: UUID) {
        guard let cfg = store.breakByID(id), var rt = runtimes[id],
              rt.phase == .active else { return }
        let taken = now.timeIntervalSince(rt.phaseEnd.addingTimeInterval(-cfg.duration))
        rt.phase = .idle
        rt.nextStart = now.addingTimeInterval(cfg.scheduleMode.interval)
        runtimes[id] = rt
        hideOverlayIfNeeded(cfg)
        SoundPlayer.play(cfg.actions.endSound, volume: cfg.actions.volume)
        if !isPreviewing(cfg) {
            log.record(.finished, break: cfg, durationSec: Int(max(1, taken.rounded())))
            store.bumpCounter(cfg.id, \.done)
        }
        clearPreviewIfDone(cfg)
    }

    // MARK: Per-break pause (Options ▸ Pause Break)

    func pauseBreak(_ id: UUID, minutes: Int) {
        let end = minutes < 0 ? Date.distantFuture : now.addingTimeInterval(TimeInterval(minutes) * 60)
        store.settings.breakPauses[id.uuidString] = end
        breakPauseStart[id] = now
    }

    func resumeBreak(_ id: UUID) {
        store.settings.breakPauses.removeValue(forKey: id.uuidString)
        // shift resumes on the next tick
    }

    func isBreakPaused(_ id: UUID) -> Bool {
        guard let until = store.settings.breakPauses[id.uuidString] else { return false }
        return until > now
    }

    private var breakPauseStart: [UUID: Date] = [:]

    private func handleBreakPauses() {
        for cfg in store.breaks {
            let paused = isBreakPaused(cfg.id)
            if paused {
                if breakPauseStart[cfg.id] == nil { breakPauseStart[cfg.id] = now }
                continue
            }
            if let started = breakPauseStart[cfg.id] {
                if var rt = runtimes[cfg.id], rt.phase == .idle {
                    rt.nextStart += now.timeIntervalSince(started)
                    runtimes[cfg.id] = rt
                }
                breakPauseStart[cfg.id] = nil
                store.settings.breakPauses.removeValue(forKey: cfg.id.uuidString)
            }
        }
    }

    func postpone(_ id: UUID, minutes: Int) {
        guard let cfg = store.breakByID(id), var rt = runtimes[id] else { return }
        let wasShowing = rt.phase != .idle
        rt.phase = .idle
        rt.nextStart = Date().adding(minutes: minutes)
        rt.frozenAt = nil
        rt.naturalResetPending = false
        runtimes[id] = rt
        if wasShowing { hideOverlayIfNeeded(cfg) }
        if !isPreviewing(cfg) {
            log.record(.postponed, break: cfg, postponeMinutes: minutes)
            store.bumpCounter(cfg.id, \.postponed)
        }
        clearPreviewIfDone(cfg)
    }

    func skip(_ id: UUID) {
        guard let cfg = store.breakByID(id), var rt = runtimes[id] else { return }
        let wasShowing = rt.phase != .idle
        rt.phase = .idle
        rt.nextStart = cfg.scheduleMode.isManual
            ? .distantFuture
            : nextDueAfterCompletion(of: cfg, endedAt: now)
        rt.frozenAt = nil
        rt.naturalResetPending = false
        runtimes[id] = rt
        if wasShowing { hideOverlayIfNeeded(cfg) }
        if !isPreviewing(cfg) {
            log.record(.skipped, break: cfg)
            store.bumpCounter(cfg.id, \.skipped)
        }
        clearPreviewIfDone(cfg)
    }

    /// The next break that will be due (for shortcuts and the menu bar).
    func nextBreakInfo(longOnly: Bool = false) -> (cfg: BreakConfig, runtime: BreakRuntime)? {
        let candidates = store.breaks
            .filter { $0.enabled && !isPaused && !$0.scheduleMode.isManual && (!longOnly || $0.kind != .micro) }
            .compactMap { cfg -> (BreakConfig, BreakRuntime)? in
                guard let rt = runtimes[cfg.id], rt.phase == .idle,
                      rt.nextStart < .distantFuture else { return nil }
                return (cfg, rt)
            }
        return candidates.min { $0.1.nextStart < $1.1.nextStart }
    }

    var activeBreakID: UUID? {
        runtimes.first { $0.value.phase != .idle }?.key
    }

    /// Whether the overlay's postpone/skip buttons should be enabled (mindfulness + limits).
    func overlayControls(for cfg: BreakConfig) -> (postpone: Bool, skip: Bool) {
        let locked = controlsLockedUntil.map { $0 > now } ?? false
        let postponeOK = !cfg.controls.postponeOptions.isEmpty
            && !store.limitReached(cfg.id, limit: cfg.controls.maxPostponesPerDay, key: \.postponed)
        let skipOK = !store.limitReached(cfg.id, limit: cfg.controls.maxSkipsPerDay, key: \.skipped)
        return (!locked && postponeOK, !locked && skipOK)
    }

    // MARK: Tick

    private func tick() {
        now = Date()

        handlePauseTransitions()
        handleBreakPauses()
        handleIdleBehavior()

        guard !isPaused else { return }

        for cfg in store.breaks {
            guard var rt = runtimes[cfg.id] else { continue }
            if isBreakPaused(cfg.id), rt.phase == .idle { continue }
            switch rt.phase {
            case .active:
                if now >= rt.phaseEnd {
                    finishBreak(id: cfg.id)
                }
            case .ready:
                if now >= rt.phaseEnd {
                    enterActive(cfg)
                }
            case .idle:
                // the Get Ready warning occupies the final N seconds BEFORE
                // the due moment, so the break itself starts exactly on time
                let readyLead = TimeInterval(max(0, cfg.readySeconds))
                let triggerAt = rt.nextStart.addingTimeInterval(-readyLead)
                if cfg.enabled, !cfg.scheduleMode.isManual,
                   rt.frozenAt == nil, now >= triggerAt {
                    if now < rt.nextStart {
                        rt.phase = .ready
                        rt.phaseEnd = rt.nextStart
                        rt.startedDue = rt.nextStart
                        runtimes[cfg.id] = rt
                        showOverlay(cfg)
                        continue
                    }
                    // outside the availability window: defer to its next start
                    if !cfg.avail.isAvailable(now) {
                        rt.nextStart = cfg.avail.rollIntoWindow(now)
                        runtimes[cfg.id] = rt
                        continue
                    }
                    if let skipper = rules.skipRuleName {
                        // a skip rule matches: skip this break silently
                        rt.nextStart = now.addingTimeInterval(cfg.scheduleMode.interval)
                        runtimes[cfg.id] = rt
                        log.record(.autoSkipped, break: cfg)
                        continue
                    }
                    if higherPriorityDue(within: cfg.skipIfHigherPriorityDueWithinMin, of: cfg) {
                        // a higher-priority break is due soon: skip this one
                        rt.nextStart = nextDueAfterCompletion(of: cfg, endedAt: now)
                        runtimes[cfg.id] = rt
                        log.record(.autoSkipped, break: cfg)
                        continue
                    }
                    if let activeID = activeBreakID, activeID != cfg.id {
                        // one break at a time: queue right after the current one
                        rt.nextStart = runtimes[activeID]?.phaseEnd ?? now
                        runtimes[cfg.id] = rt
                    } else {
                        rt.startedDue = rt.nextStart
                        runtimes[cfg.id] = rt
                        previewingBreakID = nil
                        enterActive(cfg)
                    }
                }
            }
        }
    }

    /// The next due date after a completion: interval from the anchor
    /// (Last Due or End of Break), rolled forward to the next allowed day.
    /// One-shot breaks simply don't recur.
    private func nextDueAfterCompletion(of cfg: BreakConfig, endedAt end: Date) -> Date {
        if cfg.scheduleMode.isManual || cfg.scheduleMode == .once {
            return .distantFuture
        }
        let anchorDate: Date
        switch cfg.anchor {
        case .lastDue:
            anchorDate = runtimes[cfg.id]?.startedDue ?? end
        case .endOfBreak:
            anchorDate = end
        }
        let candidate = anchorDate.addingTimeInterval(cfg.scheduleMode.nextInterval)
        return cfg.avail.rollIntoWindow(candidate)
    }

    /// Rolls a "from now" due date to the next allowed day.
    private func rolledFromNow(_ cfg: BreakConfig) -> Date {
        if cfg.scheduleMode.isManual || cfg.scheduleMode == .once {
            return .distantFuture
        }
        let candidate = now.addingTimeInterval(cfg.scheduleMode.nextInterval)
        return cfg.avail.rollIntoWindow(candidate)
    }

    /// Whether a higher-priority break is due within the given minutes.
    private func higherPriorityDue(within minutes: Int, of cfg: BreakConfig) -> Bool {
        guard minutes > 0,
              let myIndex = store.breaks.firstIndex(where: { $0.id == cfg.id }) else { return false }
        let horizon = now.addingTimeInterval(TimeInterval(minutes) * 60)
        for higher in store.breaks[..<myIndex] {
            guard higher.enabled, !higher.scheduleMode.isManual,
                  let rt = runtimes[higher.id], rt.phase == .idle else { continue }
            if rt.nextStart <= horizon { return true }
        }
        return false
    }

    /// "Reset this break after finishing one with a higher priority":
    /// when `finished` completes, reset every lower-priority break that opted in.
    private func resetBreaksAfterHigherPriority(_ finished: BreakConfig) {
        guard let finishedIndex = store.breaks.firstIndex(where: { $0.id == finished.id }) else { return }
        for lower in store.breaks[(finishedIndex + 1)...] where lower.resetAfterHigherPriorityFinish {
            guard var rt = runtimes[lower.id], rt.phase == .idle else { continue }
            rt.nextStart = rolledFromNow(lower)
            rt.startedDue = nil
            runtimes[lower.id] = rt
        }
    }

    // MARK: Phase helpers

    private func enterActive(_ cfg: BreakConfig) {
        guard var rt = runtimes[cfg.id] else { return }
        rt.phase = .active
        rt.phaseEnd = now.addingTimeInterval(cfg.duration)
        runtimes[cfg.id] = rt
        controlsLockedUntil = cfg.controls.disableButtonsSeconds > 0
            ? now.addingTimeInterval(TimeInterval(cfg.controls.disableButtonsSeconds))
            : nil
        showOverlay(cfg)
        SoundPlayer.play(cfg.actions.startSound, volume: cfg.actions.volume)
        ScriptRunner.run(cfg.actions.startAppleScript)
        if !isPreviewing(cfg) {
            log.record(.started, break: cfg)
        }
    }

    private func finishBreak(id: UUID) {
        guard let cfg = store.breakByID(id), var rt = runtimes[id] else { return }
        rt.phase = .idle
        rt.nextStart = cfg.scheduleMode.isManual
            ? .distantFuture
            : nextDueAfterCompletion(of: cfg, endedAt: now)
        rt.startedDue = nil
        rt.naturalResetPending = false
        runtimes[id] = rt
        hideOverlayIfNeeded(cfg)
        SoundPlayer.play(cfg.actions.endSound, volume: cfg.actions.volume)
        ScriptRunner.run(cfg.actions.endAppleScript)
        if !isPreviewing(cfg) {
            log.record(.finished, break: cfg, durationSec: cfg.durationSec)
            store.bumpCounter(cfg.id, \.done)
            resetBreaksAfterHigherPriority(cfg)
        }
        clearPreviewIfDone(cfg)
    }

    private func isPreviewing(_ cfg: BreakConfig) -> Bool {
        previewingBreakID == cfg.id
    }

    private func clearPreviewIfDone(_ cfg: BreakConfig) {
        if previewingBreakID == cfg.id, runtimes[cfg.id]?.phase == .idle {
            previewingBreakID = nil
        }
    }

    private func showOverlay(_ cfg: BreakConfig) {
        OverlayController.shared.show(cfg: cfg, scheduler: self)
    }

    // MARK: Pause / idle handling

    private func handlePauseTransitions() {
        let paused = isPaused
        if paused && pauseStartedAt == nil {
            pauseStartedAt = now
        } else if !paused, let started = pauseStartedAt {
            let delta = now.timeIntervalSince(started)
            for (id, rt) in runtimes where rt.phase == .idle {
                var shifted = rt
                shifted.nextStart += delta
                runtimes[id] = shifted
            }
            pauseStartedAt = nil
        }
    }

    private func handleIdleBehavior() {
        guard store.settings.naturalBreakMethod != .none else { return }
        let idle = ActivityTracker.shared.idleSeconds()
        let threshold = Double(store.settings.naturalBreakThresholdSec)
        for cfg in store.breaks {
            guard var rt = runtimes[cfg.id], rt.phase == .idle, cfg.enabled else { continue }

            // "Reset this break after a natural break longer than N": the reset
            // fires when the natural break ENDS (user active again), so the
            // countdown starts from the moment of return — and it's logged.
            let resetAfter = Double(cfg.resetAfterNaturalLongerThanSec)
            if resetAfter > 0 {
                if idle >= resetAfter {
                    if !rt.naturalResetPending {
                        rt.naturalResetPending = true
                        runtimes[cfg.id] = rt
                    }
                } else if idle < threshold, rt.naturalResetPending {
                    rt.naturalResetPending = false
                    rt.nextStart = now.addingTimeInterval(cfg.scheduleMode.nextInterval)
                    rt.frozenAt = nil
                    runtimes[cfg.id] = rt
                    log.record(.naturalReset, break: cfg)
                    continue
                }
            }

            switch cfg.idleMode {
            case .ignore:
                // only publish when something actually changes — quiet ticks
                // must not wake the observers every second
                if rt.frozenAt != nil {
                    rt.frozenAt = nil
                    runtimes[cfg.id] = rt
                }
            case .pauseTimers:
                if idle >= threshold {
                    if rt.frozenAt == nil {
                        rt.frozenAt = now
                        runtimes[cfg.id] = rt
                    }
                } else if let frozen = rt.frozenAt {
                    rt.nextStart += now.timeIntervalSince(frozen)
                    rt.frozenAt = nil
                    runtimes[cfg.id] = rt
                }
            case .countAsBreak:
                // activity returned — a fresh idle period starts from zero credit
                if idle < threshold {
                    if rt.naturalCredited != 0 || rt.frozenAt != nil {
                        rt.naturalCredited = 0
                        rt.frozenAt = nil
                        runtimes[cfg.id] = rt
                    }
                    break
                }
                // the reset rule owns over-long idle periods (fires on return)
                if resetAfter > 0 && idle >= resetAfter { break }

                // Count backwards: credit the idle time to the countdown —
                // the due date moves closer while the Mac is idle.
                let delta = idle - rt.naturalCredited
                guard delta > 0 else { break }
                rt.naturalCredited = idle

                if idle >= cfg.duration {
                    // a natural break long enough to count as taking it
                    rt.nextStart = now.addingTimeInterval(cfg.scheduleMode.nextInterval)
                    rt.frozenAt = nil
                    runtimes[cfg.id] = rt
                    log.record(.autoFinished, break: cfg, durationSec: cfg.durationSec)
                    store.bumpCounter(cfg.id, \.done)
                } else if rt.nextStart > now {
                    rt.nextStart -= delta
                    runtimes[cfg.id] = rt
                }
            }
        }
    }

    private func hideOverlayIfNeeded(_ cfg: BreakConfig) {
        if OverlayController.shared.breakID == cfg.id {
            OverlayController.shared.hide(fade: cfg.controls.fadeOutSeconds)
        }
    }

    // MARK: Status strings (sidebar, menu bar)

    /// Main sidebar line, e.g. "due in 21 min, 8 secs" or "due at 13:45".

    func sidebarDueLine(for cfg: BreakConfig) -> String {
        guard let rt = runtimes[cfg.id] else { return "" }
        guard cfg.enabled else { return "Disabled" }
        if cfg.scheduleMode.isManual { return "manual only" }
        if rt.nextStart >= .distantFuture { return "not scheduled" }
        if isPaused { return pauseReason ?? "Paused" }
        if isBreakPaused(cfg.id) {
            if let until = store.settings.breakPauses[cfg.id.uuidString], until != .distantFuture {
                return "paused for \(TimeFmt.short(until.timeIntervalSince(now)))"
            }
            return "paused indefinitely"
        }
        switch rt.phase {
        case .idle:
            // the label counts to the moment the break screen appears
            let target = rt.nextStart
            if store.settings.relativeTimesInSidebar {
                return "due in \(TimeFmt.longSeconds(target.timeIntervalSince(now)))"
            }
            return "due at \(TimeFmt.timeOfDay.string(from: target))"
        case .ready:
            return "starting…"
        case .active:
            return "until \(TimeFmt.timeOfDay.string(from: rt.phaseEnd))"
        }
    }

    /// Second sidebar line: "new break", "had natural break" or today's counters.
    /// Second sidebar line: "done 19 hrs, 5 min ago" (natural noted), or "new break".
    func sidebarStatusLine(for cfg: BreakConfig) -> String? {
        if !cfg.enabled || isPaused { return nil }
        guard let last = log.lastCompletionEvent(forBreakID: cfg.id) else {
            return "new break"
        }
        let ago = TimeFmt.relAgo(now.timeIntervalSince(last.date))
        return last.kind == .autoFinished ? "natural \(ago)" : "done \(ago)"
    }

    /// Menu bar text according to the General settings (nil = icon only).
    func menuBarTitle() -> String? {
        let longOnly = store.settings.onlyLongBreaksInMenuBar
        let clockFmt = TimeFmt.timeOfDay

        func next() -> (cfg: BreakConfig, runtime: BreakRuntime)? {
            nextBreakInfo(longOnly: longOnly)
        }

        switch store.settings.labelMode {
        case .onlyIcon:
            return nil
        case .countdownBrief:
            guard let info = next() else { return "" }
            let target = info.runtime.nextStart
            return " " + TimeFmt.brief(max(0, target.timeIntervalSince(now)))
        case .countdownFull:
            guard let info = next() else { return "" }
            let target = info.runtime.nextStart
            return " " + TimeFmt.longSeconds(max(0, target.timeIntervalSince(now)))
        case .dueTime:
            guard let info = next() else { return "" }
            let target = info.runtime.nextStart
            return " " + clockFmt.string(from: target)
        case .finishTime:
            guard let info = next() else { return "" }
            return " " + clockFmt.string(from: info.runtime.nextStart.addingTimeInterval(info.cfg.duration))
        case .nextDuration:
            guard let info = next() else { return "" }
            return " " + TimeFmt.short(info.cfg.duration)
        case .lastDoneBrief, .lastDoneFull, .doneTime, .lastDuration:
            guard let info = next(),
                  let last = log.lastCompletionEvent(forBreakID: info.cfg.id) else { return "" }
            switch store.settings.labelMode {
            case .lastDoneBrief:
                let since = now.timeIntervalSince(last.date)
                return " " + (since < 60 ? "now" : TimeFmt.brief(since)) + " ago"
            case .lastDoneFull:
                let since = now.timeIntervalSince(last.date)
                return " " + TimeFmt.longSeconds(since) + " ago"
            case .doneTime:
                return " " + clockFmt.string(from: last.date)
            case .lastDuration:
                return " " + TimeFmt.short(Double(last.durationSec))
            default:
                return nil
            }
        }
    }

    /// Per-break submenu parent title, e.g. "Normal — due in 12 min".
    func menuSubtitle(for cfg: BreakConfig) -> String {
        sidebarDueLine(for: cfg)
    }
}
