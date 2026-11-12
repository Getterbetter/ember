import Foundation

/// Pure helpers for talking to the System Management Controller.
/// Kept free of IOKit so the unit tests can exercise them.
enum SMCKey {
    /// The MagSafe charging-light key. Values come from charlie0129/batt (pkg/smc/magsafe.go).
    static let magSafeLED = "ACLC"

    /// Values Ember is ever allowed to write to `ACLC`. Anything else is refused by the helper.
    static let allowedLEDValues: Set<UInt8> = [0x00, 0x01, 0x03, 0x04, 0x05, 0x06, 0x07]

    /// SMC result code for "no such key".
    static let resultKeyNotFound: UInt8 = 0x84

    /// Turns a four-character key such as "ACLC" into the big-endian integer the SMC expects.
    static func fourCC(_ key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func string(fromFourCC value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xff) }
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

/// The 80-byte `SMCKeyData_t` struct the AppleSMC user client takes, packed by hand so the
/// layout never depends on how Swift lays out a struct.
///
/// Offsets (C layout): key 0, vers 4, pLimitData 12, keyInfo.dataSize 28, keyInfo.dataType 32,
/// keyInfo.dataAttributes 36, result 40, status 41, data8 42, data32 44, bytes 48..<80.
struct SMCParam {
    static let size = 80
    static let bytesOffset = 48
    static let maxBytes = 32

    enum Command: UInt8 {
        case readKey = 5
        case writeKey = 6
        case keyInfo = 9
    }

    var raw = [UInt8](repeating: 0, count: SMCParam.size)

    init() {}

    var key: UInt32 {
        get { load(UInt32.self, at: 0) }
        set { store(newValue, at: 0) }
    }
    var dataSize: UInt32 {
        get { load(UInt32.self, at: 28) }
        set { store(newValue, at: 28) }
    }
    var dataType: UInt32 {
        get { load(UInt32.self, at: 32) }
        set { store(newValue, at: 32) }
    }
    var result: UInt8 {
        get { raw[40] }
        set { raw[40] = newValue }
    }
    var command: UInt8 {
        get { raw[42] }
        set { raw[42] = newValue }
    }
    var bytes: [UInt8] {
        get { Array(raw[SMCParam.bytesOffset..<SMCParam.size]) }
        set {
            precondition(newValue.count <= SMCParam.maxBytes)
            for i in 0..<SMCParam.maxBytes {
                raw[SMCParam.bytesOffset + i] = i < newValue.count ? newValue[i] : 0
            }
        }
    }

    private func load<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }

    private mutating func store<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        raw.withUnsafeMutableBytes { $0.storeBytes(of: value, toByteOffset: offset, as: T.self) }
    }
}
