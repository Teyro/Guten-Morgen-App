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
