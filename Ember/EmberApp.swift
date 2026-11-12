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
            AppModel.shared.start()
        }
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
