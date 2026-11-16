import SwiftUI
import WebKit
import UIKit
import QuickLook
import PDFKit
import UserNotifications
import MorgenKern

/// Täglicher Abruf (Mo–Fr, zufällig 11–15 Uhr): meldet sich im unsichtbaren WebView an und lädt eine neue Abrechnung,
/// falls das Portal auf der Startseite einen Link darauf zeigt (Bezüge/Entgelt/Abrechnung). Nur Links, die das Portal
/// selbst anbietet – keine automatisierte Dauerabfrage, einmal am Tag.
@MainActor final class GehaltDienst: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    static let shared = GehaltDienst()
    private var web: WKWebView?
    private var ziele: [ObjectIdentifier: URL] = [:]
    private var versuche = 0
    private var dokumentGesucht = false
    private var aufraeumen: DispatchWorkItem?

    /// Wenn fällig und eingerichtet: still abrufen. [jetzt] nur für Tests.
    func pruefen(_ jetzt: Date = Date()) {
        let d = UserDefaults.standard
        guard PersonalZugang.vollstaendig, web == nil else { return }
        guard GehaltAbruf.faellig(jetzt, letzterTag: d.string(forKey: "gehaltAbrufTag") ?? "") else { return }
        d.set(Zeit.iso(jetzt), forKey: "gehaltAbrufTag")   // nur einmal am Tag, auch bei Fehlschlag
        starten()
    }

    private func starten() {
        versuche = 0; dokumentGesucht = false
        let c = WKWebViewConfiguration(); c.websiteDataStore = .default()
        let w = WKWebView(frame: .zero, configuration: c)
        w.navigationDelegate = self
        // unsichtbar in das aktuelle Fenster hängen – sonst führt WKWebView kein JS aus
        if let fenster = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            w.isHidden = true; w.frame = .zero; fenster.addSubview(w)
        }
        web = w
        let abbruch = DispatchWorkItem { [weak self] in self?.beenden() }
        aufraeumen = abbruch
        DispatchQueue.main.asyncAfter(deadline: .now() + 50, execute: abbruch)
        w.load(URLRequest(url: Personaldaten.start))
    }

    private func beenden() {
        aufraeumen?.cancel(); aufraeumen = nil
        web?.removeFromSuperview(); web = nil
    }

    private func melde(_ titel: String, _ text: String) {
        let c = UNMutableNotificationContent(); c.title = titel; c.body = text; c.sound = .default
        c.userInfo = ["link": "gutenmorgen://personal"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "gehalt-\(Int(Date().timeIntervalSince1970))", content: c, trigger: nil))
    }

    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = w.url else { return }
        let host = url.host ?? ""
        if host.contains("idp.serviceportal.hamburg.de"), url.path.contains("ShowLogin") {
            guard versuche < 2 else { beenden(); return }; versuche += 1
            w.evaluateJavaScript(Personaldaten.anmeldeSkript(email: PersonalZugang.email, passwort: PersonalZugang.passwort))
        } else if host.contains("meinepersonaldaten.hamburg.de") {
            if url.path.contains("/private") {
                guard !dokumentGesucht else { return }
                dokumentGesucht = true
                // nach einem Link suchen, den das Portal selbst zeigt
                let suche = "(function(){var r=/bez(ü|ue)g|entgelt|abrechnung|mitteilung|gehalt/i;" +
                    "for(var a of document.querySelectorAll('a,button')){var t=(a.textContent||'')+' '+(a.getAttribute('href')||'');" +
                    "if(r.test(t)){if(a.href)return a.href; a.click(); return 'klick';}}return '';})();"
                w.evaluateJavaScript(suche) { r, _ in
                    if let s = r as? String, s.hasPrefix("http"), let u = URL(string: s) { w.load(URLRequest(url: u)) }
                    else if (r as? String) != "klick" {
                        // nichts gefunden – nach kurzer Wartezeit aufgeben
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in if self?.ziele.isEmpty == true { self?.beenden() } }
                    }
                }
            } else {
                // OTP-Seite wie bei der Anmeldung von Hand erkennen (Feld „token“ im Formular „loginForm“);
                // /l3hrbc/login2fa ist nur der AJAX-Aufruf dahinter, keine eigene Seite
                w.evaluateJavaScript("document.getElementById('token') != null && document.getElementById('loginForm') != null") { r, _ in
                    guard (r as? Bool) == true, self.versuche < 4 else { return }
                    self.versuche += 1
                    w.evaluateJavaScript(Personaldaten.otpSkript(code: IServ.totp(PersonalZugang.geheimnis)))
                }
            }
        }
    }

    func webView(_ w: WKWebView, decidePolicyFor r: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let mime = r.response.mimeType?.lowercased() ?? ""
        let anhang = ((r.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased().contains("attachment")
        decisionHandler(mime == "application/pdf" || anhang ? .download : .allow)
    }
    func webView(_ w: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ w: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func download(_ d: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let ziel = PersonalAblage.ziel(fuer: suggestedFilename)
        ziele[ObjectIdentifier(d)] = ziel
        completionHandler(ziel)
    }
    func downloadDidFinish(_ d: WKDownload) {
        guard let u = ziele.removeValue(forKey: ObjectIdentifier(d)) else { return }
        // Dieselbe Abrechnung wie gestern: Kopie verwerfen, keine Mitteilung
        if PersonalAblage.schonDa(u) { try? FileManager.default.removeItem(at: u); beenden(); return }
        try? (u as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
        melde("Neue Abrechnung", u.deletingPathExtension().lastPathComponent)
        beenden()
    }
    func download(_ d: WKDownload, didFailWithError error: Error, resumeData: Data?) { ziele.removeValue(forKey: ObjectIdentifier(d)); beenden() }
}

/// Erinnerung, dass eine neue Bezügemitteilung im Portal sein sollte – einmal im Monat am gewählten Tag.
enum GehaltErinnerung {
    static let id = "gehalt-erinnerung"
    static func planen(an: Bool, tag: Int) {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: [id])
        guard an else { return }
        var comp = DateComponents(); comp.day = min(max(tag, 1), 28); comp.hour = 16
        let inhalt = UNMutableNotificationContent()
        inhalt.title = "Gehaltsabrechnung"
        inhalt.body = "Die neue Bezügemitteilung sollte jetzt im Portal sein. Zum Öffnen tippen."
        inhalt.sound = .default
        inhalt.userInfo = ["link": "gutenmorgen://personal"]
        c.add(UNNotificationRequest(identifier: id, content: inhalt, trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: true)))
    }
}

/// Ordner der gespeicherten Dokumente (Gehaltsabrechnungen, Bescheinigungen) – nur auf diesem Gerät, geschützt
enum PersonalAblage {
    static var ordner: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Personaldaten", isDirectory: true)
        if !FileManager.default.fileExists(atPath: u.path) {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        }
        return u
    }
    static func dateien() -> [URL] {
        let fm = FileManager.default
        let liste = (try? fm.contentsOfDirectory(at: ordner, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
        func datum(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        return liste.sorted { datum($0) > datum($1) }
    }
    /// Liegt dieselbe Abrechnung schon in der Ablage? Das Portal erzeugt die PDF bei jedem Abruf neu (andere Metadaten,
    /// andere Bytes) – darum zählt bei PDFs der Text, sonst der Dateiinhalt. Sonst käme jeden Tag „Neue Abrechnung“.
    static func schonDa(_ neu: URL) -> Bool {
        guard let daten = try? Data(contentsOf: neu) else { return false }
        let text = neu.pathExtension.lowercased() == "pdf" ? PDFDocument(data: daten)?.string ?? "" : ""
        return dateien().contains { alt in
            guard alt.lastPathComponent != neu.lastPathComponent, alt.pathExtension.lowercased() == neu.pathExtension.lowercased() else { return false }
            if (try? Data(contentsOf: alt)) == daten { return true }
            return !text.isEmpty && PDFDocument(url: alt)?.string == text
        }
    }
    /// Freier Dateiname (vorhandene nicht überschreiben)
    static func ziel(fuer name: String) -> URL {
        let sauber = name.replacingOccurrences(of: "/", with: "-").isEmpty ? "Dokument.pdf" : name.replacingOccurrences(of: "/", with: "-")
        var u = ordner.appendingPathComponent(sauber)
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            let basis = (sauber as NSString).deletingPathExtension, endung = (sauber as NSString).pathExtension
            u = ordner.appendingPathComponent("\(basis) (\(n))" + (endung.isEmpty ? "" : ".\(endung)")); n += 1
        }
        return u
    }
}

/// Zugang zu MeinePersonaldaten – nur im Schlüsselbund
enum PersonalZugang {
    static var email: String { Schluesselbund.lesen("mpd.email") ?? "" }
    static var passwort: String { Schluesselbund.lesen("mpd.passwort") ?? "" }
    static var geheimnis: String { Schluesselbund.lesen("mpd.otp") ?? "" }
    static var vollstaendig: Bool { !email.isEmpty && !passwort.isEmpty && !geheimnis.isEmpty }
    static func speichern(email: String, passwort: String, geheimnis: String) {
        Schluesselbund.speichern(email, "mpd.email"); Schluesselbund.speichern(passwort, "mpd.passwort"); Schluesselbund.speichern(geheimnis, "mpd.otp")
    }
    static func vergessen() { speichern(email: "", passwort: "", geheimnis: "") }
}

/// Bereich „Personaldaten“: Portal mit automatischer Anmeldung und die gespeicherten Dokumente
struct PersonaldatenAnsicht: View {
    @State private var eingerichtet = PersonalZugang.vollstaendig
    @State private var teil = 0
    @State private var dateien: [URL] = PersonalAblage.dateien()
    @State private var vorschau: URL?
    @State private var neuLaden = UUID()
    @State private var meldung = ""

    var body: some View {
        Group {
            if !eingerichtet {
                PersonalEinrichtung { eingerichtet = true }
            } else {
                VStack(spacing: 0) {
                    Picker("", selection: $teil) {
                        Text("Portal").tag(0)
                        Text("Meine Dokumente (\(dateien.count))").tag(1)
                    }
                    .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
                    if !meldung.isEmpty { Text(meldung).font(.footnote).foregroundStyle(.secondary).padding(.bottom, 4) }
                    if teil == 0 {
                        PortalWeb(neuLaden: neuLaden, meldung: $meldung) { _ in
                            dateien = PersonalAblage.dateien()
                        }
                        .ignoresSafeArea(edges: .bottom)
                    } else {
                        dokumente
                    }
                }
            }
        }
        .navigationTitle("Personaldaten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if eingerichtet {
                Menu {
                    Button { neuLaden = UUID(); teil = 0 } label: { Label("Neu anmelden", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) {
                        PersonalZugang.vergessen()
                        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
                        eingerichtet = false
                    } label: { Label("Zugang entfernen", systemImage: "person.crop.circle.badge.xmark") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .quickLookPreview($vorschau, in: dateien)
        .onAppear { dateien = PersonalAblage.dateien() }
    }

    private var dokumente: some View {
        List {
            if dateien.isEmpty {
                Text("Noch keine Dokumente. Öffne im Portal eine Gehaltsabrechnung oder Bescheinigung – sie wird hier automatisch gespeichert.")
                    .foregroundStyle(.secondary)
            }
            ForEach(dateien, id: \.self) { u in
                Button { vorschau = u } label: {
                    HStack(spacing: 12) {
                        Image(systemName: u.pathExtension.lowercased() == "pdf" ? "doc.richtext.fill" : "doc.fill")
                            .font(.title2).foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.deletingPathExtension().lastPathComponent).font(.body.weight(.medium)).lineLimit(2)
                            if let d = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                                Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { idx in
                idx.map { dateien[$0] }.forEach { try? FileManager.default.removeItem(at: $0) }
                dateien = PersonalAblage.dateien()
            }
        }
    }
}

/// Einmalige Einrichtung: E-Mail, Passwort, OTP-Link (einfügen oder QR-Code scannen)
struct PersonalEinrichtung: View {
    let fertig: () -> Void
    @State private var email = PersonalZugang.email
    @State private var passwort = ""
    @State private var otp = ""
    @State private var scannen = false
    @State private var fehler = ""

    var body: some View {
        Form {
            Section {
                Text("Gehaltsabrechnungen und Bescheinigungen aus „MeinePersonaldaten“ (ZPD Hamburg). Die App meldet sich selbst an – auch mit dem OTP-Code. Die Zugangsdaten bleiben nur im Schlüsselbund dieses Geräts.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("HamburgService-Konto") {
                TextField("E-Mail", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Passwort", text: $passwort).textContentType(.password)
            }
            Section {
                TextField("otpauth://totp/… oder Geheimnis", text: $otp, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { scannen = true } label: { Label("QR-Code scannen", systemImage: "qrcode.viewfinder") }
            } header: { Text("OTP (zweiter Faktor)") } footer: {
                Text("Den Link bekommst du beim Einrichten der Zwei-Faktor-Anmeldung im Portal (QR-Code). Danach funktioniert deine Authenticator-App weiter.")
            }
            if !fehler.isEmpty { Text(fehler).foregroundStyle(.red) }
            Button("Speichern und anmelden") {
                guard let g = Personaldaten.geheimnis(otp) else { fehler = "Der OTP-Link ist nicht lesbar."; return }
                guard !email.isEmpty, !passwort.isEmpty else { fehler = "Bitte E-Mail und Passwort eintragen."; return }
                PersonalZugang.speichern(email: email.trimmingCharacters(in: .whitespaces), passwort: passwort, geheimnis: g)
                fertig()
            }
            .bold()
        }
        .sheet(isPresented: $scannen) {
            QRScanner { text in otp = text; scannen = false }
        }
    }
}

/// Das echte Portal im WebView – füllt Anmeldung und OTP selbst aus und speichert geöffnete Dokumente
struct PortalWeb: UIViewRepresentable {
    let neuLaden: UUID
    @Binding var meldung: String
    let gespeichert: (URL) -> Void

    func makeCoordinator() -> Koordinator { Koordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()
        let w = WKWebView(frame: .zero, configuration: c)
        w.navigationDelegate = context.coordinator
        w.uiDelegate = context.coordinator
        w.allowsBackForwardNavigationGestures = true
        context.coordinator.geladen = neuLaden
        w.load(URLRequest(url: Personaldaten.start))
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        context.coordinator.eltern = self
        if context.coordinator.geladen != neuLaden {
            context.coordinator.geladen = neuLaden
            context.coordinator.versuche = 0
            w.load(URLRequest(url: Personaldaten.start))
        }
    }

    final class Koordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var eltern: PortalWeb
        var geladen = UUID()
        /// Schutz vor Endlosschleifen bei falschem Passwort/Code
        var versuche = 0
        private var ziele: [ObjectIdentifier: URL] = [:]

        init(_ e: PortalWeb) { eltern = e }

        private func melde(_ t: String) { DispatchQueue.main.async { self.eltern.meldung = t } }

        func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = w.url else { return }
            let host = url.host ?? ""
            if host.contains("idp.serviceportal.hamburg.de"), url.path.contains("ShowLogin") {
                guard versuche < 2 else { melde("Anmeldung hat nicht geklappt – Zugang prüfen (⋯ → Zugang entfernen)."); return }
                versuche += 1
                melde("Meldet an …")
                w.evaluateJavaScript(Personaldaten.anmeldeSkript(email: PersonalZugang.email, passwort: PersonalZugang.passwort))
            } else if host.contains("meinepersonaldaten.hamburg.de") {
                // Angemeldet (geschützter Bereich): Zähler zurücksetzen, damit eine spätere Wiederanmeldung (Sitzung abgelaufen) wieder klappt
                if url.path.contains("/private") { versuche = 0; melde(""); return }
                // OTP-Seite erkennen (Feld „token“) und den Code der Sekunde eintragen
                w.evaluateJavaScript("document.getElementById('token') != null && document.getElementById('loginForm') != null") { r, _ in
                    guard (r as? Bool) == true else { self.melde(""); return }
                    guard self.versuche < 4 else { self.melde("Der OTP-Code wurde nicht angenommen – OTP-Link prüfen."); return }
                    self.versuche += 1
                    self.melde("Zweiter Faktor …")
                    w.evaluateJavaScript(Personaldaten.otpSkript(code: IServ.totp(PersonalZugang.geheimnis)))
                }
            }
        }

        // Dokumente: PDF und Anhänge werden geladen und gespeichert statt angezeigt
        func webView(_ w: WKWebView, decidePolicyFor r: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let mime = r.response.mimeType?.lowercased() ?? ""
            let anhang = ((r.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased().contains("attachment")
            decisionHandler(mime == "application/pdf" || anhang || !r.canShowMIMEType ? .download : .allow)
        }

        func webView(_ w: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ w: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }

        func download(_ d: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let ziel = PersonalAblage.ziel(fuer: suggestedFilename)
            ziele[ObjectIdentifier(d)] = ziel
            completionHandler(ziel)
        }

        func downloadDidFinish(_ d: WKDownload) {
            guard let u = ziele.removeValue(forKey: ObjectIdentifier(d)) else { return }
            // Gehaltsdaten: vollständige iOS-Verschlüsselung (nur lesbar, wenn das Gerät entsperrt ist)
            try? (u as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
            melde("Gespeichert: \(u.lastPathComponent)")
            DispatchQueue.main.async { self.eltern.gespeichert(u) }
        }

        func download(_ d: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            ziele.removeValue(forKey: ObjectIdentifier(d))
            melde("Herunterladen fehlgeschlagen.")
        }

        // Neue Fenster (target=_blank, window.open) im selben WebView öffnen
        func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if a.targetFrame == nil { w.load(a.request) }
            return nil
        }
    }
}
