import EmberKit
import Foundation
import Testing

@Suite("Settle checks")
struct SettleChecksTests {
    @Test func checksStartWithinASecondAndRunInOrder() {
        let times = SettleChecks.times
        #expect(times.first == 1)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func checksCoverTheSecondResetButFinishWellBeforeTheRegularCheck() {
        // The second reset lands a few seconds after the first; the regular check is every 30 s.
        let last = SettleChecks.times.last ?? 0
        #expect(last >= 8)
        #expect(last <= 15)
    }

    @Test func gapsAddUpToTheCheckTimes() {
        let gaps = SettleChecks.gaps
        #expect(gaps.count == SettleChecks.times.count)
        #expect(gaps.allSatisfy { $0 > 0 })
        var elapsed: TimeInterval = 0
        for (gap, time) in zip(gaps, SettleChecks.times) {
            elapsed += gap
            #expect(elapsed == time)
        }
    }
}
