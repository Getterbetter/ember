import Foundation

/// Everything the policy needs to pick a light state. All inputs are plain values so it's testable.
public struct PolicyInputs: Sendable {
    public var now: Date
    public var mode: LightMode
    public var focus: FocusLightChoice
    public var snooze: Snooze?
    public var schedule: LightsOutSchedule
    /// Battery percent below which the light always shows. `nil` turns the guard off.
    public var lowBatteryThreshold: Int?
    public var battery: BatterySnapshot?
    public var calendar: Calendar

    public init(
        now: Date,
        mode: LightMode,
        focus: FocusLightChoice = .followEmber,
        snooze: Snooze? = nil,
        schedule: LightsOutSchedule = LightsOutSchedule(),
        lowBatteryThreshold: Int? = 20,
        battery: BatterySnapshot? = nil,
        calendar: Calendar = .current
    ) {
        self.now = now
        self.mode = mode
        self.focus = focus
        self.snooze = snooze
        self.schedule = schedule
        self.lowBatteryThreshold = lowBatteryThreshold
        self.battery = battery
        self.calendar = calendar
    }
}

public enum DecisionReason: Equatable, Sendable {
    case lowBattery(percent: Int, threshold: Int)
    case alwaysOff
    case alwaysOn
    case snoozed(until: Date)
    case focus(FocusLightChoice)
    case schedule(until: Date)
    case normal
}

public struct Decision: Equatable, Sendable {
    public var target: LightTarget
    public var reason: DecisionReason

    public init(target: LightTarget, reason: DecisionReason) {
        self.target = target
        self.reason = reason
    }
}

public enum Policy {
    /// Picks the light state. Precedence, highest first:
    /// 1. Low-battery guard (plugged in and below the threshold): macOS shows the light.
    /// 2. Always off.
    /// 3. An active snooze (it beats Always on, because it's explicit and temporary).
    /// 4. Always on.
    /// 5. Auto: a Focus filter's choice, then the lights-out schedule, then normal.
    public static func decide(_ input: PolicyInputs) -> Decision {
        if let threshold = input.lowBatteryThreshold,
           let battery = input.battery,
           battery.isPluggedIn,
           battery.percent < threshold {
            return Decision(target: .system, reason: .lowBattery(percent: battery.percent, threshold: threshold))
        }

        if input.mode == .alwaysOff {
            return Decision(target: .off, reason: .alwaysOff)
        }

        if let snooze = input.snooze, snooze.isActive(at: input.now) {
            return Decision(target: snooze.target, reason: .snoozed(until: snooze.until))
        }

        if input.mode == .alwaysOn {
            return Decision(target: .system, reason: .alwaysOn)
        }

        if let target = input.focus.target {
            return Decision(target: target, reason: .focus(input.focus))
        }

        if input.schedule.isEnabled, input.schedule.contains(input.now, calendar: input.calendar) {
            let until = input.schedule.nextEnd(after: input.now, calendar: input.calendar)
            return Decision(target: .off, reason: .schedule(until: until))
        }

        return Decision(target: .system, reason: .normal)
    }
}
