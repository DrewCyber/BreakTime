import Foundation
import AppKit
import SwiftUI

/// Shows the break overlay: one borderless panel per screen at screen-saver level,
/// with a fade in/out, hosting the SwiftUI overlay content.
final class OverlayController {
    static let shared = OverlayController()

    private var panels: [NSPanel] = []
    private var bannerPanel: NSPanel?
    private(set) var breakID: UUID?
    private var hideWorkItem: DispatchWorkItem?

    func show(cfg: BreakConfig, scheduler: Scheduler) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        breakID = cfg.id

        let phase = scheduler.runtimes[cfg.id]?.phase ?? .idle

        // The non-blocking Get Ready banner: a small floating window instead
        // of the fullscreen dim, so the screen stays usable while preparing.
        if phase == .ready, cfg.appearance.readyStyle == .banner {
            hideFullscreenPanels(instant: true)
            showBanner(cfg: cfg, scheduler: scheduler)
            return
        }

        hideBanner()
        showFullscreen(cfg: cfg, scheduler: scheduler)
    }

    private func showBanner(cfg: BreakConfig, scheduler: Scheduler) {
        let content = ReadyBannerView(cfg: cfg, scheduler: scheduler)
            .environmentObject(scheduler)
        let hosting = NSHostingView(rootView: content)
        hosting.setFrameSize(NSSize(width: 430, height: 64))

        let panel: NSPanel
        if let existing = bannerPanel {
            panel = existing
            panel.contentView = nil
        } else {
            panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = false
            panel.isMovable = true                  // drag by the body
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            bannerPanel = panel
        }
        panel.contentView = hosting

        // default position: top-center of the main screen (fresh every launch
        // and every new banner — the panel is recreated per break sequence)
        if let screen = NSScreen.main {
            let x = screen.frame.midX - 215
            let y = screen.frame.maxY - 72
            panel.setFrame(NSRect(x: x, y: y, width: 430, height: 64), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func hideBanner() {
        bannerPanel?.orderOut(nil)
        bannerPanel?.contentView = nil
        bannerPanel = nil   // dropped after each sequence → default position next time
    }

    private func hideFullscreenPanels(instant: Bool) {
        panels.forEach { $0.orderOut(nil) }
        if instant {
            panels.forEach { $0.contentView = nil }
            panels.removeAll()
        }
    }

    private func showFullscreen(cfg: BreakConfig, scheduler: Scheduler) {
        let screens = cfg.appearance.showOnAllScreens ? NSScreen.screens
            : [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }

        if panels.count != screens.count {
            tearDown()
        }

        for (index, screen) in screens.enumerated() {
            let panel: NSPanel
            if index < panels.count {
                panel = panels[index]
                if panel.screen != screen {
                    panel.setFrame(screen.frame, display: false)
                }
                panel.contentView = nil
            } else {
                panel = NSPanel(contentRect: screen.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = false
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panels.append(panel)
            }

            let view = OverlayView(cfg: cfg, scheduler: scheduler)
                .environmentObject(scheduler)
            let hosting = NSHostingView(rootView: view)
            hosting.setFrameSize(panel.frame.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.setFrame(screen.frame, display: true)

            let fade = cfg.controls.fadeInSeconds
            if fade <= 0.01 {
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            } else {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = fade
                    panel.animator().alphaValue = 1
                })
            }
        }
    }

    func hide(fade: Double = 0.5) {
        breakID = nil
        hideBanner()
        let snapshot = panels
        let duration = max(0.05, fade)
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            snapshot.forEach { $0.orderOut(nil) }
            self?.tearDown()
        }
        hideWorkItem = work
        if fade <= 0.01 {
            work.perform()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.completionHandler = { work.perform() }
            snapshot.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: nil)
        // safety net in case the completion handler is dropped
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.5, execute: work)
    }

    private func tearDown() {
        panels.forEach { $0.orderOut(nil) }
        panels.forEach { $0.contentView = nil }
        panels.removeAll()
    }
}
