import Foundation
import ServiceManagement
import os

/// Registers Ember's root helper with launchd (SMAppService) and talks to it over XPC.
@MainActor
final class HelperClient {
    enum State: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case notFound
        case unknown
    }

    enum ClientError: Error, CustomStringConvertible {
        case noProxy
        case helper(code: Int32, message: String?)
        case timedOut

        var description: String {
            switch self {
            case .noProxy: return "couldn't reach the helper"
            case .helper(_, let message): return message ?? "the helper reported an error"
            case .timedOut: return "the helper didn't answer in time"
            }
        }
    }

    private let log = Logger(subsystem: EmberIdentity.appBundleID, category: "helper-client")
    private let service = SMAppService.daemon(plistName: EmberIdentity.helperPlistName)
    private var connection: NSXPCConnection?

    var state: State {
        switch service.status {
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .enabled: return .enabled
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    /// Registers the daemon. The first time, macOS asks the person to approve it in Login Items.
    func register() throws {
        try service.register()
    }

    func unregister() async throws {
        dropConnection()
        try await service.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setLight(_ value: UInt8) async throws {
        let connection = currentConnection()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(throwing: error)
            }
            guard let helper = proxy as? EmberHelperProtocol else {
                once.resume(throwing: ClientError.noProxy)
                return
            }
            helper.setLight(value) { code, message in
                if code == 0 {
                    once.resume()
                } else {
                    once.resume(throwing: ClientError.helper(code: code, message: message))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                once.resume(throwing: ClientError.timedOut)
            }
        }
    }

    func helperVersion() async -> String? {
        let connection = currentConnection()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = ResumeOnceValue<String?>(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.resume(nil) }
            guard let helper = proxy as? EmberHelperProtocol else { once.resume(nil); return }
            helper.helperVersion { once.resume($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { once.resume(nil) }
        }
    }

    /// Tells a running helper to exit so launchd starts the copy inside the current app bundle.
    func restartHelper() async {
        let connection = currentConnection()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnceValue<Void>(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.resume(()) }
            guard let helper = proxy as? EmberHelperProtocol else { once.resume(()); return }
            helper.quit { once.resume(()) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { once.resume(()) }
        }
        dropConnection()
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: EmberIdentity.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: EmberHelperProtocol.self)
        if let requirement = EmberIdentity.requirement(forIdentifier: EmberIdentity.helperLabel) {
            connection.setCodeSigningRequirement(requirement)
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.log.info("helper connection interrupted") }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func dropConnection() {
        connection?.invalidate()
        connection = nil
    }
}

/// Makes sure a continuation is resumed exactly once, whichever callback fires first.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        take()?.resume()
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Error>? {
        lock.lock(); defer { lock.unlock() }
        let c = continuation
        continuation = nil
        return c
    }
}

final class ResumeOnceValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}
