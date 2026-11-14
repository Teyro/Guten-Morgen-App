# Guten Morgen: Portierung nach Scriptable und Android (interne Vorbereitung)

Stand: 2026-11-14 · Ausgangspunkt: Guten Morgen 2.0 (iOS/SwiftUI, Logik in `Sources/MorgenKern`).

Ziel: Leute ohne gutes/aktuelles iPhone sollen die Kernfunktionen auch bekommen – als Scriptable-Skript
(iOS, auch ältere Geräte) und möglichst als eigene Android-App. Das ist **Vorbereitung**, kein fertiger Bau.

## Grundidee: Logik ist schon getrennt

`MorgenKern` enthält die eigentliche Logik ohne UIKit/SwiftUI und ohne Netz-Framework (eigene HTTP-Helfer).
Jede Portierung baut nur UI und Plattform-Anbindung neu – die Regeln werden 1:1 übersetzt. `MorgenKern` ist
damit die Referenz-Spezifikation. Reihenfolge der Arbeit: 1) Datenlogik übersetzen, 2) dünne Plattform-Schicht
(Netz, Speicher, Schlüssel), 3) UI/Widget.

## Funktionen und ihre Portierbarkeit

| Funktion (MorgenKern) | Scriptable (iOS) | Android | Hinweis |
|---|---|---|---|
| Vertretung (`Vertretung.swift`) | ja – gibt es schon in [Mein Tag] | ja | reines Parsen + HTTP |
| IServ: Abwesenheiten/Störungen/Aufgaben (`IServ`, `Abwesenheiten`, `Stoerungen`, `Aufgaben`) | ja – in Mein Tag | ja | Login + 2FA (TOTP) nötig |
| WebUntis (`Untis.swift`) | ja | ja | TOTP-Login, jsonrpc |
| Speiseplan/Schulobst (`Mensa.swift`) | ja | ja | HTML/ICS parsen |
| Post & Pakete (`Post.swift`) | eigenes Skript existiert | ja (Post-und-Pakete Linux-Teil als Vorbild) | |
| Wetter/Glätte (`Wetter.swift`) | ja | ja | offene API |
| Weckzeit-Berechnung (`Weckzeit.swift`) | ja (Anzeige) | ja | reine Rechnung |
| Briefing-Text (`Briefing.swift`) | ja | ja | reine Textbildung |
| Home Assistant Morgen/Gute Nacht (`HomeAssistant.swift`) | ja | ja | REST-Aufruf |
| **Personaldaten (`Personaldaten.swift`)** | **nein, nicht automatisch** (siehe unten) | teilweise | braucht echten WebView mit Auto-Login |
| **AlarmKit-Wecker** (stellt echten Systemwecker) | **nein** | Android: AlarmClock-Intent möglich | Scriptable kann keinen Systemwecker stellen |
| **Live-Aktivität Schultag** | **nein** | Android: Vordergrund-Notification möglich | |
| **Weckmusik (Spotify/Kurzbefehl)** | eingeschränkt | Android: eigener Alarm-Dienst | |
| Fokus „Schule" automatisch | nein (nur Kurzbefehl) | Android: DND-Zeitplan | |
| Health-Schlafdaten | nein | Android: Health Connect | |

Fazit: Der **Informationsteil** (Schultag, Vertretung, Mensa, Post, Aufgaben, Störungen, Abwesenheiten,
Wetter, Weckzeit-Anzeige, Briefing) ist überall machbar. Der **aktive Teil** (echten Wecker stellen,
Live-Aktivität, Weckmusik, Fokus) bleibt iOS-nativ bzw. braucht Android-Gegenstücke.

## Scriptable-Variante

- Vieles existiert schon in **[Mein Tag]** (github.com/Teyro/Mein-Tag): Vertretung + IServ-Abw + IServ-Stör
  + Edupool + Guten-Morgen in einem Skript. Guten Morgen für Alt-iPhones = **Mein Tag ausbauen**, kein neues Repo.
- Plan: Mein Tag um Mensa/Schulobst, Wetter+Glätte, Post-Kurzinfo und die Weckzeit-**Anzeige** (ohne echten
  Wecker) ergänzen; großes Widget im Look der App (Kästen, Farbtöne) nachbauen.
- Speicher: `Keychain` (Scriptable) für Zugänge, TOTP wie in den vorhandenen Skripten.
- Grenze offen halten: Scriptable stellt keinen Wecker und keine Live-Aktivität. Im Skript klar sagen
  „Wecker bitte in der iPhone-Uhr", optional Kurzbefehl zum Stellen anbieten.
- **Personaldaten in Scriptable NICHT automatisch** – kein dauerhafter Cookie-WebView mit Auto-Login wie in der
  App. Höchstens: Skript öffnet das Portal im Safari. Automatik bleibt der nativen App vorbehalten.

## Android-Variante (eigene App)

- Kotlin, gleiche Projektstruktur wie die Damm-Apps (DammLauncher/DammBoard als Vorbild: eigene Netz-/Speicher-
  Helfer, keine großen Abhängigkeiten, Material-You-Optik aus `ui/m3`).
- `MorgenKern` → Kotlin-Modul `morgenkern` portieren: 1:1 die Parser und Rechnungen, mit den vorhandenen Swift-
  Unit-Tests als Vorlage für Kotlin-Tests (Testdaten übernehmen).
- Plattform-Schicht:
  - HTTP: OkHttp (wie Damm-Apps).
  - Schlüssel: Android Keystore statt iOS-Schlüsselbund.
  - TOTP: dieselbe RFC-6238-Rechnung (gibt es in DammTable `WebUntis.totp`).
  - Widget: App-Widget (großes Kästchen-Layout).
  - Wecker: `AlarmClock.ACTION_SET_ALARM` statt AlarmKit.
  - Personaldaten: Android-`WebView` kann denselben Auto-Login wie die iOS-App (JS einspritzen, Download-Listener).
- Reihenfolge: erst Lese-Funktionen + Widget, dann Wecker, Personaldaten zuletzt.

## Gemeinsame Pflege

- `MorgenKern` bleibt die Quelle der Wahrheit. Ändert sich ein Parser (z. B. Vertretungsplan-Format), muss er in
  allen drei Fassungen nach. Deshalb: Testdaten in `Tests/MorgenKernTests` gepflegt halten – sie sind die
  Vorlage für Scriptable- und Kotlin-Tests.
- Versionsnummern wie bei den Board-Apps nach Datum (Jahr.Monat.Tag) wäre eine Option, ist hier aber noch
  nicht entschieden (die App zählt bisher klassisch, aktuell 2.0.0).

[Mein Tag]: https://github.com/Teyro/Mein-Tag
