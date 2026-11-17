import AppIntents
import EmberKit

// MARK: Focus filter

/// What the light does while a Focus is on. Shown in System Settings > Focus > (a Focus) > Focus Filters.
enum FocusLightOption: String, AppEnum {
    case off
    case normal
    case green
    case amber

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "MagSafe Light"
    static var caseDisplayRepresentations: [FocusLightOption: DisplayRepresentation] = [
        .off: "Off",
        .normal: "Normal (amber, then green)",
        .green: "Green",
        .amber: "Amber",
    ]

    var choice: FocusLightChoice {
        switch self {
        case .off: return .off
        case .normal: return .normal
        case .green: return .green
        case .amber: return .amber
        }
    }
}

/// Ember's Focus filter. macOS runs it with the person's choice when the Focus turns on, and
/// with the default (no choice) when it turns off, which hands control back to Ember.
struct EmberFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set MagSafe Light"
    static var description: IntentDescription? = IntentDescription(
        "Choose what your MagSafe charging light does while this Focus is on."
    )

    @Parameter(title: "MagSafe light")
    var light: FocusLightOption?

    var displayRepresentation: DisplayRepresentation {
        switch light {
        case .none: return DisplayRepresentation(title: "MagSafe light: leave it to Ember")
        case .off: return DisplayRepresentation(title: "MagSafe light: off")
        case .normal: return DisplayRepresentation(title: "MagSafe light: normal")
        case .green: return DisplayRepresentation(title: "MagSafe light: green")
        case .amber: return DisplayRepresentation(title: "MagSafe light: amber")
        }
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [EmberFocusFilter] {
        let filter = EmberFocusFilter()
        filter.light = .off
        return [filter]
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.applyFocus(light?.choice ?? .followEmber)
        return .result()
    }
}

// MARK: Shortcuts actions

enum LightModeOption: String, AppEnum {
    case auto
    case alwaysOff
    case alwaysOn

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ember Mode"
    static var caseDisplayRepresentations: [LightModeOption: DisplayRepresentation] = [
        .auto: "Auto (follow Focus)",
        .alwaysOff: "Always off",
        .alwaysOn: "Always on",
    ]

    var mode: LightMode {
        switch self {
        case .auto: return .auto
        case .alwaysOff: return .alwaysOff
        case .alwaysOn: return .alwaysOn
        }
    }
}

struct SetEmberModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set MagSafe Light Mode"
    static var description: IntentDescription? = IntentDescription("Switch Ember between Auto, Always off and Always on.")

    @Parameter(title: "Mode")
    var mode: LightModeOption

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.shared.start()
        AppModel.shared.setMode(mode.mode)
        return .result(dialog: "Ember is now \(mode.mode.title.lowercased()).")
    }
}

/// The choices in the "Set MagSafe Light" action. The hardware only has green and amber.
enum MagSafeLightOption: String, AppEnum {
    case green
    case amber
    case off
    case normal

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "MagSafe Light"
    static var caseDisplayRepresentations: [MagSafeLightOption: DisplayRepresentation] = [
        .green: "Green",
        .amber: "Amber",
        .off: "Off",
        .normal: DisplayRepresentation(title: "Normal", subtitle: "Hand the light back to Ember and macOS"),
    ]

    var light: ShortcutLight {
        switch self {
        case .green: return .green
        case .amber: return .amber
        case .off: return .off
        case .normal: return .normal
        }
    }
}

/// Holds the light at a colour until something newer says otherwise: this action again, a mode
/// change, a snooze, or a Focus with Ember's filter starting or ending. Uses the same policy and
/// re-apply loop as the Focus filter, so macOS can't quietly reset it after sleep or plug-in.
struct SetMagSafeLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Set MagSafe Light"
    static var description: IntentDescription? = IntentDescription(
        "Make the MagSafe light green, amber or off until you change it, or hand it back with Normal."
    )

    @Parameter(title: "Light", default: .green)
    var light: MagSafeLightOption

    static var parameterSummary: some ParameterSummary {
        Summary("Set MagSafe light to \(\.$light)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.shared.start()
        let decision = AppModel.shared.setShortcutLight(light.light)
        if case .lowBattery(_, let threshold) = decision.reason, light != .normal {
            return .result(dialog: "Battery's low, so I'll show it charging until it's past \(threshold)%. Then \(light.spoken).")
        }
        switch light {
        case .green: return .result(dialog: "MagSafe light green.")
        case .amber: return .result(dialog: "MagSafe light amber.")
        case .off: return .result(dialog: "MagSafe light off.")
        case .normal: return .result(dialog: "MagSafe light back to normal.")
        }
    }
}

private extension MagSafeLightOption {
    var spoken: String {
        switch self {
        case .green: return "green"
        case .amber: return "amber"
        case .off: return "off"
        case .normal: return "normal"
        }
    }
}

struct SnoozeLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Off MagSafe Light For a While"
    static var description: IntentDescription? = IntentDescription("Turn the MagSafe light off for a number of minutes.")

    @Parameter(title: "Minutes", default: 60)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.shared.start()
        AppModel.shared.snooze(minutes: min(max(minutes, 1), 1440))
        return .result(dialog: "Light off for \(minutes) minutes. Ember's having a nap.")
    }
}

struct WaveIntent: AppIntent {
    static var title: LocalizedStringResource = "Wave the MagSafe Light"
    static var description: IntentDescription? = IntentDescription("Blink the MagSafe light so you can find the cable.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.wave()
        return .result()
    }
}

struct EmberShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetMagSafeLightIntent(),
            // Lead with Ember and avoid the word "light": Siri sends "make the light amber" to
            // HomeKit lights before it considers an app's phrases.
            phrases: [
                "Set \(.applicationName) to \(\.$light)",
                "Make \(.applicationName) \(\.$light)",
                "Turn \(.applicationName) \(\.$light)",
                "Set the MagSafe light with \(.applicationName)",
            ],
            shortTitle: "Set MagSafe Light",
            systemImageName: "light.beacon.max"
        )
        AppShortcut(
            intent: SetEmberModeIntent(),
            phrases: ["Set \(.applicationName) mode", "Change the MagSafe light in \(.applicationName)"],
            shortTitle: "Set Light Mode",
            systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: SnoozeLightIntent(),
            phrases: ["Snooze \(.applicationName)", "Turn off the MagSafe light with \(.applicationName)"],
            shortTitle: "Light Off For a While",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: WaveIntent(),
            phrases: ["Wave with \(.applicationName)", "Find my charger with \(.applicationName)"],
            shortTitle: "Wave",
            systemImageName: "hand.wave"
        )
    }
}
