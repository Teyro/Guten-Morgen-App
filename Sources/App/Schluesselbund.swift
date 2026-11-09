import Foundation
import Security

/// Home-Assistant-Token im Schlüsselbund der App
enum Schluesselbund {
    static func lesen(_ konto: String) -> String? {
        var e: AnyObject?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "de.teyro.gutenmorgen",
                                kSecAttrAccount as String: konto, kSecReturnData as String: true]
        guard SecItemCopyMatching(q as CFDictionary, &e) == errSecSuccess, let d = e as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func speichern(_ wert: String, _ konto: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "de.teyro.gutenmorgen", kSecAttrAccount as String: konto]
        SecItemDelete(q as CFDictionary)
        guard !wert.isEmpty else { return }
        var neu = q
        neu[kSecValueData as String] = Data(wert.utf8)
        neu[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(neu as CFDictionary, nil)
    }
}
