import Foundation

/// MeinePersonaldaten (ZPD Hamburg, P&I LOGA3): Anmeldung über das HamburgService-Konto, dann OTP-Code im Portal.
/// Die App öffnet das echte Portal und füllt die Felder selbst aus – Zugangsdaten nur im Schlüsselbund.
public enum Personaldaten {
    public static let start = URL(string: "https://www.meinepersonaldaten.hamburg.de/")!

    /// Geheimnis aus „otpauth://totp/Hamburg%3ANAME?secret=ABC…&issuer=Hamburg“ – oder das Geheimnis selbst (Base32)
    public static func geheimnis(_ eingabe: String) -> String? {
        let t = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("otpauth://") {
            guard let s = URLComponents(string: t)?.queryItems?.first(where: { $0.name.lowercased() == "secret" })?.value, !s.isEmpty else { return nil }
            return s.uppercased()
        }
        let g = t.uppercased().replacingOccurrences(of: " ", with: "")
        return g.range(of: #"^[A-Z2-7]+=*$"#, options: .regularExpression) != nil && g.count >= 16 ? g : nil
    }

    /// Text sicher in JavaScript einsetzen (als JSON-Zeichenkette)
    public static func js(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(String(data: d, encoding: .utf8)!.dropFirst().dropLast())
    }

    /// Skript für die Anmeldeseite des HamburgService-Kontos: E-Mail und Passwort eintragen und abschicken
    public static func anmeldeSkript(email: String, passwort: String) -> String {
        """
        (function(){var u=document.querySelector('input[name="Username"]'),p=document.querySelector('input[name="Password"]');
        if(!u||!p)return 'kein-formular';u.value=\(js(email));p.value=\(js(passwort));
        ['input','change'].forEach(function(e){u.dispatchEvent(new Event(e,{bubbles:true}));p.dispatchEvent(new Event(e,{bubbles:true}));});
        var b=document.querySelector('[name="LoginUsingUsernamePassword"]');if(b){b.click();return 'ok';}
        var f=u.form;if(f){f.submit();return 'ok';}return 'kein-knopf';})();
        """
    }

    /// Skript für die OTP-Seite des Portals: Code eintragen und anmelden
    public static func otpSkript(code: String) -> String {
        """
        (function(){var t=document.getElementById('token');if(!t)return 'kein-feld';t.value=\(js(code));
        if(typeof doLogin==='function'){doLogin();return 'ok';}return 'kein-login';})();
        """
    }
}
