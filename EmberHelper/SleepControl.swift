import Foundation
import IOKit.ps
import os

/// "Stay awake on the charger", on the root side.
///
/// Turns macOS sleep off and on with `pmset disablesleep`, the one switch that also stops lid-close
/// and Apple-menu sleep. Ember must never leave it off, so this turns sleep back on by itself on
/// battery, when the app goes away, before the helper exits for an update, and at start-up if a
/// marker file says Ember turned it off before a crash. It only ever turns sleep back on if Ember
/// turned it off, so it leaves alone a `disablesleep` someone set themselves.
///
/// Use it only on the helper's serial queue.
final class SleepControl {
    enum Failure: Error, CustomStringConvertible {
        case onBattery
        case pmset(status: Int32)

        var description: String {
            switch self {
            case .onBattery: return "the Mac is on battery, so it's allowed to sleep"
            case .pmset(let status): return "pmset exited with status \(status)"
            }
        }
    }

    private let queue: DispatchQueue
    private let marker: URL
    private let log = Logger(subsystem: EmberIdentity.helperLabel, category: "sleep")
    private var disabledByEmber = false
    private var batteryCheck: DispatchSourceTimer?

    init(queue: DispatchQueue) {
        self.queue = queue
        marker = URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)
            .appendingPathComponent(EmberIdentity.helperLabel, isDirectory: true)
            .appendingPathComponent("sleep-disabled")
    }

    /// `true` turns sleep off (plugged in only), `false` turns it back on. Repeats do nothing.
    func set(disabled: Bool) throws {
        guard disabled else {
            try restore(reason: "Ember asked")
            return
        }
        guard Self.isOnACPower() else {
            try restore(reason: "on battery")
            throw Failure.onBattery
        }
        guard !disabledByEmber else { return }
        // Marker first: if anything dies after this, the next start turns sleep back on.
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: marker.path, contents: nil)
        do {
            try Self.pmset(disableSleep: true)
        } catch {
            try? FileManager.default.removeItem(at: marker)
            throw error
        }
        disabledByEmber = true
        startBatteryCheck()
        log.info("sleep off: plugged in with the light off")
    }

    /// Turns sleep back on if Ember turned it off, now or before a crash. Safe to call any time.
    func restore(reason: String) throws {
        let leftOver = FileManager.default.fileExists(atPath: marker.path)
        guard disabledByEmber || leftOver else { return }
        try Self.pmset(disableSleep: false)
        try? FileManager.default.removeItem(at: marker)
        disabledByEmber = false
        batteryCheck?.cancel()
        batteryCheck = nil
        log.info("sleep back on (\(reason, privacy: .public))")
    }

    /// A backstop for the app's own unplug handling: never keep a Mac awake on battery.
    private func startBatteryCheck() {
        guard batteryCheck == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(15), repeating: .seconds(15))
        timer.setEventHandler { [weak self] in
            guard let self, !Self.isOnACPower() else { return }
            do {
                try self.restore(reason: "unplugged")
            } catch {
                self.log.error("couldn't turn sleep back on: \(String(describing: error), privacy: .public)")
            }
        }
        timer.resume()
        batteryCheck = timer
    }

    /// Whether the Mac is running from the charger. Unknown counts as battery, so sleep wins.
    static func isOnACPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        // kIOPSACPowerValue is "AC Power", the same string as the providing type kIOPMACPowerKey.
        return (type as String) == kIOPSACPowerValue
    }

    private static func pmset(disableSleep: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disableSleep ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.pmset(status: process.terminationStatus) }
    }
}
