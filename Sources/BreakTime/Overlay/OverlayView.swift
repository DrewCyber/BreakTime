import SwiftUI

/// The non-blocking Get Ready banner: a small floating window with the
/// countdown and controls, so the screen stays usable before the break.
struct ReadyBannerView: View {
    let cfg: BreakConfig
    @ObservedObject var scheduler: Scheduler
    @ObservedObject private var clock = Clock.shared

    private var remaining: TimeInterval {
        guard let rt = scheduler.runtimes[cfg.id], rt.phase == .ready else { return 0 }
        return max(0, rt.phaseEnd.timeIntervalSince(clock.now))
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.stand")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.forestGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text("Get Ready — \(cfg.name) break")
                    .font(.system(size: 12, weight: .semibold))
                Text("starts in \(Int(remaining.rounded())) sec")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Menu {
                ForEach(cfg.controls.postponeOptions, id: \.self) { minutes in
                    Button("Postpone \(TimeFmt.minutesLong(minutes))") {
                        scheduler.postpone(cfg.id, minutes: minutes)
                    }
                }
            } label: {
                Text("Postpone")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(cfg.controls.postponeOptions.isEmpty)

            Button {
                scheduler.skip(cfg.id)
            } label: {
                Text("Skip")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .frame(width: 430, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// Full-screen break overlay: "Get Ready" pre-phase, then the break countdown
/// with Postpone / Skip controls, honoring the per-break Controls settings.
struct OverlayView: View {
    let cfg: BreakConfig
    @ObservedObject var scheduler: Scheduler
    @ObservedObject var store = Store.shared
    @ObservedObject var clock = Clock.shared

    private var runtime: BreakRuntime? {
        scheduler.runtimes[cfg.id]
    }

    private var remaining: TimeInterval {
        guard let rt = runtime else { return 0 }
        switch rt.phase {
        case .ready, .active:
            return max(0, rt.phaseEnd.timeIntervalSince(clock.now))
        case .idle:
            return 0
        }
    }

    private var total: TimeInterval {
        runtime?.phase == .active ? cfg.duration : Double(max(1, cfg.readySeconds))
    }

    private var buttons: (postpone: Bool, skip: Bool) {
        scheduler.overlayControls(for: cfg)
    }

    var body: some View {
        ZStack {
            (Color(hex: cfg.appearance.backgroundHex).opacity(cfg.appearance.opacity))
                .ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if runtime?.phase == .ready {
            VStack(spacing: 28) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Get Ready")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                Text("Your \(cfg.name) break starts in \(Int(remaining.rounded())) sec")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.85))
                controls
            }
        } else if runtime?.phase == .active {
            VStack(spacing: 26) {
                Text("\(cfg.name) Break")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)

                countdown

                Text("Time remaining")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.75))

                if cfg.controls.showTodayCounts {
                    Text(todayCountsLine)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }

                controls
            }
        }
    }

    private var todayCountsLine: String {
        let c = store.counters(for: cfg.id)
        return "Today: \(c.done) done, \(c.postponed) postponed, \(c.skipped) skipped"
    }

    @ViewBuilder
    private var countdown: some View {
        switch cfg.appearance.countdownStyle {
        case .ring:
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Text(TimeFmt.clock(remaining))
                    .font(.system(size: 58, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(width: 260, height: 260)
        case .bar:
            VStack(spacing: 12) {
                Text(TimeFmt.clock(remaining))
                    .font(.system(size: 96, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                ProgressView(value: 1 - progress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(maxWidth: 420)
            }
        case .digits:
            Text(TimeFmt.clock(remaining))
                .font(.system(size: 130, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private var progress: Double {
        guard total > 0 else { return 1 }
        return min(1, max(0, remaining / total))
    }

    @ViewBuilder
    private var controls: some View {
        let options = cfg.controls.postponeOptions.filter { _ in buttons.postpone }
        HStack(spacing: 14) {
            ForEach(options, id: \.self) { minutes in
                Button {
                    scheduler.postpone(cfg.id, minutes: minutes)
                } label: {
                    Label("Postpone \(TimeFmt.minutesLong(minutes))",
                          systemImage: "clock.arrow.circlepath")
                        .frame(minWidth: 170)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
                .foregroundStyle(.white)
            }

            if cfg.controls.showSkip {
                Button {
                    scheduler.skip(cfg.id)
                } label: {
                    Label("Skip Break", systemImage: "forward.fill")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
                .foregroundStyle(.white)
                .disabled(!buttons.skip)
                .opacity(buttons.skip ? 1 : 0.4)
            }

            if cfg.controls.showEndEarly, runtime?.phase == .active {
                Button {
                    scheduler.endBreakEarly(cfg.id)
                } label: {
                    Label("End Break", systemImage: "checkmark.circle.fill")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
                .foregroundStyle(.white)
                .disabled(!buttons.skip)
                .opacity(buttons.skip ? 1 : 0.4)
            }
        }
        .controlSize(.large)
        .padding(.top, 10)
        .opacity(buttons.postpone || buttons.skip ? 1 : 0.55)
        .help(buttons.postpone || buttons.skip
              ? "" : "Buttons are briefly disabled at the start of the break")
    }
}
