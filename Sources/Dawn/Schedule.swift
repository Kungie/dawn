import Foundation

/// When pings are due. Pure functions, so the chain can be checked without waiting a day (`Dawn schedule`).
///
/// The morning ping goes out at the set time on the chosen days. With follow-ups on, the next ping goes out
/// 5 h 1 min after the last one that actually went out (or after the morning time, if the morning ping was
/// skipped or missed), so a new window starts a minute after the last one ends. The chain stops before a
/// ping whose window would still be running at the next morning ping, so the morning ping stays clean.
enum Schedule {
    static let followUpGap: TimeInterval = 5 * 3600 + 60
    static let windowLength: TimeInterval = 5 * 3600

    /// The morning ping time on `day`, if that weekday is chosen.
    static func morning(on day: Date, _ s: Settings, _ cal: Calendar = .current) -> Date? {
        guard s.weekdays.contains(cal.component(.weekday, from: day)) else { return nil }
        return cal.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: day)
    }

    /// The first morning ping strictly after `date`.
    static func nextMorning(after date: Date, _ s: Settings, _ cal: Calendar = .current) -> Date? {
        for offset in 0...8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: date),
                  let m = morning(on: day, s, cal), m > date else { continue }
            return m
        }
        return nil
    }

    /// The morning ping that today's chain hangs off: the latest chosen morning at or before `now`
    /// (today's, or yesterday's for the hours after midnight).
    static func chainBase(at now: Date, _ s: Settings, _ cal: Calendar = .current) -> Date? {
        for offset in [0, -1] {
            guard let day = cal.date(byAdding: .day, value: offset, to: now),
                  let m = morning(on: day, s, cal), m <= now else { continue }
            return m
        }
        return nil
    }

    /// When the next follow-up ping is due (it may already be in the past: then it's due now),
    /// or nil when the chain is over until the next morning.
    static func nextFollowUp(at now: Date, _ s: Settings, pings: [Date], _ cal: Calendar = .current) -> Date? {
        guard s.enabled, s.followUps, let base = chainBase(at: now, s, cal),
              let nextMorning = nextMorning(after: base, s, cal) else { return nil }
        let anchor = pings.filter { $0 >= base && $0 <= now }.max() ?? base
        let next = anchor.addingTimeInterval(followUpGap)
        guard next.addingTimeInterval(windowLength) <= nextMorning else { return nil }
        return next
    }
}
