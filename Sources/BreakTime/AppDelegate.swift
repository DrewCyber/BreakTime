import Foundation
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    let store = Store.shared
    lazy var log = ActivityLog(directory: store.supportURL)
    lazy var rules = RulesEngine()
    lazy var scheduler = Scheduler(store: store, log: log, rules: rules)

    private(set) var statusBar: StatusBarController?
    private var activityToken: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // keep timers alive despite App Nap
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "BreakTime break scheduler")

        if store.settings.showDockIcon {
            NSApp.setActivationPolicy(.regular)
        }

        rules.start()
        scheduler.start()
        Clock.shared.start()
        ActivityTracker.shared.method = store.settings.naturalBreakMethod
        ActivityTracker.shared.start()
        statusBar = StatusBarController(scheduler: scheduler, store: store)
        HotKeysBridge.refresh()

        // keep global shortcuts, rules and the idle tracker in sync with settings
        store.$settings
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] settings in
                HotKeysBridge.refresh()
                self?.rules.recheck()
                ActivityTracker.shared.method = settings.naturalBreakMethod
            }
            .store(in: &cancellables)

        if !store.hasLaunchedBefore {
            store.hasLaunchedBefore = true
            WelcomeWindowController.shared = WelcomeWindowController()
            WelcomeWindowController.shared?.show { [weak self] in
                self?.openSettings()
            }
        } else if CommandLine.arguments.contains("--settings") {
            let selection: SettingsSelection?
            if let idx = CommandLine.arguments.firstIndex(of: "--select"),
               CommandLine.arguments.indices.contains(idx + 1) {
                selection = SettingsSelection.parse(CommandLine.arguments[idx + 1])
            } else {
                selection = nil
            }
            openSettings(initialSelection: selection)
        }
    }

    func openSettings(initialSelection: SettingsSelection? = nil) {
        if SettingsWindowController.shared == nil {
            SettingsWindowController.shared = SettingsWindowController()
        }
        SettingsWindowController.shared?.show(initialSelection: initialSelection)
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler.stop()
        rules.stop()
        HotKeyCenter.shared.unregisterAll()
        OverlayController.shared.hide(fade: 0)
    }
}
