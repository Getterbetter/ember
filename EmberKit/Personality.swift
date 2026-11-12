import Foundation

/// Ember's face, used by the menu bar icon and the big mascot in the menu.
public enum Mood: String, Sendable, CaseIterable {
    /// Light on, all normal.
    case awake
    /// Light off.
    case asleep
    /// Low battery: wide eyes.
    case alert
    /// Clicked, or just did something.
    case wink
    /// Can't reach the light.
    case dazed
}

public enum ProblemKind: Equatable, Sendable {
    case helperNeedsApproval
    case helperUnavailable
    case unsupportedMac
    case writeFailed
}

/// Ember's voice: short, dry, a little cheeky. Never more than one line.
public enum Personality {
    public static func mood(for decision: Decision, problem: ProblemKind? = nil) -> Mood {
        if problem != nil { return .dazed }
        if case .lowBattery = decision.reason { return .alert }
        return decision.target == .off ? .asleep : .awake
    }

    /// The headline shown under Ember in the menu. `seed` picks among variants so the line
    /// changes when the state changes, not on every redraw.
    public static func line(
        for decision: Decision,
        problem: ProblemKind? = nil,
        seed: Int = 0,
        formatTime: (Date) -> String = Personality.shortTime
    ) -> String {
        if let problem {
            return pick(problemLines(problem), seed)
        }
        switch decision.reason {
        case .lowBattery(let percent, let threshold):
            return pick([
                "\(percent)% and plugged in. I'm staying lit so you know it's charging.",
                "Battery's at \(percent)%. Ignoring the dark until we're past \(threshold)%.",
                "Low battery. Rules are suspended, glowing until \(threshold)%.",
            ], seed)
        case .alwaysOff:
            return pick([
                "Lights out, for good. I'll be in here if you need me.",
                "Off until you say otherwise. Very restful.",
                "Permanently off duty. Don't tell the other lights.",
            ], seed)
        case .alwaysOn:
            return pick([
                "Always on. No nights off, apparently.",
                "On shift, permanently. Amber means charging, green means done.",
                "Glowing no matter what Focus says.",
            ], seed)
        case .snoozed(let until):
            let t = formatTime(until)
            return pick([
                "Napping until \(t).",
                "Quiet until \(t). Wake me if you need me.",
                "Off the clock until \(t).",
            ], seed)
        case .focus(let choice):
            switch choice {
            case .off, .followEmber:
                return pick([
                    "Your Focus asked for lights out. Respect.",
                    "Focus mode. Not a peep from me.",
                    "Shh. Somebody's concentrating.",
                ], seed)
            case .normal:
                return pick([
                    "Your Focus wants me glowing. Happy to.",
                    "This Focus likes the light on. So do I.",
                ], seed)
            case .green:
                return pick(["Your Focus picked green. Calm, collected.", "Green it is. Very zen."], seed)
            case .amber:
                return pick(["Your Focus picked amber. Cosy.", "Amber, by request. Campfire vibes."], seed)
            }
        case .schedule(let until):
            let t = formatTime(until)
            return pick([
                "Bedtime. Back at \(t).",
                "It's late. I'll glow again at \(t).",
                "Lights out till \(t). Sleep well.",
            ], seed)
        case .normal:
            return pick([
                "On duty. Amber means charging, green means done.",
                "Glowing as nature intended.",
                "Light's on. Business as usual.",
                "Standing by, glowing modestly.",
            ], seed)
        }
    }

    /// A short label for the status chip, e.g. "Light off · Focus".
    public static func status(for decision: Decision) -> String {
        let light: String
        switch decision.target {
        case .system: light = "Light normal"
        case .off: light = "Light off"
        case .green: light = "Light green"
        case .amber: light = "Light amber"
        }
        let why: String
        switch decision.reason {
        case .lowBattery: why = "low battery"
        case .alwaysOff: why = "always off"
        case .alwaysOn: why = "always on"
        case .snoozed: why = "snoozed"
        case .focus: why = "Focus"
        case .schedule: why = "schedule"
        case .normal: why = "auto"
        }
        return "\(light) · \(why)"
    }

    /// What Ember says when you click it.
    public static func poke(seed: Int) -> String {
        pick([
            "Hello. Yes, I'm the little light.",
            "Careful, I'm hot. Metaphorically.",
            "I've been charging things since before it was cool.",
            "Wave at me and I'll wave back. With the actual light.",
            "Still here. Still glowing. Mostly.",
            "Ember, at your service.",
        ], seed)
    }

    public static func waveLine(seed: Int) -> String {
        pick(["Over here!", "Down by the cable!", "Here I am. Blink blink."], seed)
    }

    static func problemLines(_ problem: ProblemKind) -> [String] {
        switch problem {
        case .helperNeedsApproval:
            return [
                "I need a hand: approve my helper in Login Items and I'll take it from there.",
                "Can't reach the light yet. One click in Login Items and we're in business.",
            ]
        case .helperUnavailable:
            return [
                "My helper isn't answering. Try turning it off and on again in the menu.",
                "Lost my helper somewhere. Re-install it from the menu.",
            ]
        case .unsupportedMac:
            return [
                "This Mac doesn't have a MagSafe light I can talk to. Awkward.",
            ]
        case .writeFailed:
            return [
                "Tried to change the light and it said no. I'll keep trying.",
                "The light's being stubborn. Retrying shortly.",
            ]
        }
    }

    static func pick(_ lines: [String], _ seed: Int) -> String {
        guard !lines.isEmpty else { return "" }
        let index = ((seed % lines.count) + lines.count) % lines.count
        return lines[index]
    }

    public static func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
