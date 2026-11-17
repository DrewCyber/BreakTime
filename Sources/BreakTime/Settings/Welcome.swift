import SwiftUI

/// First-launch welcome window, in the spirit of the original's setup assistant.
struct WelcomeView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "timer")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
                .padding(.top, 28)

            Text("Welcome to BreakTime")
                .font(.title.bold())

            Text("BreakTime helps you remember to take regular breaks,\nso you can stay comfortable and productive.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                welcomeRow("figure.stand",
                           "**Normal break** — 10 minutes every hour to stand, stretch and rest your eyes.")
                welcomeRow("figure.arms.open",
                           "**Micro break** — 15 seconds every 5 minutes to look away and reset.")
                welcomeRow("slider.horizontal.3",
                           "Choose **Settings** in the menu bar to adjust schedules, appearance and more.")
            }
            .padding(.horizontal, 28)

            Button {
                onGetStarted()
            } label: {
                Text("Get Started")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 26)
        }
        .frame(width: 460, height: 470)
    }

    private func welcomeRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Group {
                if let attr = try? AttributedString(markdown: text) {
                    Text(attr)
                } else {
                    Text(text)
                }
            }
            .foregroundStyle(.primary)
        }
    }
}

final class WelcomeWindowController {
    static var shared: WelcomeWindowController?

    private var window: NSWindow?

    func show(onFinish: @escaping () -> Void) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        w.title = "Welcome to BreakTime"
        w.contentView = NSHostingView(rootView: WelcomeView(onGetStarted: {
            w.close()
            onFinish()
        }))
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
