import Foundation

/// Wann die Gehaltsabrechnung automatisch abgerufen wird: einmal täglich, Montag–Freitag, zu einer je Tag
/// zufälligen, aber festen Uhrzeit zwischen 11:00 und 15:00. Reine Regel (ohne Netz), damit testbar.
public enum GehaltAbruf {
    /// Minute nach Mitternacht (660 = 11:00 … 900 = 15:00), je Tag fest aus dem Datum abgeleitet.
    public static func zielMinute(_ tag: Date, kalender: Calendar = Zeit.kalender) -> Int {
        let t = kalender.ordinality(of: .day, in: .era, for: tag) ?? 0
        // einfacher, deterministischer Streuwert
        let streu = (t &* 2654435761) % 241        // 0 … 240
        return 11 * 60 + abs(streu)                // 11:00 … 15:00
    }

    /// Ist jetzt ein Abruf fällig? [letzterTag]: ISO-Datum des letzten Abrufs (leer = noch nie).
    public static func faellig(_ jetzt: Date, letzterTag: String, kalender: Calendar = Zeit.kalender) -> Bool {
        let wt = kalender.component(.weekday, from: jetzt)   // 1 = So … 7 = Sa
        guard wt >= 2 && wt <= 6 else { return false }        // nur Mo–Fr
        guard Zeit.iso(jetzt) != letzterTag else { return false } // heute schon
        let minute = kalender.component(.hour, from: jetzt) * 60 + kalender.component(.minute, from: jetzt)
        return minute >= zielMinute(jetzt, kalender: kalender)
    }
}
