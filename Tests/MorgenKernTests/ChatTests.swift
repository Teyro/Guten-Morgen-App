import XCTest
@testable import MorgenKern

final class ChatTests: XCTestCase {
    /// IServ-Seite ohne Kommentar-Klassen: an „Name am Datum Uhrzeit“ in einzelne Blasen trennen (auch zwei Kommentare derselben Person)
    func testKommentareGetrennt() {
        let html = """
        <main><h1>Verbindung zum Tablet</h1><p>Das Tablet verbindet sich nicht mit dem Board.</p>
        <h2>Kommentare</h2>
        <div class="panel"><div class="panel-heading">Christian Stake am 18.11.2026 11:03</div><div class="panel-body">Schaue ich mir an.</div></div>
        <div class="panel"><div class="panel-heading">Christian Stake am 18.11.2026 11:05</div><div class="panel-body">Kabel getauscht 🙂<br>Bitte testen.</div></div>
        <div class="panel"><div class="panel-heading">Linda Beutel am 19.11.2026 08:00</div><div class="panel-body">Danke, geht wieder!</div></div>
        </main>
        """
        let e = Stoerungen.verlaufAus(html, von: "https://s5586.schuldock.de/iserv/report/show/50").eintraege
        XCTAssertEqual(e.count, 4)
        XCTAssertTrue(e[0].text.contains("verbindet sich nicht"))
        XCTAssertEqual(e[1].autor, "Christian Stake"); XCTAssertEqual(e[1].zeit, "18.11.2026 11:03"); XCTAssertEqual(e[1].text, "Schaue ich mir an.")
        XCTAssertEqual(e[2].text, "Kabel getauscht 🙂\nBitte testen.")
        XCTAssertEqual(e[3].autor, "Linda Beutel"); XCTAssertEqual(e[3].text, "Danke, geht wieder!")
    }

    /// Sammelbehälter „comments“ darf nicht alle Kommentare zu einer Blase machen
    func testSammelbehaelterNichtAlsEintrag() {
        let html = """
        <main><div class="comments"><div class="comment"><span class="author">Kim Muster</span><time>19.11.2026 08:15</time><p>Eins</p></div>
        <div class="comment"><span class="author">Kim Muster</span><time>19.11.2026 08:16</time><p>Zwei</p></div></div></main>
        """
        XCTAssertEqual(Stoerungen.verlaufAus(html, von: "https://schule.de/x").eintraege.map(\.text), ["Eins", "Zwei"])
    }

    func testIchErkennung() {
        XCTAssertTrue(Stoerungen.istIch("Christian Stake", benutzer: "christian.stake"))
        XCTAssertTrue(Stoerungen.istIch("Christian Stake-Admin", benutzer: "christian.stake"))
        XCTAssertFalse(Stoerungen.istIch("Linda Beutel", benutzer: "christian.stake"))
        XCTAssertTrue(Stoerungen.istIch("Linda Beutel", benutzer: "christian.stake", ichName: "Linda Beutel"))   // von Hand festgelegt hat Vorrang
    }
}

final class ChatBereinigenTests: XCTestCase {
    /// Textbausteine („Kein weiterer Kommentar“, „Kommentar hinzufügen“, Angaben-Spalten) und Wiederholungen fliegen raus
    func testBausteineUndWiederholungen() {
        let l = [
            StoerungVerlauf.Eintrag(autor: "", zeit: "", text: "Das Board bleibt schwarz.\nStatus: Neu\nRaum: 104\nDas Board bleibt schwarz.\nKein weiterer Kommentar."),
            StoerungVerlauf.Eintrag(autor: "Kim Muster", zeit: "", text: "Kommentar hinzufügen"),
            StoerungVerlauf.Eintrag(autor: "Kim Muster", zeit: "", text: "Schaue ich mir morgen an."),
            StoerungVerlauf.Eintrag(autor: "Kim Muster", zeit: "", text: "Schaue ich mir  morgen an."),
            StoerungVerlauf.Eintrag(autor: "Kim Muster", zeit: "", text: "Danke"),
            StoerungVerlauf.Eintrag(autor: "Linda Beutel", zeit: "", text: "Danke"),
        ]
        XCTAssertEqual(Stoerungen.bereinigen(l).map(\.text), ["Das Board bleibt schwarz.", "Schaue ich mir morgen an.", "Danke", "Danke"])
    }

    /// Kopf der IServ-Detailseite (Titel, „Name | Datum“, Kategorie, Status) und „Es wurden noch keine Dateien angehängt!“ fliegen raus
    func testKopfDerDetailseite() {
        let t = "Details zu Kalendereintrag\nVertretungsplan\nZurück zur Liste\n\nKalendereintrag Vertretungsplan\nKim Muster | 01.10.2026 07:51\n| Medienproblem |\neingereicht\nHallo :)\n\nIch sehe den Kalender nicht.\n\nEs wurden noch keine Dateien angehängt!"
        XCTAssertEqual(Stoerungen.bereinigen([.init(autor: "Kim Muster", zeit: "", text: t)]).map(\.text), ["Hallo :)\n\nIch sehe den Kalender nicht."])
    }
}

final class PersonenFarbenTests: XCTestCase {
    /// Farben wie auf dem Board „Medien“: Vorname + Anfang des Nachnamens, „Admin“-Konten gleich
    func testNamenZuordnen() {
        let f = ["Christian S.": "#76a5af", "Christian N.": "#7aab5c", "Vivi": "#8c7fc2", "Jörn": "#de9a4b"]
        XCTAssertEqual(Aufgaben.farbe(fuer: "Christian Stake Admin", in: f), "#76a5af")
        XCTAssertEqual(Aufgaben.farbe(fuer: "Christian Normann", in: f), "#7aab5c")
        XCTAssertEqual(Aufgaben.farbe(fuer: "Viviane Haist Admin", in: f), "#8c7fc2")
        XCTAssertEqual(Aufgaben.farbe(fuer: "Jörn Muster", in: f), "#de9a4b")
        XCTAssertNil(Aufgaben.farbe(fuer: "Sonja Sellmann", in: f))
        XCTAssertNil(Aufgaben.farbe(fuer: "Christian Xaver", in: f))
        // Vorgabe aus dem Board „Medien“
        let m = Aufgaben.medienVorgabe
        XCTAssertEqual(Aufgaben.farbe(fuer: "Christian Stake", in: m), "#80a4ae")
        XCTAssertEqual(Aufgaben.farbe(fuer: "Christian Normann Admin", in: m), "#79a75a")
        XCTAssertEqual(Aufgaben.farbe(fuer: "Viviane Haist", in: m), "#8b7dbe")
        XCTAssertEqual(Aufgaben.farbe(fuer: "Michelle Muster", in: m), "#7ba7d8")
    }
}

final class AvatarTests: XCTestCase {
    /// Profilbilder aus der IServ-Seite: Name aus alt/title, „Admin“ egal, Adresse absolut
    func testAvatareAusSeite() {
        let html = #"<header><img class="avatar" src="/iserv/core/avatar/user/kim.muster" alt="Kim Muster"></header>"#
            + #"<div class="comment"><img src="/iserv/profile/picture/lea.beutel?size=32" title="Beutel, Lea"><span class="author">Lea Beutel</span><p>Geht wieder.</p></div><img src="/logo.png" alt="Schule am Damm">"#
        let v = Stoerungen.verlaufAus(html, von: "https://schule.de/iserv/report/7")
        XCTAssertEqual(v.avatar("Kim Muster Admin"), "https://schule.de/iserv/core/avatar/user/kim.muster")
        XCTAssertEqual(v.avatar("Lea Beutel"), "https://schule.de/iserv/profile/picture/lea.beutel?size=32")
        XCTAssertNil(v.avatar("Schule am Damm"))
    }

    /// Ohne Namen am Bild: Profilbild (auch als Hintergrundbild) im Beitrag gehört zur Person des Beitrags
    func testAvatarImBeitrag() {
        let html = #"<div class='comment'><span class='avatar' style='background-image: url(&quot;/iserv/core/avatar/user/lea.beutel&quot;)'></span><span class='author'>Lea Beutel</span><p>Geht wieder.</p></div>"#
        XCTAssertEqual(Stoerungen.verlaufAus(html, von: "https://schule.de/iserv/report/7").avatar("Lea Beutel"), "https://schule.de/iserv/core/avatar/user/lea.beutel")
    }
}
