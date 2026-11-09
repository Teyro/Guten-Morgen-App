import XCTest
@testable import MorgenKern

final class MorgenKernTests: XCTestCase {
    let k = Zeit.kalender
    func tag(_ j: Int, _ m: Int, _ t: Int, _ h: Int = 12, _ min: Int = 0) -> Date { k.date(from: DateComponents(year: j, month: m, day: t, hour: h, minute: min))! }

    func testWeckzeit() {
        let e = MorgenEinstellungen()
        // Montag, 9.11.2026: Standard 6:15
        XCTAssertEqual(Weckzeit.berechne(tag: tag(2026, 11, 9), termine: [], frei: nil, e: e).minuten, 375)
        // Termin um 7:00 → 75 min vorher = 5:45
        let t = Termin(titel: "Konferenz", start: tag(2026, 11, 9, 7, 0), ganztags: false)
        let w = Weckzeit.berechne(tag: tag(2026, 11, 9), termine: [t], frei: nil, e: e)
        XCTAssertEqual(w.minuten, 345)
        XCTAssertTrue(w.grund.contains("Konferenz"))
        // nie vor „frühestens“ 5:00
        let sehrFrueh = Termin(titel: "Flug", start: tag(2026, 11, 9, 5, 30), ganztags: false)
        XCTAssertEqual(Weckzeit.berechne(tag: tag(2026, 11, 9), termine: [sehrFrueh], frei: nil, e: e).minuten, 300)
        // Samstag kein Wecker, Ferien kein Wecker
        XCTAssertNil(Weckzeit.berechne(tag: tag(2026, 11, 7), termine: [], frei: nil, e: e).minuten)
        let ferien = FreierTag(von: "2026-10-19", bis: "2026-10-30", name: "Herbstferien", ferien: true)
        XCTAssertEqual(Weckzeit.berechne(tag: tag(2026, 10, 20), termine: [], frei: ferien, e: e).grund, "Herbstferien")
        XCTAssertEqual(FreieTage.am([ferien], tag(2026, 10, 30))?.name, "Herbstferien")
        XCTAssertNil(FreieTage.am([ferien], tag(2026, 10, 31)))
    }

    func testFreieTageLesen() {
        let ferien: [[String: Any]] = [["startDate": "2026-10-19", "endDate": "2026-10-30", "name": [["language": "DE", "text": "Herbstferien"]]]]
        let feiertage: [[String: Any]] = [
            ["startDate": "2026-10-31", "endDate": "2026-10-31", "nationwide": false, "subdivisions": [["code": "DE-HH"]], "name": [["language": "DE", "text": "Reformationstag"]]],
            ["startDate": "2026-11-01", "endDate": "2026-11-01", "nationwide": false, "subdivisions": [["code": "DE-BY"]], "name": [["language": "DE", "text": "Allerheiligen"]]],
        ]
        let t = FreieTage.lesen(ferien: ferien, feiertage: feiertage, bundesland: "HH")
        XCTAssertEqual(t.map(\.name), ["Herbstferien", "Reformationstag"])
    }

    func testWetter() {
        let j: [String: Any] = ["current": ["temperature_2m": 3.6, "weather_code": 3],
                                "daily": ["weather_code": [61, 0], "temperature_2m_max": [7.2, 9], "temperature_2m_min": [0.4, 2], "precipitation_probability_max": [70, 10], "wind_speed_10m_max": [20, 10]]]
        let w = Wetter.lesen(j)
        XCTAssertEqual(w.heute?.code, 61)
        let s = w.satz()
        XCTAssertTrue(s.contains("4 Grad") && s.contains("bedeckt") && s.contains("Regen wahrscheinlich") && s.contains("glatt"), s)
        XCTAssertTrue(w.satz(morgen: true).hasPrefix("Morgen 2 bis 9 Grad"))
    }

    func testVertretungParser() {
        // Tabelle wie der echte Plan: Kopf „Klasse | 1a | 1b“, Stundenzeilen mit halben Zellen, Pausen-Tabelle
        func tc(_ t: String, _ b: Int) -> String { "<w:tc><w:tcPr><w:tcW w:w=\"\(b)\"/></w:tcPr><w:p><w:r><w:t>\(t)</w:t></w:r></w:p></w:tc>" }
        func tr(_ z: [String]) -> String { "<w:tr>" + z.joined() + "</w:tr>" }
        let xml = "<w:body><w:p><w:r><w:t>Freitag, 06.11.2026</w:t></w:r></w:p><w:tbl>"
            + tr([tc("Es fehlen:", 1000), tc("Kha, Reh, Sta", 2000)])
            + tr([tc("Klasse", 1000), tc("1a", 1000), tc("1b", 1000)])
            + tr([tc("1", 1000), tc("", 500), tc("Sta", 500), tc("", 500), tc("", 500)])
            + tr([tc("3", 1000), tc("", 500), tc("", 500), tc("Mey", 500), tc("Sta", 500)])
            + tr([tc("Wichtig!", 1000), tc("Sta 4. Std Termin", 1000), tc("1. Pause", 500), tc("2. Pause", 500)])
            + tr([tc("", 1000), tc("Haus 4", 1000), tc("Sta", 500), tc("Wal", 500)])
            + "</w:tbl></w:body>"
        let p = Vertretung.auswerten(xml, kuerzel: "Sta")
        XCTAssertEqual(p.datum, "2026-11-06")
        XCTAssertEqual(p.stunden.map { "\($0.stunde):\($0.klasse)" }, ["1:1a", "3:1b"])
        XCTAssertEqual(p.pausen.map { "\($0.pause)@\($0.ort)" }, ["1. Pause@Haus 4"])
        XCTAssertTrue(p.fehlt)
        XCTAssertEqual(p.fehlen, ["Kha", "Reh", "Sta"])
        XCTAssertEqual(p.hinweise, ["Sta 4. Std Termin"])
        XCTAssertEqual(p.satz(), "Vertretung: du bist als fehlend eingetragen, 1. Stunde 1a, 3. Stunde 1b, 1. Pause Aufsicht Haus 4.")
    }

    func testDateiname() {
        let gespeichert = tag(2026, 11, 6, 8)
        XCTAssertEqual(Vertretung.nameDatum("3. Mittwoch 411.docx", gespeichert), "2026-11-04")
        XCTAssertEqual(Vertretung.nameDatum("1. Montag 0211.docx", gespeichert), "2026-11-02")
        XCTAssertEqual(Vertretung.nameDatum("5. Freitag_09.10..docx", gespeichert), "2026-10-09")
        XCTAssertNil(Vertretung.nameDatum("5. Freitag.docx", gespeichert))
        XCTAssertEqual(Vertretung.zielTag(tag(2026, 11, 8)), "2026-11-06") // Sonntag → Freitag
        XCTAssertNotNil(Vertretung.zerlege("https://cloud.example.de/s/AbC123"))
    }

    func testPlanWahl() {
        // 9.11.2026 früh: alle Dateien neu gespeichert, die mit Datum im Namen muss gewinnen
        let z = tag(2026, 11, 9, 7, 37)
        let dateien: [(name: String, zeit: Date)] = [("5. Freitag.docx", z), ("4. Donnerstag.docx", z.addingTimeInterval(-30)), ("3. Mittwoch.docx", z.addingTimeInterval(-60)),
                                                     ("2. Dienstag.docx", z.addingTimeInterval(-90)), ("1. Montag 0911.docx", z.addingTimeInterval(-120)), ("1. Montag.docx", z.addingTimeInterval(-900))]
        XCTAssertEqual(Vertretung.reihenfolge(dateien, ziel: "2026-11-09").first?.name, "1. Montag 0911.docx")
        XCTAssertEqual(Vertretung.reihenfolge(dateien, ziel: "2026-11-09").dropFirst().first?.name, "1. Montag.docx")
        XCTAssertEqual(Vertretung.reihenfolge(dateien, ziel: "2026-11-10").first?.name, "2. Dienstag.docx")
        XCTAssertEqual(Vertretung.reihenfolge(dateien, ziel: Vertretung.zielTag(tag(2026, 11, 8))).first?.name, "5. Freitag.docx")
    }

    func testBriefing() {
        var d = BriefingDaten()
        d.jetzt = tag(2026, 11, 9, 6, 15)
        d.termine = [Termin(titel: "Zahnarzt", start: tag(2026, 11, 9, 15, 30), ganztags: false)]
        d.post = "Heute kommt ein Paket: Thalia (DHL)."
        var p = VertretungsPlan(); p.stunden = [.init(stunde: "2", klasse: "2c")]
        d.vertretung = p
        let s = Briefing.morgen(d)
        XCTAssertTrue(s.hasPrefix("Guten Morgen! Heute ist Montag, 9. November"), s)
        XCTAssertTrue(s.contains("um 15 Uhr 30 Zahnarzt") && s.contains("Thalia") && s.contains("2. Stunde 2c"), s)
        d.wecker = Weckzeit(minuten: 375, grund: "", tag: tag(2026, 11, 10))
        d.erledigt = ["Alle Lichter aus"]
        let n = Briefing.nacht(d)
        XCTAssertTrue(n.contains("Alle Lichter aus – erledigt.") && n.contains("morgen um 6 Uhr 15"), n)
    }

    func testHausUndReserve() {
        func tc(_ t: String, _ b: Int) -> String { "<w:tc><w:tcPr><w:tcW w:w=\"\(b)\"/></w:tcPr><w:p><w:r><w:t>\(t)</w:t></w:r></w:p></w:tc>" }
        func tr(_ z: [String]) -> String { "<w:tr>" + z.joined() + "</w:tr>" }
        let xml = "<w:tbl>" + tr([tc("Klasse", 1000), tc("2a", 1000)]) + tr([tc("2", 1000), tc("Sta", 1000)])
            + tr([tc("", 1000), tc("1.  Pause", 500), tc("2. Pause", 500)]) + tr([tc("Hof", 1000), tc("(Sta)", 500), tc("Wal", 500)])
            + tr([tc("Haus 4", 1000), tc("Mey", 500), tc("Mey", 500)]) + "</w:tbl>"
        let p = Vertretung.auswerten(xml, kuerzel: "Sta")
        XCTAssertEqual(p.belegt, 1) // Pausenzeilen zählen nicht mit
        XCTAssertEqual(p.pausen, [.init(pause: "1. Pause", ort: "Hof", reserve: true)])
        let h = Vertretung.haeuser(text: "Haus 1: 1a, 2a\nHaus 4: 4a 4b")
        XCTAssertEqual(Vertretung.haus("2a", h), "Haus 1")
        XCTAssertEqual(Vertretung.haus("4B", h), "Haus 4")
        XCTAssertEqual(p.satz(haeuser: h), "Vertretung: 2. Stunde 2a in Haus 1, 1. Pause Aufsicht Hof als Reserve.")
        XCTAssertEqual(Vertretung.haeuser(text: Vertretung.text(haeuser: h)), h)
    }

    func testMensa() {
        let html = """
        <thead><tr><th>Datum</th><th>Menü 1 3,90 €</th><th>Menü 2 (veg.) 3,90 €</th></tr></thead>
        <tbody id="menuplan_data">
        <tr data-ri="0"><td class="menu-cell-disabled">Montag 09.11.2026</td>
          <td class="menu-cell"><div class="innerFoodNameContainer">Spaghetti Bolognese <span class="additive-info">(1,3)</span></div></td>
          <td class="menu-cell selected"><div class="innerFoodNameContainer">Gem&uuml;securry</div></td></tr>
        <tr data-ri="1"><td>Dienstag 10.11.2026</td><td class="menu-cell"><div class="dayOffOverlay">Feiertag</div></td><td class="menu-cell"><div class="dayOffOverlay">Feiertag</div></td></tr>
        </tbody>
        """
        let t = Mensa.tageAus(html)
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t[0].datum, "2026-11-09")
        XCTAssertEqual(t[0].gerichte.map(\.text), ["Spaghetti Bolognese", "Gemüsecurry"])
        XCTAssertEqual(t[0].gerichte.map(\.menue), ["Menü 1", "Menü 2 (veg.)"])
        XCTAssertEqual(t[0].haupt?.text, "Gemüsecurry")
        XCTAssertEqual(t[0].satz(), "In der Mensa gibt es für dich Gemüsecurry.")
        XCTAssertEqual(t[1].frei, "Feiertag")
        XCTAssertTrue(t[1].gerichte.isEmpty)
    }

    func testSchulKalender() {
        let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261109\r\nDTEND;VALUE=DATE:20261110\r\nEND:VEVENT\r\n"
            + "BEGIN:VEVENT\r\nDTSTART;TZID=Europe/Berlin:20261111T100000\r\nEND:VEVENT\r\n"
            + "BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261123\r\nDTEND;VALUE=DATE:20261125\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        XCTAssertEqual(SchulKalender.tage(ics), ["2026-11-09", "2026-11-11", "2026-11-23", "2026-11-24"])
        var d = BriefingDaten()
        d.jetzt = tag(2026, 11, 9, 6, 15)
        d.obst = true
        d.mensa = MensaTag(datum: "2026-11-09", gerichte: [Gericht(menue: "Menü 1", text: "Pizza")])
        let s = Briefing.morgen(d)
        XCTAssertTrue(s.contains("Heute kommt Schulobst.") && s.contains("In der Mensa gibt es Pizza."), s)
    }

    func testTagwahlUndKantine() {
        // Montag 15:59 → heute, 16:00 → Dienstag; Freitag 17 Uhr → Montag; Samstag früh → Montag
        XCTAssertEqual(Zeit.iso(Tagwahl.ziel(tag(2026, 11, 9, 15, 59))), "2026-11-09")
        XCTAssertEqual(Zeit.iso(Tagwahl.ziel(tag(2026, 11, 9, 16, 0))), "2026-11-10")
        XCTAssertEqual(Zeit.iso(Tagwahl.ziel(tag(2026, 11, 13, 17))), "2026-11-16")
        XCTAssertEqual(Zeit.iso(Tagwahl.ziel(tag(2026, 11, 14, 8))), "2026-11-16")
        let frei = [FreierTag(von: "2026-11-10", bis: "2026-11-10", name: "Studientag", ferien: false)]
        XCTAssertEqual(Zeit.iso(Tagwahl.ziel(tag(2026, 11, 9, 18), frei: frei)), "2026-11-11")
        XCTAssertEqual(Mensa.guthabenAus("<div id=\"balancePanel\">GUTHABEN (GESAMT) 20,00 € Verfügbar: 1.012,40 € Reservierte Speisen: 7,60 €</div>"), 1012.40)
        let t = MensaTag(datum: "2026-11-09", gerichte: [Gericht(menue: "Menü 1", text: "Schweinebraten", zusatz: "2,3"),
                                                          Gericht(menue: "Menü 2", text: "Nudeln mit Tomatensoße", zusatz: "A")])
        XCTAssertEqual(t.haupt(meiden: "schwein")?.menue, "Menü 2")
        XCTAssertEqual(t.haupt(favoriten: "Braten")?.menue, "Menü 1")
        XCTAssertEqual(t.haupt(meiden: "tomate")?.menue, "Menü 1")
        let json = #"{"kuerzel":"Sta","link":"https://c.example/s/AbC","haeuser":{"Haus 1":["1a"]},"kantine":{"benutzer":"max","passwort":"geheim","favoriten":"Pizza"}}"#
        let b = Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let imp = ImportDaten.aus(url: URL(string: "gutenmorgen://import?d=\(b)")!)
        XCTAssertNotNil(imp)
        var e = MorgenEinstellungen()
        let pw = imp!.anwenden(&e)
        XCTAssertEqual(e.kuerzel, "Sta"); XCTAssertTrue(e.mensa); XCTAssertEqual(e.favoriten, "Pizza"); XCTAssertEqual(pw.mensa, "geheim")
        XCTAssertEqual(pw.iserv, "")
        XCTAssertEqual(e.haeuser["Haus 1"], ["1a"])
    }

    func testTakt() {
        let ohne: (ClosedRange<Double>) -> Double = { _ in 0 }
        XCTAssertEqual(Takt.naechste(nach: tag(2026, 11, 9, 6, 30), zufall: ohne), tag(2026, 11, 9, 7, 0))
        XCTAssertEqual(Takt.naechste(nach: tag(2026, 11, 9, 7, 0), zufall: ohne), tag(2026, 11, 9, 7, 10))
        XCTAssertEqual(Takt.naechste(nach: tag(2026, 11, 9, 7, 45), zufall: ohne), tag(2026, 11, 9, 7, 50))
        XCTAssertEqual(Takt.naechste(nach: tag(2026, 11, 9, 7, 51), zufall: ohne), tag(2026, 11, 9, 8, 51)) // danach stündlich
        XCTAssertEqual(Takt.naechste(nach: tag(2026, 11, 9, 15, 30), zufall: ohne), tag(2026, 11, 9, 16, 0))
        XCTAssertEqual(Takt.naechste(nach: tag(2026, 11, 14, 6, 30), zufall: ohne), tag(2026, 11, 14, 7, 30)) // Samstag: kein Morgentakt
        // Versatz: höchstens ±1 Minute
        let d = Takt.naechste(nach: tag(2026, 11, 9, 6, 30), zufall: { $0.upperBound })
        XCTAssertEqual(d, tag(2026, 11, 9, 7, 1))
        XCTAssertTrue(Takt.morgenFenster(tag(2026, 11, 9, 7, 20)))
        XCTAssertFalse(Takt.morgenFenster(tag(2026, 11, 9, 8, 0)))
        XCTAssertEqual(Zeit.vereinigt([(tag(2026, 11, 9, 0), tag(2026, 11, 9, 2)), (tag(2026, 11, 9, 1), tag(2026, 11, 9, 3))]), 3 * 3600)
    }

    func testTotp() {
        // RFC 6238, Anhang B (SHA-1): Zeit 59 s → 94287082 (letzte 6 Stellen)
        XCTAssertEqual(IServ.totp("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", zeit: Date(timeIntervalSince1970: 59)), "287082")
        XCTAssertEqual(IServ.totp("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", zeit: Date(timeIntervalSince1970: 1111111109)), "081804")
        XCTAssertEqual(IServ.bereinige("https://Schule.de/iserv/app"), "schule.de")
    }

    func testAbwesenheiten() {
        let csv = "Nachname;Vorname;Klasse;Zeitraum;Status\nMuster;Mia;2a;09.11.2026 - 11.11.2026;entschuldigt\nBeispiel;Tom;2b;10.11.2026 (08:00 - 10:00);krank\nAlt;Ali;2a;01.10.2026;krank\n"
        let seite = IServ.Seite(body: csv, url: "https://x/iserv/absence/.csv", status: 200, typ: "text/csv")
        let l = Abwesenheiten.lesen(seite, spalten: [])!
        XCTAssertEqual(l.count, 3)
        XCTAssertEqual(l[0].name, "Mia Muster"); XCTAssertEqual(l[0].von, "2026-11-09"); XCTAssertEqual(l[0].bis, "2026-11-11"); XCTAssertEqual(l[0].art, "entschuldigt")
        XCTAssertEqual(l[1].stunden, "8–10 Uhr"); XCTAssertTrue(l[1].stundenweise)
        let di = tag(2026, 11, 10)
        let heute = Abwesenheiten.amTag(l, ziel: di)
        XCTAssertEqual(heute.map(\.name), ["Mia Muster", "Tom Beispiel"]) // ganztägig zuerst
        XCTAssertEqual(Abwesenheiten.amTag(l, ziel: di, klassen: ["2B"]).map(\.name), ["Tom Beispiel"])
        XCTAssertEqual(Abwesenheiten.zeitText(l[0], ziel: di, jetzt: tag(2026, 11, 10, 7)), "seit Mo · bis Mi")
        XCTAssertEqual(Abwesenheiten.zeitText(l[0], ziel: tag(2026, 11, 11), jetzt: tag(2026, 11, 11, 7)), "seit Mo · ab morgen da")
        XCTAssertEqual(Abwesenheiten.zeitText(l[1], ziel: di), "8–10 Uhr")
        XCTAssertEqual(Abwesenheiten.kurzName("Mia Muster"), "Mia M.")
        // HTML-Tabelle
        let html = "<table><tr><th>Schüler</th><th>Klasse</th><th>Von</th><th>Bis</th><th>Grund</th></tr><tr><td>Muster, Mia</td><td>2a</td><td>09.11.2026</td><td>09.11.2026</td><td>beurlaubt</td></tr></table>"
        let t = Abwesenheiten.lesen(IServ.Seite(body: html, url: "https://x", status: 200, typ: "text/html"), spalten: [])!
        XCTAssertEqual(t.first?.name, "Mia Muster"); XCTAssertEqual(t.first?.art, "beurlaubt")
    }

    func testStoerungenUndAufgaben() {
        let html = "<table><tr><th>Titel</th><th>Raum</th><th>Erstellt von</th><th>Erstellt</th><th>Status</th><th>Bearbeiter</th></tr>"
            + "<tr><td><a href=\"/iserv/defect/7\">Beamer kaputt</a></td><td>A12</td><td>Stark, Anna</td><td>09.11.2026, 08:15</td><td>Neu</td><td>-</td></tr>"
            + "<tr><td>Drucker</td><td>B1</td><td>Kim</td><td>08.11.2026</td><td>Erledigt</td><td>Hausmeister</td></tr></table>"
        let l = Stoerungen.lesen(IServ.Seite(body: html, url: "https://schule.de/iserv/defect", status: 200, typ: "text/html"), spalten: [])!
        XCTAssertEqual(l.count, 2)
        XCTAssertEqual(l[0].autor, "Anna Stark"); XCTAssertEqual(l[0].ort, "A12"); XCTAssertTrue(l[0].unbesetzt); XCTAssertEqual(l[0].url, "https://schule.de/iserv/defect/7")
        XCTAssertTrue(l[1].erledigt)
        XCTAssertEqual(StoerungenStand(meldungen: l).offen.map(\.titel), ["Beamer kaputt"])
        XCTAssertEqual(Stoerungen.zeit("09.11.2026, 08:15"), tag(2026, 11, 9, 8, 15))
        XCTAssertEqual(Aufgaben.kategorie("In Bearbeitung"), 2)
        XCTAssertEqual(Aufgaben.kategorie("Zu erledigen"), 1)
        XCTAssertEqual(Aufgaben.kategorie("Erledigt ✓"), 4)
        XCTAssertEqual(Aufgaben.kategorie("Material"), -1)
        XCTAssertEqual(Aufgaben.farbNorm("#76A5AF"), "76a5af")
        let k: [String: Any] = ["title": "", "blocks": [["block_type": "text", "position": 2, "data": ["text": "<p><b>Arbeitsblatt</b> kopieren</p>"]],
                                                       ["block_type": "link", "position": 1, "data": ["url": "https://example.de", "title": "Material"]]]]
        let inhalt = Aufgaben.inhaltAus(k)
        XCTAssertEqual(inhalt.map(\.typ), ["link", "text"])
        XCTAssertEqual(Aufgaben.textAus(k, inhalt).0, "Arbeitsblatt kopieren")
        XCTAssertEqual(Gericht(menue: "Menü 1", text: "Spaghetti Bolognese").emoji, "🍝")
        XCTAssertEqual(Gericht(menue: "Menü 2", text: "Gemüsecurry (vegan)").merkmale, ["🌱 vegan"])
        let tg = MensaTag(datum: "2026-11-09", gerichte: [Gericht(menue: "Menü 1", text: "Pizza"), Gericht(menue: "Menü 2", text: "Bowl")])
        XCTAssertEqual(tg.haupt(gut: ["bowl"])?.menue, "Menü 2")
        XCTAssertEqual(tg.haupt(schlecht: ["PIZZA"])?.menue, "Menü 2")
    }

    func testEinstellungenAlteDaten() {
        let e = MorgenEinstellungen.aus(json: #"{"vorlauf": 60}"#)
        XCTAssertEqual(e?.vorlauf, 60)
        XCTAssertEqual(e?.weckzeiten[2], "06:15")
    }
}
