import Foundation
import MorgenKern
#if canImport(HealthKit)
import HealthKit
#endif

/// Apple Health: Schlaf der letzten Nacht lesen, den Nachtmodus als Schlaf eintragen.
/// Ohne Berechtigung (oder wenn die Signatur HealthKit nicht erlaubt) passiert einfach nichts.
enum Gesundheit {
    #if canImport(HealthKit)
    private static let speicher = HKHealthStore()
    private static var schlafTyp: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    #endif

    static var verfuegbar: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    static func erlauben() async -> Bool {
        #if canImport(HealthKit)
        guard verfuegbar else { return false }
        do {
            try await speicher.requestAuthorization(toShare: [schlafTyp], read: [schlafTyp])
            return true
        } catch { return false }
        #else
        return false
        #endif
    }

    /// Geschlafene Zeit der letzten Nacht (gestern 18 Uhr bis heute 14 Uhr), überlappende Quellen nur einmal gezählt
    static func schlafLetzteNacht(jetzt: Date = Date()) async -> TimeInterval? {
        #if canImport(HealthKit)
        guard verfuegbar else { return nil }
        let k = Calendar.current
        let heute = k.startOfDay(for: jetzt)
        guard let von = k.date(byAdding: .hour, value: -6, to: heute), let bis = k.date(byAdding: .hour, value: 14, to: heute) else { return nil }
        let schlaf: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let proben: [HKCategorySample] = await withCheckedContinuation { weiter in
            let filter = HKQuery.predicateForSamples(withStart: von, end: bis)
            let q = HKSampleQuery(sampleType: schlafTyp, predicate: filter, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                weiter.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            speicher.execute(q)
        }
        // Nur „geschlafen“; gibt es das nicht (z. B. nur iPhone ohne Uhr), dann „im Bett“
        var teile = proben.filter { schlaf.contains($0.value) }.map { ($0.startDate, $0.endDate) }
        if teile.isEmpty { teile = proben.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }.map { ($0.startDate, $0.endDate) } }
        guard !teile.isEmpty else { return nil }
        return Zeit.vereinigt(teile)
        #else
        return nil
        #endif
    }

    /// Nachtmodus als „im Bett“ eintragen (nur plausible Nächte: 2 bis 14 Stunden)
    static func nachtEintragen(von: Date, bis: Date) async {
        #if canImport(HealthKit)
        let dauer = bis.timeIntervalSince(von)
        guard verfuegbar, dauer > 2 * 3600, dauer < 14 * 3600 else { return }
        let probe = HKCategorySample(type: schlafTyp, value: HKCategoryValueSleepAnalysis.inBed.rawValue, start: von, end: bis)
        try? await speicher.save(probe)
        #endif
    }

    /// „7 Std. 12 Min.“
    static func text(_ dauer: TimeInterval) -> String {
        let m = Int(dauer / 60)
        return m >= 60 ? "\(m / 60) Std. \(m % 60) Min." : "\(m) Min."
    }
}
