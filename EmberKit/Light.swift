import Foundation

/// What Ember wants the MagSafe light to do.
public enum LightTarget: String, Codable, CaseIterable, Sendable {
    /// macOS drives the light: amber while charging, green when full.
    case system
    case off
    case green
    case amber

    /// The byte written to the `ACLC` SMC key.
    public var smcValue: UInt8 {
        switch self {
        case .system: return 0x00
        case .off: return 0x01
        case .green: return 0x03
        case .amber: return 0x04
        }
    }

    /// macOS resets a forced light on power events, so forced targets must be re-applied.
    /// `.system` is handed back once and then left alone.
    public var needsReassert: Bool { self != .system }

    /// True when a raw `ACLC` reading already shows this target.
    public func matches(raw: UInt8) -> Bool {
        switch self {
        case .system: return true
        case .off: return raw == 0x01
        case .green: return raw == 0x02 || raw == 0x03
        case .amber: return raw == 0x04
        }
    }
}

/// The permanent setting the person picks in the menu.
public enum LightMode: String, Codable, CaseIterable, Sendable {
    /// Follow Focus filters, snoozes and the schedule.
    case auto
    /// Light off, whatever else is going on (except the low-battery guard).
    case alwaysOff
    /// macOS's normal behaviour, whatever Focus is on.
    case alwaysOn

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .alwaysOff: return "Always off"
        case .alwaysOn: return "Always on"
        }
    }
}

/// What a Focus filter asked for. `.followEmber` is also what macOS sends when a Focus ends.
public enum FocusLightChoice: String, Codable, CaseIterable, Sendable {
    case followEmber
    case off
    case normal
    case green
    case amber

    public var target: LightTarget? {
        switch self {
        case .followEmber: return nil
        case .off: return .off
        case .normal: return .system
        case .green: return .green
        case .amber: return .amber
        }
    }
}

/// A temporary override, e.g. "off for an hour".
public struct Snooze: Codable, Equatable, Sendable {
    public var target: LightTarget
    public var until: Date

    public init(target: LightTarget = .off, until: Date) {
        self.target = target
        self.until = until
    }

    public func isActive(at date: Date) -> Bool { date < until }
}

/// Battery state as read from IOKit power sources.
public struct BatterySnapshot: Equatable, Sendable {
    public var percent: Int
    public var isPluggedIn: Bool
    public var isCharging: Bool

    public init(percent: Int, isPluggedIn: Bool, isCharging: Bool) {
        self.percent = percent
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
    }
}
