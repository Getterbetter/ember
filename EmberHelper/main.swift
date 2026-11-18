import Foundation
import os

// Ember's privileged helper. launchd starts it as root on demand (SMAppService daemon).
// It writes allowed values to the MagSafe light SMC key, and, only for "Stay awake on the
// charger", switches macOS sleep off and back on (see SleepControl).

let log = Logger(subsystem: EmberIdentity.helperLabel, category: "helper")

final class HelperService: NSObject, EmberHelperProtocol {
    private let queue: DispatchQueue
    private let smcProvider: () throws -> SMCConnection
    private let sleepControl: SleepControl

    init(queue: DispatchQueue, sleepControl: SleepControl, smcProvider: @escaping () throws -> SMCConnection) {
        self.queue = queue
        self.sleepControl = sleepControl
        self.smcProvider = smcProvider
    }

    func setLight(_ value: UInt8, withReply reply: @escaping (Int32, String?) -> Void) {
        guard SMCKey.allowedLEDValues.contains(value) else {
            log.error("refused value \(value, privacy: .public)")
            reply(1, "value \(value) isn't an allowed MagSafe light state")
            return
        }
        queue.async { [smcProvider] in
            do {
                try smcProvider().write(SMCKey.magSafeLED, [value])
                reply(0, nil)
            } catch {
                log.error("write failed: \(String(describing: error), privacy: .public)")
                reply(2, String(describing: error))
            }
        }
    }

    func setSleepDisabled(_ disabled: Bool, withReply reply: @escaping (Int32, String?) -> Void) {
        queue.async { [sleepControl] in
            do {
                try sleepControl.set(disabled: disabled)
                reply(0, nil)
            } catch {
                log.error("sleep switch failed: \(String(describing: error), privacy: .public)")
                reply(3, String(describing: error))
            }
        }
    }

    func helperVersion(withReply reply: @escaping (String) -> Void) {
        reply(EmberIdentity.helperVersion)
    }

    func quit(withReply reply: @escaping () -> Void) {
        log.info("asked to quit (app update); launchd will start the new binary on demand")
        queue.async { [sleepControl] in
            // Never exit with sleep switched off. The app turns it off again if it still wants to.
            try? sleepControl.restore(reason: "helper restarting")
            reply()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let queue: DispatchQueue
    private let sleepControl: SleepControl
    private var cachedSMC: SMCConnection?
    private var activeConnections = 0
    private let stateLock = NSLock()

    override init() {
        let queue = DispatchQueue(label: "ember.helper.smc")
        self.queue = queue
        self.sleepControl = SleepControl(queue: queue)
        super.init()
    }

    private func smc() throws -> SMCConnection {
        if let cachedSMC { return cachedSMC }
        let connection = try SMCConnection()
        cachedSMC = connection
        return connection
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: EmberHelperProtocol.self)
        connection.exportedObject = HelperService(queue: queue, sleepControl: sleepControl, smcProvider: { [unowned self] in try self.smc() })
        connection.invalidationHandler = { [weak self] in self?.connectionEnded() }
        stateLock.lock(); activeConnections += 1; stateLock.unlock()
        connection.resume()
        log.info("app connected")
        return true
    }

    /// If Ember.app goes away without saying goodbye (crash, force quit), hand the light back
    /// to macOS so it never stays stuck off, and let the Mac sleep again.
    private func connectionEnded() {
        stateLock.lock(); activeConnections -= 1; let remaining = activeConnections; stateLock.unlock()
        log.info("app disconnected, \(remaining, privacy: .public) left")
        guard remaining <= 0 else { return }
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.stateLock.lock(); let stillNone = self.activeConnections <= 0; self.stateLock.unlock()
            guard stillNone else { return }
            do {
                try self.smc().write(SMCKey.magSafeLED, [LEDValue.system])
                log.info("no app connected; light handed back to macOS")
            } catch {
                log.error("reset failed: \(String(describing: error), privacy: .public)")
            }
            do {
                try self.sleepControl.restore(reason: "no app connected")
            } catch {
                log.error("couldn't turn sleep back on: \(String(describing: error), privacy: .public)")
            }
            self.scheduleIdleExit()
        }
    }

    /// Turns sleep back on if a previous run switched it off and then crashed or was killed.
    func restoreLeftoverSleep() {
        queue.sync {
            do {
                try sleepControl.restore(reason: "left over from a previous run")
            } catch {
                log.error("couldn't turn sleep back on: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Don't sit around as root with nobody to serve. launchd relaunches on the next connection.
    private func scheduleIdleExit() {
        queue.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self else { return }
            self.stateLock.lock(); let idle = self.activeConnections <= 0; self.stateLock.unlock()
            if idle {
                log.info("idle for 60 s with no app connected; exiting")
                exit(0)
            }
        }
    }
}

enum LEDValue {
    static let system: UInt8 = 0x00
}

guard getuid() == 0 else {
    log.error("EmberHelper must run as root via launchd; exiting")
    exit(1)
}
guard let requirement = EmberIdentity.requirement(forIdentifier: EmberIdentity.appBundleID) else {
    // Without a team ID the only check left is the bundle identifier, which anyone can copy.
    log.error("EmberHelper isn't signed with a team ID; refusing to start")
    exit(1)
}
let delegate = HelperDelegate()
delegate.restoreLeftoverSleep()
let listener = NSXPCListener(machServiceName: EmberIdentity.machServiceName)
listener.setConnectionCodeSigningRequirement(requirement)
log.info("listening on \(EmberIdentity.machServiceName, privacy: .public), requirement: \(requirement, privacy: .public)")
listener.delegate = delegate
listener.resume()
dispatchMain()
