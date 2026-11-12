import Foundation
import IOKit

enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case keyNotFound(String)
    case smcResult(UInt8)
    case badKey(String)
    case badSize(expected: Int, got: Int)

    var description: String {
        switch self {
        case .serviceNotFound: return "AppleSMC service not found"
        case .openFailed(let kr): return "couldn't open AppleSMC (\(String(format: "0x%08x", kr)))"
        case .callFailed(let kr) where kr == SMCConnection.notPrivileged:
            return "the SMC refused the write: it needs root (helper not running?)"
        case .callFailed(let kr): return "SMC call failed (\(String(format: "0x%08x", kr)))"
        case .keyNotFound(let key): return "this Mac has no SMC key \(key)"
        case .smcResult(let r): return "SMC returned error \(r)"
        case .badKey(let key): return "bad SMC key \(key)"
        case .badSize(let expected, let got): return "SMC key wants \(expected) bytes, got \(got)"
        }
    }
}

/// A connection to the AppleSMC user client. Reading works for any user; writing needs root.
final class SMCConnection {
    /// kIOReturnNotPrivileged (a function-like macro, so Swift doesn't import it).
    static let notPrivileged = kern_return_t(bitPattern: 0xE00002C1)

    private var connection: io_connect_t = 0

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == kIOReturnSuccess else { throw SMCError.openFailed(kr) }
    }

    deinit {
        IOServiceClose(connection)
    }

    struct KeyInfo {
        let size: UInt32
        let type: UInt32
    }

    func keyInfo(_ key: String) throws -> KeyInfo {
        guard let code = SMCKey.fourCC(key) else { throw SMCError.badKey(key) }
        var input = SMCParam()
        input.key = code
        input.command = SMCParam.Command.keyInfo.rawValue
        let output = try call(input, key: key)
        return KeyInfo(size: output.dataSize, type: output.dataType)
    }

    func read(_ key: String) throws -> [UInt8] {
        let info = try keyInfo(key)
        guard let code = SMCKey.fourCC(key) else { throw SMCError.badKey(key) }
        var input = SMCParam()
        input.key = code
        input.dataSize = info.size
        input.command = SMCParam.Command.readKey.rawValue
        let output = try call(input, key: key)
        return Array(output.bytes.prefix(Int(info.size)))
    }

    func write(_ key: String, _ bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        guard Int(info.size) == bytes.count else {
            throw SMCError.badSize(expected: Int(info.size), got: bytes.count)
        }
        guard let code = SMCKey.fourCC(key) else { throw SMCError.badKey(key) }
        var input = SMCParam()
        input.key = code
        input.dataSize = info.size
        input.dataType = info.type
        input.command = SMCParam.Command.writeKey.rawValue
        input.bytes = bytes
        _ = try call(input, key: key)
    }

    private func call(_ input: SMCParam, key: String) throws -> SMCParam {
        var output = SMCParam()
        var outputSize = SMCParam.size
        let kr = input.raw.withUnsafeBytes { inBuffer in
            output.raw.withUnsafeMutableBytes { outBuffer in
                IOConnectCallStructMethod(
                    connection, 2,
                    inBuffer.baseAddress, SMCParam.size,
                    outBuffer.baseAddress, &outputSize
                )
            }
        }
        guard kr == kIOReturnSuccess else { throw SMCError.callFailed(kr) }
        if output.result == SMCKey.resultKeyNotFound { throw SMCError.keyNotFound(key) }
        guard output.result == 0 else { throw SMCError.smcResult(output.result) }
        return output
    }
}
