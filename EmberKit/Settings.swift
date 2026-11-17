import Foundation

/// Ember's saved preferences. Stored as JSON in UserDefaults.
public struct EmberSettings: Codable, Equatable, Sendable {
    public var mode: LightMode
    public var snooze: Snooze?
    /// A colour set by the "Set MagSafe Light" Shortcuts action. Held until the action runs
    /// again, the mode changes, a snooze starts or a Focus filter changes its choice.
    public var heldLight: LightTarget?
    public var schedule: LightsOutSchedule
    public var lowBatteryGuardEnabled: Bool
    public var lowBatteryThreshold: Int
    public var hasFinishedWelcome: Bool
    /// True once a Focus filter has reached Ember, or the person says they've set one up.
    public var focusSetupDone: Bool

    public init(
        mode: LightMode = .auto,
        snooze: Snooze? = nil,
        heldLight: LightTarget? = nil,
        schedule: LightsOutSchedule = LightsOutSchedule(),
        lowBatteryGuardEnabled: Bool = true,
        lowBatteryThreshold: Int = 20,
        hasFinishedWelcome: Bool = false,
        focusSetupDone: Bool = false
    ) {
        self.mode = mode
        self.snooze = snooze
        self.heldLight = heldLight
        self.schedule = schedule
        self.lowBatteryGuardEnabled = lowBatteryGuardEnabled
        self.lowBatteryThreshold = lowBatteryThreshold
        self.hasFinishedWelcome = hasFinishedWelcome
        self.focusSetupDone = focusSetupDone
    }

    // Decode field by field so adding a setting later never wipes the saved ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EmberSettings()
        mode = (try? c.decode(LightMode.self, forKey: .mode)) ?? d.mode
        snooze = try? c.decodeIfPresent(Snooze.self, forKey: .snooze)
        heldLight = try? c.decodeIfPresent(LightTarget.self, forKey: .heldLight)
        schedule = (try? c.decode(LightsOutSchedule.self, forKey: .schedule)) ?? d.schedule
        lowBatteryGuardEnabled = (try? c.decode(Bool.self, forKey: .lowBatteryGuardEnabled)) ?? d.lowBatteryGuardEnabled
        lowBatteryThreshold = (try? c.decode(Int.self, forKey: .lowBatteryThreshold)) ?? d.lowBatteryThreshold
        hasFinishedWelcome = (try? c.decode(Bool.self, forKey: .hasFinishedWelcome)) ?? d.hasFinishedWelcome
        focusSetupDone = (try? c.decode(Bool.self, forKey: .focusSetupDone)) ?? d.focusSetupDone
    }

    // MARK: Instructions. The newest one wins, so each clears the ones it replaces.

    /// The "Set MagSafe Light" action: hold a colour (and end any snooze), or let go with `.normal`.
    public mutating func setShortcutLight(_ light: ShortcutLight) {
        heldLight = light.heldTarget
        if heldLight != nil { snooze = nil }
    }

    /// A mode picked in the menu or by the "Set MagSafe Light Mode" action.
    public mutating func setMode(_ newMode: LightMode) {
        mode = newMode
        heldLight = nil
    }

    /// A snooze from the menu or the "Turn Off MagSafe Light For a While" action.
    public mutating func startSnooze(_ newSnooze: Snooze) {
        snooze = newSnooze
        heldLight = nil
    }

    /// A Focus filter changed its choice: a Focus with Ember's filter started or ended.
    public mutating func focusChanged() {
        heldLight = nil
    }

    public func policyInputs(
        now: Date,
        focus: FocusLightChoice,
        battery: BatterySnapshot?,
        calendar: Calendar = .current
    ) -> PolicyInputs {
        PolicyInputs(
            now: now,
            mode: mode,
            focus: focus,
            snooze: snooze,
            heldLight: heldLight,
            schedule: schedule,
            lowBatteryThreshold: lowBatteryGuardEnabled ? lowBatteryThreshold : nil,
            battery: battery,
            calendar: calendar
        )
    }
}

/// Reads and writes settings and the current Focus choice.
public struct SettingsStore {
    public static let settingsKey = "ember.settings.v1"
    public static let focusKey = "ember.focus.v1"

    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSettings() -> EmberSettings {
        guard let data = defaults.data(forKey: Self.settingsKey),
              let settings = try? JSONDecoder().decode(EmberSettings.self, from: data) else {
            return EmberSettings()
        }
        return settings
    }

    public func save(_ settings: EmberSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }

    public func loadFocus() -> FocusLightChoice {
        defaults.string(forKey: Self.focusKey).flatMap(FocusLightChoice.init(rawValue:)) ?? .followEmber
    }

    public func saveFocus(_ choice: FocusLightChoice) {
        defaults.set(choice.rawValue, forKey: Self.focusKey)
    }
}

/// The sequence the "Wave" button plays on the real light, so you can find the cable.
public enum WavePattern {
    public static let steps: [LightTarget] = [.green, .off, .amber, .off, .green, .off, .amber]
    public static let stepInterval: TimeInterval = 0.3
}
