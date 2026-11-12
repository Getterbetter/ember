import AppKit
import Combine
import EmberKit
import os
import ServiceManagement

/// Ember's brain: holds settings, decides the light state, and keeps the hardware in line.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: EmberSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            if !isReconciling { reconcileSoon() }
        }
    }
    @Published private(set) var focus: FocusLightChoice
    @Published private(set) var decision: Decision
    @Published private(set) var problem: ProblemKind?
    @Published private(set) var helperState: HelperClient.State = .unknown
    @Published private(set) var aldenteRunning = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var isWaving = false
    @Published private(set) var lastError: String?
    /// Overrides the headline briefly after a poke or a wave.
    @Published private(set) var transientLine: String?
    @Published private(set) var transientMood: Mood?
    @Published private(set) var lineSeed = Int.random(in: 0..<1000)

    var mood: Mood { transientMood ?? Personality.mood(for: decision, problem: problem) }
    var headline: String {
        transientLine ?? Personality.line(for: decision, problem: problem, seed: lineSeed)
    }
    var statusText: String { Personality.status(for: decision) }

    private let store = SettingsStore()
    private let helper = HelperClient()
    private let power = PowerMonitor()
    private let log = Logger(subsystem: EmberIdentity.appBundleID, category: "model")
    private var lastApplied: LightTarget?
    private var timer: Timer?
    private var started = false
    private var reconcileTask: Task<Void, Never>?
    private var transientTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var hardwareSupported: Bool?
    private var isReconciling = false
    private var uninstalled = false

    private init() {
        let store = SettingsStore()
        let settings = store.loadSettings()
        let focus = store.loadFocus()
        self.settings = settings
        self.focus = focus
        self.decision = Policy.decide(settings.policyInputs(now: Date(), focus: focus, battery: PowerMonitor.snapshot()))
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        hardwareSupported = Self.probeHardware()
        clearExpiredSnooze()
        registerHelperIfNeeded()
        refreshLaunchAtLogin()
        refreshAlDente()
        checkFocusFilterConfigured()
        upgradeHelperIfNeeded()

        power.onChange = { [weak self] in self?.reconcileSoon(force: true) }
        power.start()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAlDente() }
            })
        }

        // A light check every 30 s re-asserts the state if macOS reset it, and catches
        // snooze and schedule boundaries.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileSoon() }
        }
        reconcileSoon(force: true)
    }

    /// Whether quitting has to hand the light back first. After an uninstall the helper is gone,
    /// so there's nothing to release.
    var needsLightRelease: Bool {
        !uninstalled && hardwareSupported != false && helper.state == .enabled
    }

    /// Called on quit: hand the light back to macOS.
    func releaseLight() async {
        timer?.invalidate()
        guard needsLightRelease else { return }
        try? await helper.setLight(LightTarget.system.smcValue)
    }

    /// Uninstall: give the light back and remove the root helper from launchd.
    func prepareForUninstall() async {
        timer?.invalidate()
        if helper.state == .enabled {
            try? await helper.setLight(LightTarget.system.smcValue)
        }
        try? await helper.unregister()
        uninstalled = true
    }

    /// After an app update, a helper from the old version may still be running as root.
    /// Ask it to exit so launchd starts the new one; fall back to re-registering for helpers
    /// too old to understand that.
    private func upgradeHelperIfNeeded() {
        Task {
            guard helper.state == .enabled, let running = await helper.helperVersion(),
                  running != EmberIdentity.helperVersion else { return }
            log.info("helper \(running, privacy: .public) is out of date; restarting it")
            await helper.restartHelper()
            if let after = await helper.helperVersion(), after != EmberIdentity.helperVersion {
                // Helpers older than 1.1.0 don't know quit(). They still work, so leave them be:
                // unregistering here would need a fresh approval in Login Items. "Reinstall helper"
                // in the menu swaps it when the person chooses to.
                log.info("helper \(after, privacy: .public) can't restart itself; keeping it until a manual reinstall")
            }
            lastApplied = nil
            reconcileSoon(force: true)
        }
    }

    // MARK: Actions from the menu, Shortcuts and Focus

    func setMode(_ mode: LightMode) {
        settings.mode = mode
        bumpLine()
    }

    func snooze(minutes: Int) {
        settings.snooze = Snooze(target: .off, until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        bumpLine()
    }

    func snoozeUntilMorning() {
        settings.snooze = Snooze(target: .off, until: SnoozeMath.morning(after: Date(), schedule: settings.schedule, calendar: .current))
        bumpLine()
    }

    func cancelSnooze() {
        settings.snooze = nil
        bumpLine()
    }

    func applyFocus(_ choice: FocusLightChoice) {
        log.info("focus filter says \(choice.rawValue, privacy: .public)")
        focus = choice
        store.saveFocus(choice)
        if choice != .followEmber { markFocusSetupDone() }
        bumpLine()
        reconcileSoon(force: true)
    }

    func poke() {
        showTransient(line: Personality.poke(seed: Int.random(in: 0..<1000)), mood: .wink, seconds: 4)
    }

    func wave() {
        guard !isWaving else { return }
        isWaving = true
        showTransient(line: Personality.waveLine(seed: Int.random(in: 0..<100)), mood: .wink, seconds: 4)
        Task {
            if helper.state == .enabled {
                for step in WavePattern.steps {
                    try? await helper.setLight(step.smcValue)
                    try? await Task.sleep(nanoseconds: UInt64(WavePattern.stepInterval * 1_000_000_000))
                }
            }
            isWaving = false
            lastApplied = nil
            reconcileSoon(force: true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    func approveHelper() {
        registerHelperIfNeeded()
        helper.openLoginItemsSettings()
    }

    /// Removes and re-adds the helper. macOS asks for approval again in Login Items.
    func reinstallHelper() {
        Task {
            try? await helper.unregister()
            // Background Task Management needs a moment after an unregister; registering straight
            // away fails with "Operation not permitted".
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            registerHelperIfNeeded()
            if helper.state != .enabled {
                helper.openLoginItemsSettings()
            }
            lastApplied = nil
            reconcileSoon(force: true)
        }
    }

    func openFocusSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Focus-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    func finishWelcome() {
        settings.hasFinishedWelcome = true
    }

    func markFocusSetupDone() {
        if !settings.focusSetupDone { settings.focusSetupDone = true }
    }

    /// If a Focus with Ember's filter is on right now, the setup step is clearly done.
    func checkFocusFilterConfigured() {
        guard !settings.focusSetupDone else { return }
        Task {
            if let current = try? await EmberFocusFilter.current, current.light != nil {
                markFocusSetupDone()
            }
        }
    }

    // MARK: Reconcile

    func reconcileSoon(force: Bool = false) {
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            await self?.reconcile(force: force)
        }
    }

    private func reconcile(force: Bool) async {
        guard !isWaving, !uninstalled else { return }
        isReconciling = true
        clearExpiredSnooze()
        isReconciling = false
        helperState = helper.state

        let newDecision = Policy.decide(settings.policyInputs(now: Date(), focus: focus, battery: PowerMonitor.snapshot()))
        if newDecision.reason != decision.reason { bumpLine() }
        decision = newDecision

        guard hardwareSupported != false else {
            problem = .unsupportedMac
            return
        }
        guard helperState == .enabled else {
            problem = helperState == .requiresApproval ? .helperNeedsApproval : .helperUnavailable
            return
        }

        let target = newDecision.target
        var shouldWrite = force || lastApplied != target
        if !shouldWrite, target.needsReassert, let raw = Self.readLight(), !target.matches(raw: raw) {
            log.info("light drifted to \(raw, privacy: .public); re-applying \(target.rawValue, privacy: .public)")
            shouldWrite = true
        }
        guard shouldWrite else { return }

        do {
            try await helper.setLight(target.smcValue)
            lastApplied = target
            problem = nil
            lastError = nil
        } catch {
            log.error("couldn't set light: \(String(describing: error), privacy: .public)")
            lastApplied = nil
            problem = .writeFailed
            lastError = String(describing: error)
        }
    }

    // MARK: Helpers

    private func registerHelperIfNeeded() {
        guard hardwareSupported != false else { return }
        if helper.state == .notRegistered || helper.state == .notFound {
            do {
                try helper.register()
            } catch {
                log.error("helper register failed: \(error.localizedDescription, privacy: .public)")
                lastError = "Couldn't install the helper: \(error.localizedDescription)"
            }
        }
        helperState = helper.state
    }

    private func clearExpiredSnooze() {
        if let snooze = settings.snooze, !snooze.isActive(at: Date()) {
            settings.snooze = nil
        }
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func refreshAlDente() {
        aldenteRunning = NSWorkspace.shared.runningApplications.contains { app in
            let id = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            return id.contains("aldente") || name.contains("aldente")
        }
    }

    private func bumpLine() {
        lineSeed &+= 1
    }

    private func showTransient(line: String, mood: Mood, seconds: Double) {
        transientTask?.cancel()
        transientLine = line
        transientMood = mood
        transientTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.transientLine = nil
            self?.transientMood = nil
        }
    }

    /// Reading the SMC needs no privileges, so the app checks the light itself.
    private static func readLight() -> UInt8? {
        guard let smc = try? SMCConnection(), let bytes = try? smc.read(SMCKey.magSafeLED) else { return nil }
        return bytes.first
    }

    /// `false` only when the SMC clearly says there's no MagSafe light key.
    private static func probeHardware() -> Bool? {
        do {
            let smc = try SMCConnection()
            _ = try smc.keyInfo(SMCKey.magSafeLED)
            return true
        } catch SMCError.keyNotFound {
            return false
        } catch {
            return nil
        }
    }
}
