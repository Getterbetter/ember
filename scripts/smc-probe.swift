// Read-only probe: does this Mac expose the MagSafe LED SMC key (ACLC)?
// Run: swift scripts/smc-probe.swift   (no sudo; never writes anything)
import Foundation
import IOKit

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
func fourCCString(_ v: UInt32) -> String {
    String(bytes: [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)], encoding: .ascii) ?? "????"
}

// SMCKeyData_t is 80 bytes. Offsets: key 0, keyInfo.dataSize 28, keyInfo.dataType 32,
// result 40, status 41, data8 42, data32 44, bytes 48..<80.
func call(_ conn: io_connect_t, key: String, data8: UInt8, size: UInt32 = 0) -> (kern_return_t, [UInt8]) {
    var input = [UInt8](repeating: 0, count: 80)
    var output = [UInt8](repeating: 0, count: 80)
    input.withUnsafeMutableBytes { b in
        b.storeBytes(of: fourCC(key), toByteOffset: 0, as: UInt32.self)
        b.storeBytes(of: size, toByteOffset: 28, as: UInt32.self)
        b.storeBytes(of: data8, toByteOffset: 42, as: UInt8.self)
    }
    var outSize = 80
    let kr = input.withUnsafeBytes { i in
        output.withUnsafeMutableBytes { o in
            IOConnectCallStructMethod(conn, 2, i.baseAddress, 80, o.baseAddress, &outSize)
        }
    }
    return (kr, output)
}

let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard service != 0 else { print("FAIL: AppleSMC service not found"); exit(1) }
var conn: io_connect_t = 0
let openKR = IOServiceOpen(service, mach_task_self_, 0, &conn)
guard openKR == kIOReturnSuccess else { print("FAIL: IOServiceOpen \(openKR)"); exit(1) }

let (kr1, info) = call(conn, key: "ACLC", data8: 9)
let result1 = info[40]
let size = info.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 28, as: UInt32.self) }
let type = info.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: UInt32.self) }
print("keyInfo kr=\(kr1) result=\(result1) size=\(size) type=\(fourCCString(type))")
guard kr1 == kIOReturnSuccess, result1 == 0 else {
    print(result1 == 0x84 ? "UNSUPPORTED: ACLC key not found" : "FAIL: keyInfo error"); exit(2)
}
let (kr2, out) = call(conn, key: "ACLC", data8: 5, size: size)
print("read kr=\(kr2) result=\(out[40]) bytes=\(Array(out[48..<(48 + Int(size))]))")
print("OK: ACLC present. Values: 0 system, 1 off, 3 green, 4 amber (from charlie0129/batt)")
IOServiceClose(conn)
