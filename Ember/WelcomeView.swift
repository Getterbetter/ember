import EmberKit
import SwiftUI

/// First-launch window: three steps, then Ember gets out of the way.
struct WelcomeView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 18) {
            MascotView(mood: model.mood == .dazed ? .awake : model.mood, light: .system, size: 96)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("G'day, I'm Ember.").font(.title2.bold())
                Text("I look after your MagSafe charging light, so it stays dark when you want dark.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                step(
                    number: 1,
                    title: "Let me reach the light",
                    detail: "Changing the light needs admin rights, so I use a tiny helper. Approve \"Ember\" in Login Items.",
                    done: model.helperState == .enabled,
                    action: ("Open Login Items", model.approveHelper)
                )
                step(
                    number: 2,
                    title: "Tell me about your Focuses",
                    detail: "In each Focus you want dark: Focus Filters › Add Filter › Ember › MagSafe light: Off.",
                    done: model.settings.focusSetupDone,
                    action: ("Open Focus settings", model.openFocusSettings),
                    secondary: ("I've done this", model.markFocusSetupDone)
                )
                step(
                    number: 3,
                    title: "Keep me around",
                    detail: "Start Ember when you log in so the light behaves after a restart.",
                    done: model.launchAtLogin,
                    action: ("Open at login", { model.setLaunchAtLogin(true) })
                )
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))

            Button("All set") {
                model.finishWelcome()
                dismissWindow(id: "welcome")
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)

            Text("I live in the menu bar. Click me there any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            model.checkFocusFilterConfigured()
            // Count the welcome as seen the first time it shows, so it only opens on first launch.
            // It stays reachable from Ember's menu (… › Welcome & setup).
            model.finishWelcome()
            bringToFront()
        }
    }

    /// A menu bar app isn't frontmost when it launches, so pull the window up explicitly.
    private func bringToFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.identifier?.rawValue.contains("welcome") == true {
                window.center()
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    private func step(
        number: Int,
        title: String,
        detail: String,
        done: Bool,
        action: (String, @MainActor () -> Void),
        secondary: (String, @MainActor () -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.orange).frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.bold()).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !done {
                    HStack {
                        Button(action.0, action: action.1)
                        if let secondary {
                            Button(secondary.0, action: secondary.1).buttonStyle(.link)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
