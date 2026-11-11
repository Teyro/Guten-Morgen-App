# Guten Morgen

iPhone-App mit Widget: errechnet die Weckzeit (Wochentag, früher vor dem ersten Termin, frei in Ferien und an Feiertagen)
und stellt sie ab iOS 26 als echten Wecker (AlarmKit). Liest morgens vor: Wetter, Termine, Erinnerungen, Post und Pakete
(Home Assistant, Integration „Briefankündigung“) und an Schultagen die eigene Vertretung aus dem Cloud-Ordner der Schule.
„Gute Nacht“ führt Home-Assistant-Aktionen aus, meldet offene Fenster und nennt den Wecker für morgen.

- **Widget** (klein, mittel, Sperrbildschirm): Wecker, Wetter, nächster Termin, Post. Funktioniert auch in neu signierten
  Apps (Signulous): Einstellungen und Zugang bekommt es beim Öffnen der App über eine kurze Live-Aktivität.
- **Schultag** (1.6): eigener Stundenplan mit den Klingelzeiten der Schule; Vertretungen und Hofaufsichten kommen aus dem Vertretungsplan dazu.
  Live-Aktivität (Sperrbildschirm, Dynamic Island, Smart Stack der Apple Watch) und Widget „Schultag“: was läuft, wie lange noch, was danach kommt.
  Mitteilung 5 Minuten vor jeder Hofaufsicht.
- **Anfahrt und Wetter** (1.6): Fahrzeit über Apple Karten (Auto, Bus und Bahn, zu Fuß) – wird es knapp, klingelt der Wecker früher;
  bei Glätte oder Schnee ebenfalls. Morgens sagt das Briefing, wann du losfahren musst, und gibt Hinweise wie „Schirm mitnehmen“.
- **Morgenroutine** (1.6): legt in Home Assistant eine Automation an, die sich nach dem Wecker richtet (sensor.guten_morgen_wecker) –
  z. B. 20 Minuten vorher das Bad heizen, 10 Minuten vorher das Licht langsam hochfahren.
- **Fokus „Schule“** (1.6): Fokus-Filter – im Fokus zeigt die App die Schul-Infos zuerst; den Fokus schaltet iOS nach Ort ein.
- **Apple Watch** (1.6): eigene App (IPA „mit Uhr“) mit Wecker, laufender Stunde und Tagesablauf.
- **Siri/Kurzbefehle**: „Guten Morgen mit Guten Morgen“, „Gute Nacht mit Guten Morgen“, Aktion „Weckzeit für morgen“;
  Link `gutenmorgen://vorlesen` z. B. als Automation „Wenn Wecker gestoppt“.
- Daten: Open-Meteo (Wetter), OpenHolidays (Ferien/Feiertage), EventKit; nichts verlässt das iPhone außer diesen Abfragen
  und den Anfragen an deinen Home Assistant bzw. den Schul-Ordner.

Installation: IPA aus den Releases mit Signulous signieren. Bauen: `scripts/baue.sh` (Xcode, XcodeGen).
