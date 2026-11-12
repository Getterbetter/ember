import EmberKit
import Foundation
import Testing

private let melbourne: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Australia/Melbourne")!
    return c
}()

/// A fixed Wednesday in Melbourne at the given time.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 11) -> Date {
    melbourne.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private let pluggedFull = BatterySnapshot(percent: 100, isPluggedIn: true, isCharging: false)

@Suite("Policy")
struct PolicyTests {
    private func decide(
        now: Date = at(14),
        mode: LightMode = .auto,
        focus: FocusLightChoice = .followEmber,
        snooze: Snooze? = nil,
        schedule: LightsOutSchedule = LightsOutSchedule(),
        threshold: Int? = 20,
        battery: BatterySnapshot? = pluggedFull
    ) -> Decision {
        Policy.decide(PolicyInputs(
            now: now, mode: mode, focus: focus, snooze: snooze, schedule: schedule,
            lowBatteryThreshold: threshold, battery: battery, calendar: melbourne
        ))
    }

    @Test func autoWithNothingGoingOnLeavesMacOSInCharge() {
        #expect(decide() == Decision(target: .system, reason: .normal))
    }

    @Test func alwaysOffTurnsTheLightOff() {
        #expect(decide(mode: .alwaysOff) == Decision(target: .off, reason: .alwaysOff))
    }

    @Test func alwaysOnIgnoresFocus() {
        #expect(decide(mode: .alwaysOn, focus: .off) == Decision(target: .system, reason: .alwaysOn))
    }

    @Test func focusFilterOffWinsInAuto() {
        #expect(decide(focus: .off) == Decision(target: .off, reason: .focus(.off)))
    }

    @Test func focusFilterColoursMapToTargets() {
        #expect(decide(focus: .green).target == .green)
        #expect(decide(focus: .amber).target == .amber)
        #expect(decide(focus: .normal).target == .system)
    }

    @Test func activeSnoozeBeatsAlwaysOnAndFocus() {
        let snooze = Snooze(target: .off, until: at(15))
        #expect(decide(mode: .alwaysOn, snooze: snooze) == Decision(target: .off, reason: .snoozed(until: at(15))))
        #expect(decide(focus: .normal, snooze: snooze).target == .off)
    }

    @Test func expiredSnoozeIsIgnored() {
        let snooze = Snooze(target: .off, until: at(13))
        #expect(decide(snooze: snooze) == Decision(target: .system, reason: .normal))
    }

    @Test func lowBatteryGuardBeatsEverythingWhenPluggedIn() {
        let low = BatterySnapshot(percent: 12, isPluggedIn: true, isCharging: true)
        #expect(decide(mode: .alwaysOff, battery: low) == Decision(target: .system, reason: .lowBattery(percent: 12, threshold: 20)))
        #expect(decide(focus: .off, battery: low).target == .system)
    }

    @Test func lowBatteryGuardIgnoredWhenUnpluggedOrDisabled() {
        let lowUnplugged = BatterySnapshot(percent: 12, isPluggedIn: false, isCharging: false)
        #expect(decide(mode: .alwaysOff, battery: lowUnplugged).target == .off)
        let low = BatterySnapshot(percent: 12, isPluggedIn: true, isCharging: true)
        #expect(decide(mode: .alwaysOff, threshold: nil, battery: low).target == .off)
    }

    @Test func lowBatteryGuardStopsAtTheThreshold() {
        let atThreshold = BatterySnapshot(percent: 20, isPluggedIn: true, isCharging: true)
        #expect(decide(mode: .alwaysOff, battery: atThreshold).target == .off)
    }

    @Test func scheduleTurnsLightOffOvernight() {
        let schedule = LightsOutSchedule(isEnabled: true, startMinutes: 22 * 60, endMinutes: 7 * 60)
        #expect(decide(now: at(23, 30), schedule: schedule) == Decision(target: .off, reason: .schedule(until: at(7, day: 12))))
        #expect(decide(now: at(6, 59), schedule: schedule) == Decision(target: .off, reason: .schedule(until: at(7))))
        #expect(decide(now: at(7), schedule: schedule).target == .system)
        #expect(decide(now: at(21, 59), schedule: schedule).target == .system)
    }

    @Test func focusChoiceBeatsSchedule() {
        let schedule = LightsOutSchedule(isEnabled: true)
        #expect(decide(now: at(23), focus: .green, schedule: schedule).target == .green)
    }

    @Test func disabledScheduleDoesNothing() {
        let schedule = LightsOutSchedule(isEnabled: false)
        #expect(decide(now: at(23), schedule: schedule).target == .system)
    }
}

@Suite("Schedule")
struct ScheduleTests {
    @Test func sameDayWindow() {
        let s = LightsOutSchedule(isEnabled: true, startMinutes: 9 * 60, endMinutes: 17 * 60)
        #expect(s.contains(at(9), calendar: melbourne))
        #expect(s.contains(at(16, 59), calendar: melbourne))
        #expect(!s.contains(at(17), calendar: melbourne))
        #expect(!s.contains(at(8, 59), calendar: melbourne))
    }

    @Test func emptyWindowNeverMatches() {
        let s = LightsOutSchedule(isEnabled: true, startMinutes: 600, endMinutes: 600)
        #expect(!s.contains(at(10), calendar: melbourne))
    }

    @Test func clampWrapsMinutes() {
        #expect(LightsOutSchedule.clamp(1440) == 0)
        #expect(LightsOutSchedule.clamp(-60) == 1380)
    }

    @Test func morningIsTomorrowAtSevenInTheEvening() {
        let morning = SnoozeMath.morning(after: at(23, 18), schedule: LightsOutSchedule(), calendar: melbourne)
        #expect(morning == at(7, day: 12))
    }

    @Test func morningIsTodayAfterMidnight() {
        let morning = SnoozeMath.morning(after: at(2), schedule: LightsOutSchedule(), calendar: melbourne)
        #expect(morning == at(7))
    }

    @Test func morningUsesScheduleEndWhenScheduleIsOn() {
        let schedule = LightsOutSchedule(isEnabled: true, startMinutes: 23 * 60, endMinutes: 6 * 60 + 30)
        let morning = SnoozeMath.morning(after: at(22), schedule: schedule, calendar: melbourne)
        #expect(morning == at(6, 30, day: 12))
    }
}

@Suite("Light values")
struct LightTests {
    @Test func smcValuesMatchBatt() {
        #expect(LightTarget.system.smcValue == 0)
        #expect(LightTarget.off.smcValue == 1)
        #expect(LightTarget.green.smcValue == 3)
        #expect(LightTarget.amber.smcValue == 4)
    }

    @Test func readingsMatchTargets() {
        #expect(LightTarget.off.matches(raw: 1))
        #expect(!LightTarget.off.matches(raw: 4))
        #expect(LightTarget.green.matches(raw: 2))
        #expect(LightTarget.green.matches(raw: 3))
        #expect(LightTarget.system.matches(raw: 4))
    }

    @Test func onlyForcedTargetsAreReasserted() {
        #expect(!LightTarget.system.needsReassert)
        #expect(LightTarget.off.needsReassert)
    }

    @Test func focusEndingMeansFollowEmber() {
        #expect(FocusLightChoice.followEmber.target == nil)
    }
}
