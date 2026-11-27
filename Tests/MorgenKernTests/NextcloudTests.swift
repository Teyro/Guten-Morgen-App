import XCTest
@testable import MorgenKern

final class NextcloudTests: XCTestCase {
    /// PROPFIND-Antwort (wie von nextcloud.teyro.synology.me, Ordner „DammAPP“)
    func testOrdnerLesen() {
        let xml = """
        <?xml version="1.0"?><d:multistatus xmlns:d="DAV:"><d:response><d:href>/remote.php/dav/files/clevertouch/DammAPP/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
        <d:response><d:href>/remote.php/dav/files/clevertouch/DammAPP/Fu%c3%9fballplatz_Haus1_Pausenbelegung.pdf</d:href><d:propstat><d:prop><d:getetag>&quot;abc123&quot;</d:getetag><d:getcontentlength>163810</d:getcontentlength><d:resourcetype/></d:prop></d:propstat></d:response>
        <d:response><d:href>/remote.php/dav/files/clevertouch/DammAPP/Fu%c3%9fballplatz_TH_Pausenbelegung.pdf</d:href><d:propstat><d:prop><d:getetag>&quot;def&quot;</d:getetag><d:getcontentlength>175404</d:getcontentlength><d:resourcetype/></d:prop></d:propstat></d:response></d:multistatus>
        """
        let l = Nextcloud.lesen(xml)
        XCTAssertEqual(l.map(\.name), ["Fußballplatz_Haus1_Pausenbelegung.pdf", "Fußballplatz_TH_Pausenbelegung.pdf"])
        XCTAssertEqual(l[0].etag, "abc123"); XCTAssertEqual(l[0].groesse, 163810); XCTAssertFalse(l[0].ordner)
        XCTAssertEqual(Nextcloud.planName(l[0].name), "Haus 1")
        XCTAssertEqual(Nextcloud.planName(l[1].name), "Turnhalle")
        XCTAssertEqual(Nextcloud(server: "https://nextcloud.teyro.synology.me/", benutzer: "clevertouch", passwort: "x").url("DammAPP/Pläne")?.absoluteString,
                       "https://nextcloud.teyro.synology.me/remote.php/dav/files/clevertouch/DammAPP/Pl%C3%A4ne")
    }
}
