import SwiftUI
import AppKit

// MARK: - Rules page ("If [app] is frontmost → …" / script detectors)

/// Starter detector scripts (our own heuristics — edit them to taste).
enum RuleTemplates {
    static let faceTime = Rule(
        appBundleID: "detector.facetime",
        appName: "FaceTime Meeting",
        action: .skip,
        script: """
        # Active while a FaceTime / Continuity call is in progress
        pgrep -x avconferenced >/dev/null
        """)

    static let zoom = Rule(
        appBundleID: "detector.zoom",
        appName: "Zoom Meeting",
        action: .skip,
        script: """
        # Active while Zoom is running a meeting (helper utilities spawn during calls)
        pgrep -x zoom.us >/dev/null && pgrep -f "zoom.us.*--type=utility" >/dev/null
        """)

    static let custom = Rule(
        appBundleID: "detector.custom",
        appName: "Custom Detector",
        action: .skip,
        script: """
        # Exit 0 when the condition is active, any other code otherwise.
        # Runs every ~15 seconds with a 5 second timeout. For example,
        # check that a VPN is connected:
        # ifconfig | grep -q "utun"
        exit 1
        """)
}

struct RulesPage: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var rules: RulesEngine

    @State private var addingRule = false
    @State private var selectedBundleID: String?
    @State private var editingRule: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rules on what to do when a break is due, or a natural break.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("App is frontmost…") { addingRule = true }
                    Divider()
                    Button("FaceTime Meeting Detector") { add(RuleTemplates.faceTime) }
                    Button("Zoom Meeting Detector") { add(RuleTemplates.zoom) }
                    Divider()
                    Button("Custom Script Detector…") { add(RuleTemplates.custom) }
                } label: {
                    Label("Add", systemImage: "plus")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.forestGreen))
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(16)

            Divider()

            if store.settings.rules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No rules")
                        .font(.headline)
                    Text("Add a rule to skip or pause breaks while an app is frontmost, or run a detector script — for example during video calls.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    Button("Add Rule") { addingRule = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.settings.rules) { rule in
                            RuleRow(rule: bindingFor(rule)) { editingRule = rule }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 520)
        .sheet(isPresented: $addingRule) {
            RuleAddSheet(selection: $selectedBundleID) { app in
                guard !store.settings.rules.contains(where: { $0.appBundleID == app.bundleID }) else { return }
                store.settings.rules.append(Rule(appBundleID: app.bundleID, appName: app.name))
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleScriptSheet(rule: bindingFor(rule))
        }
    }

    private func add(_ template: Rule) {
        var copy = template
        copy.id = UUID()
        store.settings.rules.append(copy)
        editingRule = copy
    }

    private func bindingFor(_ rule: Rule) -> Binding<Rule> {
        Binding(
            get: {
                store.settings.rules.first { $0.id == rule.id } ?? rule
            },
            set: { newValue in
                if let idx = store.settings.rules.firstIndex(where: { $0.id == rule.id }) {
                    store.settings.rules[idx] = newValue
                }
            })
    }
}

private struct RuleRow: View {
    @Binding var rule: Rule
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $rule.enabled).labelsHidden().fixedSize()

            Text("If")
            if rule.isScript {
                Button(action: onEdit) {
                    Label(rule.appName, systemImage: "terminal")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(rule.script)

                Picker("", selection: .constant(0)) {
                    Text("script").tag(0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(true)

                Picker("", selection: .constant(0)) {
                    Text("succeeds").tag(0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(true)
            } else {
                Text(rule.appName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.appBundleID)

                Picker("", selection: .constant(0)) {
                    Text("is").tag(0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(true)

                Picker("", selection: .constant(0)) {
                    Text("frontmost").tag(0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(true)
            }

            Picker("", selection: $rule.action) {
                ForEach(RuleAction.allCases) { action in
                    Text(action.label).tag(action)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Spacer()

            if rule.isScript {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit the detector script")
            }

            Button {
                if let idx = Store.shared.settings.rules.firstIndex(where: { $0.id == rule.id }) {
                    Store.shared.settings.rules.remove(at: idx)
                }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete this rule")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }
}

/// Editor for script detector rules, with a live Test button.
private struct RuleScriptSheet: View {
    @Binding var rule: Rule
    @Environment(\.dismiss) private var dismiss
    @State private var testResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detector Script")
                .font(.headline)

            HStack {
                Text("Name:")
                TextField("Name", text: $rule.appName)
                    .textFieldStyle(.roundedBorder)
            }

            Text("The rule is active while this shell script exits with status 0. It runs about every 15 seconds with a 5 second timeout.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextEditor(text: $rule.script)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 460, height: 160)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.15)))

            if let result = testResult {
                Label(result,
                      systemImage: result == "Active" ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(result == "Active" ? Color.forestGreen : .secondary)
                    .font(.system(size: 12))
            }

            HStack {
                Button("Test") {
                    let active = RulesEngine.runShell(rule.script, timeout: 5)
                    testResult = active ? "Active" : "Not active"
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500)
        .onDisappear { AppDelegate.shared?.rules.recheck() }
    }
}

private struct RuleCandidate: Identifiable, Equatable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

private struct RuleAddSheet: View {
    let onAdd: (RuleCandidate) -> Void
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    init(selection: Binding<String?>, onAdd: @escaping (RuleCandidate) -> Void) {
        self._selection = selection
        self.onAdd = onAdd
    }

    private var candidates: [RuleCandidate] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var seen: [String: RuleCandidate] = [:]
        apps.forEach { app in
            guard let bundleID = app.bundleIdentifier else { return }
            seen[bundleID] = RuleCandidate(bundleID: bundleID,
                                           name: app.localizedName ?? bundleID)
        }
        let existing = Set(Store.shared.settings.rules.map { $0.appBundleID })
        return seen.values
            .filter { !existing.contains($0.bundleID) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Pause or skip breaks when this app is frontmost:")
                .font(.headline)
                .padding()

            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(candidates) { app in
                Button {
                    selection = app.bundleID
                } label: {
                    HStack {
                        Text(app.name)
                        Spacer()
                        if selection == app.bundleID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(height: 280)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add Rule") {
                    if let id = selection,
                       let app = candidates.first(where: { $0.bundleID == id }) {
                        onAdd(app)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .padding()
        }
        .frame(width: 430, height: 460)
    }
}

// MARK: - Advanced page

struct AdvancedPage: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler

    @State private var confirmReset = false

    private let thresholds: [Int] = [15, 30, 60, 120, 300, 600]

    var body: some View {
        TabForm {
            SettingsRow("Natural break detection method:", labelWidth: 270) {
                Picker("", selection: $store.settings.naturalBreakMethod) {
                    ForEach(NaturalBreakMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()   // width by the longest item, like the reference
            }
            Text("Used to detect when the computer is idle. The Event Source method works without adding the app to the Accessibility System Settings, but the Event Monitor method is more reliable.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620, alignment: .leading)

            AccessibilityWarningRow()

            SettingsRow("Natural break active threshold:", labelWidth: 270) {
                Picker("", selection: $store.settings.naturalBreakThresholdSec) {
                    ForEach(thresholds, id: \.self) { sec in
                        Text(TimeFmt.short(Double(sec))).tag(sec)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220)
                .disabled(store.settings.naturalBreakMethod == .none)
            }
            Text("How long the computer is idle before counting it as a natural break. Set the detection method to None to disable natural breaks.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620, alignment: .leading)

            SectionDivider()

            Text("Hide:")
                .font(.system(size: 13, weight: .semibold))
            Text("Are these ways to avoid breaks too tempting?")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                hideToggle("Pause", "pause")
                hideToggle("Make Due", "makeDue")
                hideToggle("Reset", "reset")
                hideToggle("Disable", "disable")
                hideToggle("Delete", "delete")
                hideToggle("Quit", "quit")
            }
            .padding(.leading, 6)

            SectionDivider()

            HStack {
                Button("Reset Break Timers") { scheduler.resetAll() }
                Button("Reset All Settings", role: .destructive) { confirmReset = true }
                Spacer()
            }
            Text("“Reset All Settings” restores the default Normal and Micro breaks and clears every setting. The activity log is kept.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520, alignment: .leading)
        }
        .confirmationDialog("Reset all settings to defaults?", isPresented: $confirmReset) {
            Button("Reset Settings", role: .destructive) {
                store.resetToDefaults()
                HotKeysBridge.refresh()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func hideToggle(_ label: String, _ key: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { store.settings.isHidden(key) },
            set: { hide in
                if hide {
                    if !store.settings.hiddenItems.contains(key) {
                        store.settings.hiddenItems.append(key)
                    }
                } else {
                    store.settings.hiddenItems.removeAll { $0 == key }
                }
            }))
    }
}

/// The Accessibility hint for Event Monitor. Isolated in its own view so the
/// per-second trust re-check doesn't re-render the whole Advanced page
/// (which interfered with the popup menu positioning).
struct AccessibilityWarningRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var clock = Clock.shared

    var body: some View {
        if store.settings.naturalBreakMethod == .eventMonitor,
           !ActivityTracker.isTrustedForAccessibility {
            HStack {
                Label("Event Monitor needs Accessibility access — currently using Event Source.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Button("Open System Settings…") {
                        ActivityTracker.requestAccessibility()
                    }
                    .controlSize(.small)
            }
        }
    }
}
