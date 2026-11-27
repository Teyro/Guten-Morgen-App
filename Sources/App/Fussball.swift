import SwiftUI
import PDFKit
import MorgenKern

/// Fußballplatz-Pläne aus der Nextcloud der Schule (Ordner „DammAPP“): alle PDFs, zwischengespeichert,
/// nur bei Änderung neu geladen (ETag). Offline der letzte Stand.
struct FussballAnsicht: View {
    let kern: Kern
    @State private var dateien: [Nextcloud.Datei] = []
    @State private var wahl = UserDefaults.standard.string(forKey: "fussballWahl") ?? ""
    @State private var pdf: PDFDocument?
    @State private var fehler = ""
    @State private var laedt = false

    private static var ordner: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("fussball", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    var body: some View {
        VStack(spacing: 10) {
            if dateien.count > 1 {
                Picker("Plan", selection: $wahl) {
                    ForEach(dateien, id: \.name) { d in Text(Nextcloud.planName(d.name)).tag(d.name) }
                }.pickerStyle(.segmented).padding(.horizontal)
            }
            if let pdf { PDFAnsicht(dokument: pdf) } else if laedt { Spacer(); ProgressView(); Spacer() }
            else { Spacer(); Text(fehler.isEmpty ? "Noch kein Plan." : fehler).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(); Spacer() }
            if !fehler.isEmpty && pdf != nil { Label(fehler, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
        }
        .navigationTitle("Fußballplatz")
        .task { await laden() }
        .refreshable { await laden() }
        .onChange(of: wahl) { _, neu in UserDefaults.standard.set(neu, forKey: "fussballWahl"); Task { await zeigen(neu) } }
    }

    private var zugang: Nextcloud? {
        let e = kern.einstellungen
        return kern.nextcloudBereit ? Nextcloud(server: e.nextcloudServer, benutzer: e.nextcloudBenutzer, passwort: kern.nextcloudPasswort) : nil
    }

    private func laden() async {
        // offline: was zuletzt da war
        let gemerkt = (try? Data(contentsOf: Self.ordner.appendingPathComponent("liste.json"))).flatMap { try? JSONDecoder().decode([Nextcloud.Datei].self, from: $0) } ?? []
        if dateien.isEmpty { dateien = gemerkt }
        guard let n = zugang else { fehler = "Die Nextcloud der Schule ist noch nicht eingerichtet (Einstellungen → Schule)."; await zeigen(wahl); return }
        laedt = pdf == nil
        defer { laedt = false }
        do {
            let neu = try await n.liste(Nextcloud.planOrdner).filter { !$0.ordner && $0.name.lowercased().hasSuffix(".pdf") }.sorted { $0.name < $1.name }
            dateien = neu
            try? JSONEncoder().encode(neu).write(to: Self.ordner.appendingPathComponent("liste.json"))
            fehler = ""
        } catch { fehler = error.localizedDescription }
        if !dateien.contains(where: { $0.name == wahl }) { wahl = dateien.first?.name ?? "" }
        await zeigen(wahl)
    }

    private func zeigen(_ name: String) async {
        guard let d = dateien.first(where: { $0.name == name }) else { pdf = nil; return }
        let datei = Self.ordner.appendingPathComponent(d.name)
        let etagDatei = Self.ordner.appendingPathComponent(d.name + ".etag")
        let alt = (try? String(contentsOf: etagDatei, encoding: .utf8)) ?? ""
        // nur bei Änderung neu laden
        if alt != d.etag || !FileManager.default.fileExists(atPath: datei.path), let n = zugang, let daten = try? await n.laden(Nextcloud.planOrdner + "/" + d.name) {
            try? daten.write(to: datei); try? d.etag.write(to: etagDatei, atomically: true, encoding: .utf8)
        }
        pdf = PDFDocument(url: datei)
    }
}

/// PDFKit in SwiftUI: ganze Breite, zoombar
struct PDFAnsicht: UIViewRepresentable {
    let dokument: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.displayMode = .singlePageContinuous; v.backgroundColor = .clear; return v
    }
    func updateUIView(_ v: PDFView, context: Context) { if v.document !== dokument { v.document = dokument } }
}
