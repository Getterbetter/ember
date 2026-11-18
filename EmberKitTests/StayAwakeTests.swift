import EmberKit
import Foundation
import Testing

@Suite("Stay awake on the charger")
struct StayAwakeTests {
    private let plugged = BatterySnapshot(percent: 80, isPluggedIn: true, isCharging: false)
    private let unplugged = BatterySnapshot(percent: 80, isPluggedIn: false, isCharging: false)

    @Test func holdsOnlyWhenSwitchedOnPluggedInAndTheLightIsOff() {
        #expect(StayAwake.shouldHold(enabled: true, target: .off, battery: plugged))
    }

    @Test func neverHoldsWhenTheSwitchIsOff() {
        #expect(!StayAwake.shouldHold(enabled: false, target: .off, battery: plugged))
    }

    @Test func neverHoldsOnBatteryOrWhenTheBatteryIsUnknown() {
        #expect(!StayAwake.shouldHold(enabled: true, target: .off, battery: unplugged))
        #expect(!StayAwake.shouldHold(enabled: true, target: .off, battery: nil))
    }

    @Test func neverHoldsWhenTheLightIsMeantToShow() {
        for target in [LightTarget.system, .green, .amber] {
            #expect(!StayAwake.shouldHold(enabled: true, target: target, battery: plugged))
        }
    }

    @Test func switchIsOffByDefaultAndForOldSettings() throws {
        #expect(!EmberSettings().staysAwakeOnCharger)
        let old = try JSONDecoder().decode(EmberSettings.self, from: #"{"mode":"alwaysOff"}"#.data(using: .utf8)!)
        #expect(!old.staysAwakeOnCharger)
    }

    @Test func switchRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "ember.tests.\(UUID().uuidString)"))
        let store = SettingsStore(defaults: defaults)
        var s = EmberSettings()
        s.staysAwakeOnCharger = true
        store.save(s)
        #expect(store.loadSettings().staysAwakeOnCharger)
    }
}
