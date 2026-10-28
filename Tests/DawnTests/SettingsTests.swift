import Foundation
import Testing
@testable import Dawn

/// Your settings live in UserDefaults under "settings" as JSON. An update must never reset them.
@Suite struct SettingsTests {
    @Test func settingsFromBeforeUpdatesKeepEverythingAndCheckDaily() throws {
        let saved = """
        {"enabled": true, "hour": 7, "minute": 15, "weekdays": [2, 3, 4], "model": "haiku",
         "doneSound": false, "menuBar": "usage", "followUps": false}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(saved.utf8))
        #expect(s.enabled && s.hour == 7 && s.minute == 15 && s.weekdays == [2, 3, 4])
        #expect(!s.doneSound && s.menuBar == .usage && !s.followUps)
        #expect(s.checkForUpdates)
        #expect(s.lastUpdateCheck == nil)
    }

    @Test func theUpdateFieldsRoundTrip() throws {
        var s = Settings(enabled: true, hour: 5, minute: 45)
        s.checkForUpdates = false
        s.lastUpdateCheck = Date(timeIntervalSince1970: 1_793_000_000)
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(again == s)
        #expect(!again.checkForUpdates && again.lastUpdateCheck == Date(timeIntervalSince1970: 1_793_000_000))
    }

    @Test func oneBrokenFieldDoesntResetTheRest() throws {
        let saved = """
        {"enabled": true, "hour": "seven", "minute": 15, "weekdays": [2], "menuBar": "sideways", "checkForUpdates": "maybe"}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(saved.utf8))
        #expect(s.enabled && s.minute == 15 && s.weekdays == [2])
        #expect(s.hour == Settings().hour && s.menuBar == Settings().menuBar && s.checkForUpdates)
    }
}
