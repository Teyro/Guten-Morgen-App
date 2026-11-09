# Guten Morgen

iPhone-App mit Widget: errechnet die Weckzeit (Wochentag, früher vor dem ersten Termin, frei in Ferien und an Feiertagen)
und stellt sie ab iOS 26 als echten Wecker (AlarmKit). Liest morgens vor: Wetter, Termine, Erinnerungen, Post und Pakete
(Home Assistant, Integration „Briefankündigung“) und an Schultagen die eigene Vertretung aus dem Cloud-Ordner der Schule.
„Gute Nacht“ führt Home-Assistant-Aktionen aus, meldet offene Fenster und nennt den Wecker für morgen.

- **Widget** (klein, mittel, Sperrbildschirm): Wecker, Wetter, nächster Termin, Post. Funktioniert auch in neu signierten
  Apps (Signulous): Einstellungen und Zugang bekommt es beim Öffnen der App über eine kurze Live-Aktivität.
- **Siri/Kurzbefehle**: „Guten Morgen mit Guten Morgen“, „Gute Nacht mit Guten Morgen“, Aktion „Weckzeit für morgen“;
  Link `gutenmorgen://vorlesen` z. B. als Automation „Wenn Wecker gestoppt“.
- Daten: Open-Meteo (Wetter), OpenHolidays (Ferien/Feiertage), EventKit; nichts verlässt das iPhone außer diesen Abfragen
  und den Anfragen an deinen Home Assistant bzw. den Schul-Ordner.

Installation: IPA aus den Releases mit Signulous signieren. Bauen: `scripts/baue.sh` (Xcode, XcodeGen).
