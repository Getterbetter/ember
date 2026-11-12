import Foundation

/// A nightly lights-out window, in minutes after local midnight. It may wrap past midnight.
public struct LightsOutSchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var startMinutes: Int
    public var endMinutes: Int

    public init(isEnabled: Bool = false, startMinutes: Int = 22 * 60, endMinutes: Int = 7 * 60) {
        self.isEnabled = isEnabled
        self.startMinutes = LightsOutSchedule.clamp(startMinutes)
        self.endMinutes = LightsOutSchedule.clamp(endMinutes)
    }

    public static func clamp(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }

    /// Whether `date` falls inside the window. Ignores `isEnabled` so the UI can preview it.
    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard startMinutes != endMinutes else { return false }
        let m = LightsOutSchedule.minutesIntoDay(date, calendar: calendar)
        if startMinutes < endMinutes {
            return m >= startMinutes && m < endMinutes
        }
        return m >= startMinutes || m < endMinutes
    }

    /// The next time the window ends, strictly after `date`.
    public func nextEnd(after date: Date, calendar: Calendar) -> Date {
        LightsOutSchedule.next(minutes: endMinutes, after: date, calendar: calendar)
    }

    public static func minutesIntoDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The next wall-clock occurrence of `minutes` after midnight, strictly after `date`.
    public static func next(minutes: Int, after date: Date, calendar: Calendar) -> Date {
        let m = clamp(minutes)
        let components = DateComponents(hour: m / 60, minute: m % 60, second: 0)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(24 * 3600)
    }
}

public enum SnoozeMath {
    /// Default wake-up for "Off until morning" when no schedule is set: 07:00.
    public static let defaultMorningMinutes = 7 * 60

    /// When "Off until morning" should end: the schedule's end if the schedule is on, otherwise 07:00.
    /// If it is already past midnight but before that time, that's this morning; otherwise tomorrow's.
    public static func morning(after date: Date, schedule: LightsOutSchedule, calendar: Calendar) -> Date {
        let minutes = schedule.isEnabled ? schedule.endMinutes : defaultMorningMinutes
        return LightsOutSchedule.next(minutes: minutes, after: date, calendar: calendar)
    }
}
