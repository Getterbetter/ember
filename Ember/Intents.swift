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
