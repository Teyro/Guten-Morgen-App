import Foundation

/// Wann die Gehaltsabrechnung automatisch abgerufen wird: einmal täglich, Montag–Freitag, zu einer je Tag
/// zufälligen, aber festen Uhrzeit zwischen 11:00 und 15:00. Reine Regel (ohne Netz), damit testbar.
public enum GehaltAbruf {
    /// Minute nach Mitternacht (660 = 11:00 … 900 = 15:00), je Tag fest aus dem Datum abgeleitet.
    public static func zielMinute(_ tag: Date, kalender: Calendar = Zeit.kalender) -> Int {
        let t = kalender.ordinality(of: .day, in: .era, for: tag) ?? 0
        // Deterministischer Streuwert ohne Überlauf (auch auf der 32-Bit-Watch): erst auf 0…240 bringen, dann mit
        // einem Faktor teilerfremd zu 241 (Primzahl) mischen – benachbarte Tage liegen so weit auseinander.
        // (Vorher abs(t &* 48271): konnte Int.min ergeben, und abs(Int.min) bricht ab.)
        let streu = ((t % 241 + 241) % 241 * 97 + 13) % 241   // 0 … 240
        return 11 * 60 + streu                      // 11:00 … 15:00
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
