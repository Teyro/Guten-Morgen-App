import XCTest
@testable import MorgenKern

final class MatrixTests: XCTestCase {
    /// /sync auswerten: Namen aus Mitglieds-Ereignissen, Direktchat nach Gegenüber benannt, verschlüsselt erkannt, neueste zuerst, Folge-Sync hängt an
    func testSyncEinarbeiten() throws {
        let erst = #"""
        {"next_batch":"s1","rooms":{"join":{
          "!a:s":{"summary":{"m.heroes":["@kim.muster:s"]},"unread_notifications":{"notification_count":2},
            "state":{"events":[{"type":"m.room.member","state_key":"@kim.muster:s","content":{"displayname":"Kim Muster"}}]},
            "timeline":{"events":[{"type":"m.room.message","event_id":"$1","sender":"@kim.muster:s","origin_server_ts":1700000000000,"content":{"msgtype":"m.text","body":"Hallo"}}]}},
          "!b:s":{"state":{"events":[{"type":"m.room.name","state_key":"","content":{"name":"Kollegium"}},{"type":"m.room.encryption","state_key":"","content":{}}]},
            "timeline":{"events":[{"type":"m.room.encrypted","event_id":"$2","sender":"@lea:s","origin_server_ts":1700000100000,"content":{}}]}}
        }}}
        """#
        var (r, w) = Matrix.einarbeiten(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(erst.utf8)) as? [String: Any]), in: [])
        XCTAssertEqual(w, "s1")
        XCTAssertEqual(r.map(\.name), ["Kollegium", "Kim Muster"])
        XCTAssertTrue(r[0].verschluesselt && r[0].nachrichten[0].verschluesselt)
        XCTAssertEqual(r[1].ungelesen, 2)
        let dann = #"{"next_batch":"s2","rooms":{"join":{"!a:s":{"timeline":{"events":[{"type":"m.room.message","event_id":"$1","sender":"@kim.muster:s","origin_server_ts":1700000000000,"content":{"body":"Hallo"}},{"type":"m.room.message","event_id":"$3","sender":"@ich:s","origin_server_ts":1700000200000,"content":{"body":"Hi!"}}]}}}}}"#
        (r, w) = Matrix.einarbeiten(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(dann.utf8)) as? [String: Any]), in: r)
        XCTAssertEqual(r[0].nachrichten.map(\.text), ["Hallo", "Hi!"])
        XCTAssertEqual(r[0].name(von: "@ich:s"), "ich")
    }
}

final class MatrixPinTests: XCTestCase {
    /// Favorit-Tag = angepinnt und oben; Suche in Namen und Nachrichten
    func testKennungen() {
        XCTAssertEqual(Matrix.kennungen(" Vorname.Name@Schule.de ").map { $0["user"] ?? $0["address"] ?? "" }, ["vorname.name", "vorname.name@schule.de", "vorname.name@schule.de"])
        XCTAssertEqual(Matrix.kennungen("vorname.name").count, 1)
    }

    func testAnpinnenUndSuchen() throws {
        let j = #"{"next_batch":"s1","rooms":{"join":{"!alt:s":{"account_data":{"events":[{"type":"m.tag","content":{"tags":{"m.favourite":{"order":0.5}}}}]},"state":{"events":[{"type":"m.room.name","state_key":"","content":{"name":"Medien"}}]},"timeline":{"events":[{"type":"m.room.message","event_id":"$1","sender":"@a:s","origin_server_ts":1000,"content":{"body":"Beamer kaputt"}}]}},"!neu:s":{"state":{"events":[{"type":"m.room.name","state_key":"","content":{"name":"Kollegium"}}]},"timeline":{"events":[{"type":"m.room.message","event_id":"$2","sender":"@b:s","origin_server_ts":9000,"content":{"body":"Konferenz"}}]}}}}}"#
        let r = Matrix.einarbeiten(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(j.utf8)) as? [String: Any]), in: []).raeume
        XCTAssertEqual(r.map(\.name), ["Medien", "Kollegium"])
        XCTAssertEqual(Matrix.suchen(r, "beamer").map(\.name), ["Medien"])
        XCTAssertEqual(Matrix.suchen(r, "koll").map(\.name), ["Kollegium"])
    }
}

final class ChatMeldenTests: XCTestCase {
    /// Zu Hause sammeln, sonst sofort; ohne Standort nach Uhrzeit
    func testArt() {
        let z = Kontext.Ort(lat: 53.55, lon: 10.1), weg = Kontext.Ort(lat: 53.60, lon: 10.1)
        XCTAssertEqual(ChatMelden.art(hier: z, zuhause: z), .sammeln)
        XCTAssertEqual(ChatMelden.art(hier: weg, zuhause: z), .sofort)
        let k = Zeit.kalender
        let mi10 = k.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 10))!, mi20 = k.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 20))!
        let sa10 = k.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 10))!
        XCTAssertEqual(ChatMelden.art(jetzt: mi10, hier: nil, zuhause: nil), .sofort)
        XCTAssertEqual(ChatMelden.art(jetzt: mi20, hier: nil, zuhause: nil), .sammeln)
        XCTAssertEqual(ChatMelden.art(jetzt: sa10, hier: nil, zuhause: nil), .sammeln)
        XCTAssertEqual(k.component(.hour, from: ChatMelden.zeitpunkt("18:00", jetzt: mi10)), 18)
        XCTAssertEqual(k.component(.day, from: ChatMelden.zeitpunkt("18:00", jetzt: mi20)), 26)
    }

    /// Nur Nachrichten anderer; Raumname aus dem Merker, wenn der Folge-Sync ihn nicht liefert
    func testNeueUndZusammenfassung() throws {
        let j = #"{"next_batch":"s2","rooms":{"join":{"!k:s":{"timeline":{"events":[{"type":"m.room.message","event_id":"$1","sender":"@a:s","origin_server_ts":1000,"content":{"body":"Hallo"}},{"type":"m.room.message","event_id":"$2","sender":"@ich:s","origin_server_ts":2000,"content":{"body":"Selbst"}}]}}}}}"#
        var namen = ["!k:s": "Kollegium"]
        let n = ChatMelden.neue(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(j.utf8)) as? [String: Any]), ich: "@ich:s", namen: &namen)
        XCTAssertEqual(n.map(\.text), ["Hallo"])
        XCTAssertEqual(n.first?.raum, "Kollegium")
        let z = ChatMelden.zusammenfassung(["Medien": 1, "Kollegium": 3])
        XCTAssertEqual(z.titel, "4 neue Chat-Nachrichten")
        XCTAssertEqual(z.text, "Kollegium (3), Medien (1)")
    }
}

final class MatrixAnhangTests: XCTestCase {
    /// Foto als Anhang statt Dateiname als Text; Profilbilder aus m.room.member; Medien-Pfad mit Anmeldung (v1)
    func testAnhangUndAvatar() throws {
        let j = #"{"next_batch":"s1","rooms":{"join":{"!d:s":{"summary":{"m.heroes":["@v:s"]},"state":{"events":[{"type":"m.room.member","state_key":"@v:s","content":{"displayname":"Viviane Haist","avatar_url":"mxc://s/abc"}}]},"timeline":{"events":[{"type":"m.room.message","event_id":"$1","sender":"@v:s","origin_server_ts":1000,"content":{"msgtype":"m.image","body":"IMG_1.jpg","url":"mxc://s/bild1","info":{"w":800,"h":600}}},{"type":"m.room.message","event_id":"$2","sender":"@v:s","origin_server_ts":2000,"content":{"msgtype":"m.file","body":"Plan.pdf","url":"mxc://s/pdf"}}]}}}}}"#
        let r = try XCTUnwrap(Matrix.einarbeiten(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(j.utf8)) as? [String: Any]), in: []).raeume.first)
        XCTAssertEqual(r.nachrichten.map(\.text), ["📷 Foto", "📎 Plan.pdf"])
        XCTAssertEqual(r.nachrichten.first?.anhang?.mxc, "mxc://s/bild1")
        XCTAssertEqual(r.nachrichten.first?.anhang?.breite, 800)
        XCTAssertEqual(r.bild, "mxc://s/abc")
        XCTAssertEqual(Matrix.medienPfad("mxc://s/abc", groesse: 96), "/_matrix/client/v1/media/thumbnail/s/abc?width=96&height=96&method=scale")
        XCTAssertEqual(Matrix.medienPfad("mxc://s/abc"), "/_matrix/client/v1/media/download/s/abc")
        XCTAssertNil(Matrix.medienPfad("https://x/y"))
    }
}
