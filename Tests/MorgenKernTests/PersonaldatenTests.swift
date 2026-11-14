import XCTest
@testable import MorgenKern

final class PersonaldatenTests: XCTestCase {
    func testGeheimnisAusLink() {
        XCTAssertEqual(Personaldaten.geheimnis("otpauth://totp/Hamburg%3ATEST?secret=JBSWY3DPEHPK3PXP&issuer=Hamburg"), "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(Personaldaten.geheimnis(" jbsw y3dp ehpk 3pxp "), "JBSWY3DPEHPK3PXP")
        XCTAssertNil(Personaldaten.geheimnis("otpauth://totp/x?issuer=Hamburg"))
        XCTAssertNil(Personaldaten.geheimnis("hallo"))
    }

    func testSkripteSindSicher() {
        let s = Personaldaten.anmeldeSkript(email: "a@b.de", passwort: "x'\"</script>\\")
        XCTAssertTrue(s.contains(#""x'\"<\/script>\\""#) || s.contains(#""x'\"</script>\\""#), s)
        XCTAssertTrue(Personaldaten.otpSkript(code: "123456").contains("\"123456\""))
    }
}
