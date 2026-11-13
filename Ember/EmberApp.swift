import AppKit
import EmberKit
import SwiftUI

@main
struct EmberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: model.mood))
                .accessibilityLabel("Ember, \(model.statusText)")
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to Ember", id: "welcome") {
            WelcomeView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.settings.hasFinishedWelcome ? .suppressed : .presented)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if Self.isOutsideApplications {
                Self.askToMoveToApplications()
                return
            }
            AppModel.shared.start()
        }
    }

    /// Opened straight from Downloads, macOS runs a quarantined app from a random read-only
    /// copy (App Translocation). Its root helper can't be registered reliably from there, so
    /// Ember asks to be moved first.
    static var isOutsideApplications: Bool {
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") { return true }
        let roots = ["/Applications/", NSHomeDirectory() + "/Applications/"]
        return !roots.contains { path.hasPrefix($0) }
    }

    @MainActor
    private static func askToMoveToApplications() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Ember to Applications first"
        alert.informativeText = "Ember needs to live in your Applications folder to install its light helper. Quit, drag Ember from Downloads into Applications, then open it from there."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Show Applications")
        let choice = alert.runModal()
        if choice == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }

    /// Hand the light back to macOS before quitting, so it never stays stuck off.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let needsRelease = MainActor.assumeIsolated { AppModel.shared.needsLightRelease }
        guard needsRelease else { return .terminateNow }
        Task { @MainActor in
            // Whichever finishes first: the release, or a 2 s deadline.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await AppModel.shared.releaseLight() }
                group.addTask { try? await Task.sleep(nanoseconds: 2_000_000_000) }
                await group.next()
                group.cancelAll()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
