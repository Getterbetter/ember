import EmberKit
import Foundation
import Testing

@Suite("Personality")
struct PersonalityTests {
    let reasons: [DecisionReason] = [
        .lowBattery(percent: 12, threshold: 20), .alwaysOff, .alwaysOn,
        .snoozed(until: Date(timeIntervalSince1970: 0)),
        .focus(.off), .focus(.normal), .focus(.green), .focus(.amber),
        .schedule(until: Date(timeIntervalSince1970: 0)), .normal,
    ]

    @Test func everyStateHasALine() {
        for reason in reasons {
            for seed in 0..<6 {
                let line = Personality.line(for: Decision(target: .off, reason: reason), seed: seed, formatTime: { _ in "7:00 am" })
                #expect(!line.isEmpty)
                #expect(!line.contains("\n"))
            }
        }
    }

    @Test func linesVaryWithSeed() {
        let d = Decision(target: .system, reason: .normal)
        let lines = Set((0..<4).map { Personality.line(for: d, seed: $0) })
        #expect(lines.count > 1)
    }

    @Test func negativeSeedsDontCrash() {
        #expect(!Personality.line(for: Decision(target: .off, reason: .alwaysOff), seed: -7).isEmpty)
    }

    @Test func snoozeLineIncludesTheTime() {
        let line = Personality.line(
            for: Decision(target: .off, reason: .snoozed(until: Date())),
            seed: 0, formatTime: { _ in "7:00 am" }
        )
        #expect(line.contains("7:00 am"))
    }

    @Test func problemsOverrideTheLineAndMood() {
        let d = Decision(target: .off, reason: .alwaysOff)
        #expect(Personality.mood(for: d, problem: .helperNeedsApproval) == .dazed)
        #expect(Personality.line(for: d, problem: .helperNeedsApproval).contains("Login Items"))
    }

    @Test func moods() {
        #expect(Personality.mood(for: Decision(target: .off, reason: .alwaysOff)) == .asleep)
        #expect(Personality.mood(for: Decision(target: .system, reason: .normal)) == .awake)
        #expect(Personality.mood(for: Decision(target: .system, reason: .lowBattery(percent: 5, threshold: 20))) == .alert)
    }

    @Test func statusChip() {
        #expect(Personality.status(for: Decision(target: .off, reason: .focus(.off))) == "Light off · Focus")
    }
}

@Suite("Settings")
struct SettingsTests {
    @Test func roundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "ember.tests.\(UUID().uuidString)"))
        let store = SettingsStore(defaults: defaults)
        #expect(store.loadSettings() == EmberSettings())
        var s = EmberSettings()
        s.mode = .alwaysOff
        s.schedule.isEnabled = true
        s.lowBatteryThreshold = 30
        store.save(s)
        #expect(store.loadSettings() == s)
    }

    @Test func missingFieldsFallBackToDefaults() throws {
        let json = #"{"mode":"alwaysOn"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(EmberSettings.self, from: json)
        #expect(s.mode == .alwaysOn)
        #expect(s.lowBatteryGuardEnabled)
        #expect(s.lowBatteryThreshold == 20)
        #expect(!s.focusSetupDone)
        #expect(!s.hasFinishedWelcome)
    }

    @Test func focusChoicePersists() throws {
        let defaults = try #require(UserDefaults(suiteName: "ember.tests.\(UUID().uuidString)"))
        let store = SettingsStore(defaults: defaults)
        #expect(store.loadFocus() == .followEmber)
        store.saveFocus(.off)
        #expect(store.loadFocus() == .off)
    }

    @Test func guardDisabledMeansNoThreshold() {
        var s = EmberSettings()
        s.lowBatteryGuardEnabled = false
        #expect(s.policyInputs(now: Date(), focus: .followEmber, battery: nil).lowBatteryThreshold == nil)
    }
}

@Suite("SMC packing")
struct SMCPackingTests {
    @Test func fourCC() {
        #expect(SMCKey.fourCC("ACLC") == 0x41434C43)
        #expect(SMCKey.fourCC("TOOLONG") == nil)
        #expect(SMCKey.string(fromFourCC: 0x41434C43) == "ACLC")
    }

    @Test func paramLayoutIsEightyBytesWithCOffsets() {
        var p = SMCParam()
        p.key = 0x41434C43
        p.dataSize = 1
        p.command = SMCParam.Command.writeKey.rawValue
        p.bytes = [0x01]
        #expect(p.raw.count == 80)
        #expect(p.raw[42] == 6)
        #expect(p.raw[48] == 1)
        #expect(p.raw[28] == 1)
        #expect(p.key == 0x41434C43)
        #expect(p.bytes.count == 32)
    }

    @Test func helperOnlyAllowsLightValues() {
        #expect(SMCKey.allowedLEDValues.contains(0))
        #expect(SMCKey.allowedLEDValues.contains(1))
        #expect(!SMCKey.allowedLEDValues.contains(0x19))
        #expect(!SMCKey.allowedLEDValues.contains(0xFF))
    }
}

@Suite("Versions")
struct VersionTests {
    @Test func parses() {
        #expect(SemanticVersion("v1.2.3")?.parts == [1, 2, 3])
        #expect(SemanticVersion("1.0.0-beta.1")?.parts == [1, 0, 0])
        #expect(SemanticVersion("nope") == nil)
        #expect(SemanticVersion("") == nil)
    }

    @Test func compares() {
        #expect(SemanticVersion("1.0.0")! < SemanticVersion("1.0.1")!)
        #expect(SemanticVersion("1.9")! < SemanticVersion("1.10")!)
        #expect(SemanticVersion("1.0")! == SemanticVersion("1.0.0")!)
        #expect(!(SemanticVersion("2.0.0")! < SemanticVersion("1.9.9")!))
    }
}
