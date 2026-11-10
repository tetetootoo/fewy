# AdMob / UMP Prüfung — 10. November 2026

**Nachträgliche Änderung:** Die Studio-Paywall und StoreKit-Integration wurden entfernt. Alle Studio-Funktionen sind kostenlos verfügbar; die frühere Studio-Ausnahme für Anzeigen entfällt. AdMob bleibt einwilligungsabhängig. Die folgenden Studio-Kaufhinweise beschreiben den damaligen Prüfstand und sind überholt.

## Projekt und Anfragepfad

Aufgelöst und beim Build verwendet: Google Mobile Ads **13.12.0**, UMP **3.1.0**. Keine SDK-Aktualisierung. `Package.resolved` und die heruntergeladenen Paket-Manifeste stimmen überein.

`FewyApp` und `NotesScreen` starten das Ads-SDK nicht. Styles bindet `FewyAdSection` ein. `FewyAds.prepare()` aktualisiert zuerst UMP, präsentiert bei Anzeigenberechtigung gegebenenfalls den Consent-Dialog und prüft danach die Werbeentscheidung. Nur `requestAd()` ruft `MobileAds.shared.start()`, erstellt einen `AdLoader` und ruft `load(Request())` auf. Es gibt keinen weiteren Preload- oder Anzeigenanfragepfad im App-/Widget-Code. Ad Inspector bleibt ein Debug-Werkzeug und wird erst nach einem erlaubten SDK-Start geöffnet.

Die frühere optionale direkte Sponsorenkarte und ihre Beispielkonfiguration wurden entfernt. Das Projekt enthält keine zusätzlichen Mediation-SDKs; serverseitige AdMob-Einstellungen sind dadurch nicht nachgewiesen. Studio als vorhandener In-App-Kauf bleibt erhalten.

## Neue Entscheidung

`canRequestAds` ist notwendig, aber im GDPR-Pfad nicht hinreichend. Zusätzlich werden die von UMP gespeicherten Signale nur gelesen:

- Purpose 1 und Google Vendor 755 müssen Consent haben.
- Für Google müssen Purposes 2, 7, 9 und 10 jeweils eine gültige Rechtsgrundlage haben. Google verwendet hier standardmäßig Legitimate Interest; eine Publisher Restriction „Require Consent“ schaltet den jeweiligen Zweck auf Consent um. Zweck- und Vendor-Signale werden gemeinsam geprüft. Ein LI-Widerspruch wird nicht durch einen beliebigen Consent-Bit ersetzt.
- Publisher Restrictions „Not Allowed“ sperren den betroffenen Zweck. „Require LI“ kann keine Einwilligung für Googles nicht flexible Purposes 1, 3 und 4 ersetzen.
- Purposes 3 und 4 werden für den NPA-Anfragepfad nicht vorausgesetzt. Sind sie mit gültigem Google-Consent vorhanden, ist der Pfad für personalisierte Anzeigen berechtigt. Dies ist keine Zusage, welchen Anzeigenmodus Google tatsächlich ausliefert.
- Der TC-Core wird ausschließlich lesend dekodiert, einschließlich Vendor-Bitfeldern/Ranges und Publisher Restrictions; für TCF 2.3 wird Googles Disclosure geprüft. Die UMP-Projektionen in UserDefaults müssen zu den relevanten TC-Signalen passen. UMPs elfstellige Purpose-Projektionen werden unterstützt.
- Fehlende, unlesbare oder widersprüchliche Signale sperren den GDPR-Anfragepfad. Ein UMP-Update-/Formularfehler sperrt Anzeigen für diesen Ablauf, auch bei früherer Zustimmung.
- UMP `.notRequired` sowie explizit nicht anwendbares GDPR behalten den bisherigen SDK-gesteuerten Pfad. Fehlende TCF-Signale allein werden nicht als Nicht-EWR interpretiert.

Google Mobile Ads liest weiterhin den unveränderten TC-String und entscheidet die zulässige Auslieferung. Fewy schreibt weder TCF-Bits noch erfundene Einwilligungen und fügt keine zusätzliche Monetarisierungsquelle hinzu.

## Lebenszyklus und Diagnose

Ein gemeinsamer Controller serialisiert Consent- und Anfrageabläufe pro Prozess. Wiederöffnen von Styles löst keine zweite Anfrage aus. Vor dem Öffnen der Privacy Options wird die sichtbare Anzeige entfernt, der alte Loader entkoppelt und die Anfragegeneration ungültig gemacht. Alte Loader-Antworten werden nicht mehr angenommen. Vor SDK-Start, vor `load` und bei erfolgreicher Antwort wird die Berechtigung geprüft.

Ein bereits gestartetes SDK wird bei Widerruf nicht rückwirkend aus dem Prozess entfernt. Fewy startet danach keine neue native Anfrage; eine bereits laufende Netzwerkanfrage kann noch enden, ihre alte Anzeige wird verworfen. Beim nächsten Prozessstart verhindert gespeicherte Ablehnung auch den SDK-Start aus diesem Pfad.

Die Privacy Options bleiben bei UMP-Anforderung auch mit Studio erreichbar. Studio sperrt Anzeigen; das UMP-Informationsupdate bleibt möglich, ein erstmaliger Werbedialog wird für Studio nicht erzwungen.

`Reset consent test`, `.EEA`, Purpose-/Vendor-Diagnosen und lokale Konsolenausgaben sind erhalten. Reset und Geografie-Override sind durch `DEBUG && targetEnvironment(simulator)` ausgeschlossen. Release verwendet die konfigurierte Fewy-Ad-Unit; Debug weiterhin Googles Demo-Unit. Der vollständige TC-String wird nicht protokolliert.

## Verifikation

21 isolierte Regressionstests: `python3 Tests/test_consent_gate.py`. Die Fixtures verändern keine UMP-/TCF-Signale der App. Abgedeckt: Zustimmung, NPA, Ablehnung, Vendor-Ablehnung, LI-Widersprüche, Publisher Restrictions, alternative Consent-Rechtsgrundlagen, Range-Encoding, TCF-2.3-Disclosure, elfstellige UMP-Projektionen und fehlende/fehlerhafte/widersprüchliche Werte.

Debug und Release des finalen Stands erfolgreich für den aktiven iPhone 17 Pro / iOS 26.5 Simulator gebaut. Der finale Debug-Build wurde installiert und gestartet. Im Release-App-Binary fehlen Reset-Button, Consent-Test-Logs, Ad-Inspector-Button und Googles Demo-Ad-Unit. Ein zwischenzeitlicher Universal-Build scheiterte an fehlendem Speicherplatz; nur die temporären Caches dieser Prüfung wurden entfernt und anschließend gezielt arm64 gebaut.

Tatsächliche Simulatorfälle (UMP-Dialogauswahl teilweise durch die Nutzerin, da die Fernsteuerung bei Koordinatenklicks `noWindowsAvailable` meldete):

| Fall | Purpose 1 / Google 755 Consent | Purpose 3 / 4 Consent | LI 2 / 7 / 9 / 10 | SDK-Start aus diesem Ablauf | Native Anfrage |
|---|---|---|---|---|---|
| Vollständige Ablehnung über „Nicht einwilligen“ | 0 / 0 | 0 / 0 | 1 / 1 / 1 / 1 | Nein | Nein |
| Neustart nach gespeicherter Ablehnung | 0 / 0 | 0 / 0 | 1 / 1 / 1 / 1 | Nein | Nein |
| Zustimmung | 1 / 1 | 1 / 1 | 1 / 1 / 1 / 1 | Ja | Eine; geladen |
| Widerruf nach geladener Anzeige | 0 / 0 | 0 / 0 | 0 / 1 / 1 / 1 | Kein neuer Start; SDK war bereits aktiv | Keine weitere; Anzeige entfernt |
| Erlaubte NPA-Auswahl ohne Personalisierung | 1 / 1 | 0 / 0 | 1 / 1 / 1 / 1 | Bereits aktiv, kein erneuter Start | Eine; geladen |
| Finaler Debug-Build, Neustart mit gespeicherter NPA-Auswahl | 1 / 1 | 0 / 0 | 1 / 1 / 1 / 1 | Ja | Eine; geladen |

Für alle Tabellenzeilen: GDPR=1, TC-String vorhanden, Google Vendor LI=1, keine Google Publisher Restrictions, `canRequestAds=true`. Bei Zustimmung/NPA stehen zusätzlich die Consent-Bits für 2, 7, 9 und 10 auf 1; die Rechtsgrundlage für Google ist ohne Publisher Restriction weiterhin LI. Die Verweigerung ließ LI teilweise bestehen, wurde wegen fehlender Purpose-1-/Google-Einwilligung trotzdem gesperrt.

Nach erneutem Öffnen von Styles blieb im finalen Prozess die Zahl der SDK-Starts und nativen Requests jeweils bei eins. Die entfernte Anzeige nach Widerruf wurde visuell geprüft; Privacy Options blieb erreichbar. Die konsolidierte lokale Konsolenausgabe steht in `AdMob-UMP-Testprotokoll.txt`.

Ein Demo-Ad-Load bestätigt nur den Anfragepfad, keinen produktiven Anzeigenmodus. Kein vollständiger Netzwerk-/Telemetry-Audit. Nicht als interaktiver Simulatorfall ausgeführt: Region mit `.notRequired`, erzwungener UMP-Netzwerkfehler, absichtlich verspätete Loader-Antwort und Studio-Kauf. Diese Pfade wurden im Code geprüft; die TCF-Fehlersignale sind durch isolierte Fixtures abgedeckt. Für die übrigen Laufzeitprüfungen: auf einem passenden Testgerät/regionalen Testlauf UMP `.notRequired` verifizieren; für Fehler Netzwerk gezielt unterbrechen; eine Loader-Antwort während des Öffnens der Privacy Options verzögern; Studio per StoreKit-Test kaufen und die weiter erreichbaren Privacy Options prüfen.

## In AdMob separat prüfen

1. **Programmatic limited ads bleibt ausgeschaltet.** Die Kontoeinstellung ist nicht aus dem Quellcode überprüfbar; Fewys lokale Sperre funktioniert unabhängig davon.
2. Richtige App-ID, richtige native Anzeigen-Unit und veröffentlichte UMP-Nachricht für Fewy prüfen. Ablehnen, Auswahl ändern und NPA-Konfiguration müssen in der veröffentlichten Nachricht erreichbar sein.
3. Google Vendor 755, Rechtsgrundlagen und Publisher Restrictions sowie tatsächlich ausgewählte Ad-Technology-Partner/Authorized Buyers prüfen. Der getestete Dialog nennt 210 Partner; daraus folgt weder, dass 210 SDKs installiert sind, noch dass alle Partner Daten erhalten haben.
4. Keine unbeabsichtigten weiteren Mediation-/Bidding-Quellen konfigurieren. AdMob als Vermittlungsdienst kann dennoch weitere Werbepartner einbeziehen.
5. App-Freigabe, app-ads.txt, Reporting und produktive Privacy-Signale auf einem echten Gerät mit Testgeräte-Konfiguration prüfen. Für NPA und personalisierte Auslieferung nicht allein auf die Demo-Anzeige vertrauen.
6. App-Store-Datenschutzangaben, eingebundene SDK-Privacy-Manifeste, SKAdNetwork-Liste und gegebenenfalls ATT-Anforderungen mit der tatsächlichen Produktionskonfiguration abgleichen. Das App-eigene Manifest enthält derzeit leere CollectedDataTypes und Tracking=false; das allein beschreibt nicht den gesamten AdMob-Datenfluss.

## Datenschutzerklärung: belegbare Aussagen und offene Angaben

Nach Auslieferung dieses Codes kann die technische Beschreibung sagen: Werbung wird über AdMob eingebunden; UMP verwaltet die Auswahl; Fewy prüft vor seinen Anzeigenanfragen zusätzliche GDPR-Signale; nach vollständiger Ablehnung wird aus diesem Pfad weder das Ads-SDK gestartet noch eine native Anzeige angefragt. Styles bleibt nutzbar. Einwilligungen können über die von UMP verlangten Privacy Options geändert werden. Bei Widerruf entfernt Fewy die sichtbare Anzeige und unterbindet weitere eigene native Anfragen.

Nicht schreiben: „Nach Ablehnung gibt es keinerlei Verbindung zu Google“ oder „es werden keine Daten übertragen“. UMP wird für das Informationsupdate/den Dialog verwendet. Ebenso sind nicht personalisierte Anzeigen nicht mit einer Verarbeitung ohne Einwilligung oder ohne Gerätezugriff gleichzusetzen.

**Aus dem Projekt allein nicht bestätigt:** vollständige Empfänger-/Unterauftragsverarbeiterliste und Rollen der Beteiligten, konkrete verarbeitete Daten und serverseitige Zwecke, Speicher- und Löschfristen, Verarbeitungsländer, Drittlandübermittlungen und deren Garantien, serverseitige Verarbeitung nach Widerruf. Diese Angaben müssen anhand der tatsächlichen AdMob-Konfiguration, aktuellen Google-Verträge/-Dokumentation und des produktiven Datenflusses ergänzt werden. Die Datenschutzerklärung wurde hier nicht veröffentlicht oder pauschal als rechtlich vollständig eingestuft.

## Quellen

- https://support.google.com/admob/answer/9760862 — Google-spezifische Purpose-/Vendor-Anforderungen, flexible Registrierung und Publisher Restrictions.
- https://developers.google.com/admob/ios/privacy/ad-serving-modes — personalisierte, nicht personalisierte und Limited-Ads-Modi.
- https://developers.google.com/admob/ios/privacy/gdpr — Lesen der UMP-/TCF-Auswahl.
- https://developers.google.com/admob/ios/privacy — UMP-Update, Privacy Options, Debug-Geografie und Test-Reset; API-Namen zusätzlich an installierten UMP-3.1.0-Headern geprüft.
- https://github.com/InteractiveAdvertisingBureau/GDPR-Transparency-and-Consent-Framework/blob/master/TCFv2/IAB%20Tech%20Lab%20-%20Consent%20string%20and%20vendor%20list%20formats%20v2.md — lesendes Dekodieren des TC-Core und Publisher Restrictions.
