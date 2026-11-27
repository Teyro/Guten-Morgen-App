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
    func testAnpinnenUndSuchen() throws {
        let j = #"{"next_batch":"s1","rooms":{"join":{"!alt:s":{"account_data":{"events":[{"type":"m.tag","content":{"tags":{"m.favourite":{"order":0.5}}}}]},"state":{"events":[{"type":"m.room.name","state_key":"","content":{"name":"Medien"}}]},"timeline":{"events":[{"type":"m.room.message","event_id":"$1","sender":"@a:s","origin_server_ts":1000,"content":{"body":"Beamer kaputt"}}]}},"!neu:s":{"state":{"events":[{"type":"m.room.name","state_key":"","content":{"name":"Kollegium"}}]},"timeline":{"events":[{"type":"m.room.message","event_id":"$2","sender":"@b:s","origin_server_ts":9000,"content":{"body":"Konferenz"}}]}}}}}"#
        let r = Matrix.einarbeiten(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(j.utf8)) as? [String: Any]), in: []).raeume
        XCTAssertEqual(r.map(\.name), ["Medien", "Kollegium"])
        XCTAssertEqual(Matrix.suchen(r, "beamer").map(\.name), ["Medien"])
        XCTAssertEqual(Matrix.suchen(r, "koll").map(\.name), ["Kollegium"])
    }
}
