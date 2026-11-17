import SwiftUI
import Charts

// MARK: - Activity page (segmented Activity | Statistics in the content header)

struct ActivityPage: View {
    let tab: ActivityTab
    let onTabChange: (ActivityTab) -> Void

    @EnvironmentObject var log: ActivityLog
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                segButton("Activity", .log)
                segButton("Statistics", .statistics)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch tab {
                case .log: ActivityLogTab()
                case .statistics: StatisticsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .tint(.forestGreen)
    }

    private func segButton(_ title: String, _ value: ActivityTab) -> some View {
        Button {
            onTabChange(value)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(tab == value ? Color.forestGreen : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    Capsule().strokeBorder(tab == value ? Color.forestGreen : Color.primary.opacity(0.15),
                                           lineWidth: 1)
                )
                .foregroundStyle(tab == value ? .white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity tab (Today group + rows)

struct ActivityLogTab: View {
    @EnvironmentObject var log: ActivityLog
    @EnvironmentObject var store: Store

    @State private var breakFilter: UUID?
    @State private var todayExpanded = true
    @State private var confirmClear = false

    private var allFiltered: [ActivityEvent] {
        let base = log.events.reversed()
        guard let id = breakFilter else { return Array(base) }
        return base.filter { $0.breakID == id }
    }

    private var todayEvents: [ActivityEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        return allFiltered.filter { $0.date >= start }
    }

    private var earlierEvents: [ActivityEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        return allFiltered.filter { $0.date < start }
    }

    var body: some View {
        if log.events.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
                Text("No Activity")
                    .font(.title3).bold()
                    .foregroundStyle(.secondary)
                Text("Break events will appear here. This is the status of your breaks; if a break didn't occur when you expected it, the reason should be shown here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Picker("Break", selection: $breakFilter) {
                        Text("All").tag(UUID?.none)
                        ForEach(store.breaks) { cfg in
                            Text(cfg.name).tag(UUID?.some(cfg.id))
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Button("Clear Log", role: .destructive) { confirmClear = true }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        DisclosureGroup(isExpanded: $todayExpanded) {
                            ForEach(todayEvents) { event in
                                ActivityRow(event: event)
                            }
                        } label: {
                            Text("Today")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }

                        ForEach(earlierEvents.prefix(200)) { event in
                            ActivityRow(event: event)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .confirmationDialog("Clear the activity log?", isPresented: $confirmClear) {
                Button("Clear Log", role: .destructive) { log.clear() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolFor(event.kind))
                .frame(width: 22)
                .foregroundStyle(colorFor(event.kind))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(event.breakName) break — \(event.kind.label.lowercased())")
                    .font(.system(size: 13))
                if event.kind == .postponed {
                    Text("postponed by \(event.postponeMinutes) min")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if event.durationSec > 0 {
                    Text("duration \(TimeFmt.clock(Double(event.durationSec)))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(event.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }

    private func symbolFor(_ kind: ActivityKind) -> String {
        switch kind {
        case .started: return "play.circle"
        case .finished: return "checkmark.circle"
        case .autoFinished: return "moon.zzz"
        case .skipped: return "forward.circle"
        case .autoSkipped: return "arrow.right.circle"
        case .postponed: return "clock.arrow.circlepath"
        case .preview: return "eye"
        case .naturalReset: return "arrow.counterclockwise.circle"
        }
    }

    private func colorFor(_ kind: ActivityKind) -> Color {
        switch kind {
        case .started: return .blue
        case .finished: return .green
        case .autoFinished: return .indigo
        case .skipped, .autoSkipped: return .orange
        case .postponed: return .teal
        case .naturalReset: return .mint
        case .preview: return .secondary
        }
    }
}

// MARK: - Statistics tab

struct StatisticsTab: View {
    @EnvironmentObject var log: ActivityLog

    @State private var rangeDays: Int = 7

    private var stats: [DayStat] { log.dayStats(days: rangeDays) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $rangeDays) {
                    Text("7 Days").tag(7)
                    Text("30 Days").tag(30)
                    Text("90 Days").tag(90)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                summaryCards

                GroupBox("Breaks per day") {
                    Chart(stats) { d in
                        BarMark(
                            x: .value("Day", d.date, unit: .day),
                            y: .value("Breaks", d.total)
                        )
                        .foregroundStyle(
                            by: .value("Break", d.normalCount >= d.microCount ? "Normal" : "Micro"))
                    }
                    .chartForegroundStyleScale([
                        "Normal": Color.forestGreen,
                        "Micro": Color.teal
                    ])
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .frame(height: 190)
                    .padding(6)
                }

                GroupBox("Break minutes per day") {
                    Chart(stats) { d in
                        BarMark(
                            x: .value("Day", d.date, unit: .day),
                            y: .value("Minutes", d.minutes)
                        )
                        .foregroundStyle(Color.forestGreen.opacity(0.75))
                    }
                    .frame(height: 170)
                    .padding(6)
                }
            }
            .padding(20)
        }
    }

    private var summaryCards: some View {
        let today = log.todayStats()
        let streak = log.streak()
        return HStack(spacing: 12) {
            StatCard(title: "Today", value: "\(today.count) breaks",
                     detail: String(format: "%.0f min total", today.minutes))
            StatCard(title: "Streak", value: "\(streak) day\(streak == 1 ? "" : "s")",
                     detail: streak > 0 ? "Keep it up!" : "Take a break today")
            StatCard(title: "All time", value: "\(log.totalFinished) breaks",
                     detail: String(format: "%.1f hours", log.totalMinutes / 60))
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).bold()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quinary.opacity(0.35)))
    }
}
