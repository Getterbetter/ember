import AppKit
import EmberKit
import ServiceManagement

/// Update checks, About and Uninstall: the housekeeping a public app needs.
enum EmberLinks {
    static let repo = "Getterbetter/ember"
    static let home = URL(string: "https://github.com/\(repo)")!
    static let releases = URL(string: "https://github.com/\(repo)/releases")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

struct LatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

@MainActor
enum Maintenance {
    /// Asks GitHub for the latest release. Only runs when the person picks "Check for Updates…".
    static func checkForUpdates() {
        Task {
            NSApp.activate(ignoringOtherApps: true)
            do {
                var request = URLRequest(url: EmberLinks.latestReleaseAPI, timeoutInterval: 15)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Ember/\(EmberLinks.appVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let release = try JSONDecoder().decode(LatestRelease.self, from: data)
                let current = SemanticVersion(EmberLinks.appVersion)
                let latest = SemanticVersion(release.tagName)
                if let current, let latest, current < latest {
                    let alert = NSAlert()
                    alert.messageText = "Ember \(latest) is out"
                    alert.informativeText = "You have \(current). Download the new version, quit Ember, and replace it in Applications."
                    alert.addButton(withTitle: "Download")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(release.htmlURL)
                    }
                } else {
                    info("You're up to date", "Ember \(EmberLinks.appVersion) is the latest version. Still glowing.")
                }
            } catch {
                info("Couldn't check for updates", "GitHub didn't answer. You can always look at \(EmberLinks.releases.absoluteString).")
            }
        }
    }

    static func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(
            string: "Looks after your MagSafe charging light.\nFree and open source (MIT).\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        credits.append(NSAttributedString(
            string: EmberLinks.home.absoluteString,
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: EmberLinks.home]
        ))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Ember",
            .credits: credits,
        ])
    }

    /// Asks first, then hands the light back, removes the helper and login item, forgets settings,
    /// moves Ember to the Bin (or shows it in Finder if it can't), and quits.
    static func uninstall(model: AppModel) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall Ember?"
        alert.informativeText = "Ember will hand the light back to macOS, remove its helper, stop opening at login, forget its settings and move itself to the Bin."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await model.prepareForUninstall()
            try? await SMAppService.mainApp.unregister()
            if let id = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: id)
            }
            let bundle = Bundle.main.bundleURL
            do {
                _ = try await NSWorkspace.shared.recycle([bundle])
            } catch {
                NSWorkspace.shared.activateFileViewerSelecting([bundle])
            }
            // Quit from the run loop, not from inside this task. terminate(_:) spins a nested run
            // loop on the main thread, and calling it from a main-actor task blocks the main queue,
            // so nothing queued there (like the quit reply) could ever run.
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        }
    }

    private static func info(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
