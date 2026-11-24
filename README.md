# Scholar-Counter

Zeigt Google-Scholar-Zitationen auf einer Pixeluhr (Ulanzi TC001 mit AWTRIX NG).

Eine GitHub Action ruft einmal am Tag das Scholar-Profil ab, vergleicht es mit dem Vortag und
schreibt eine kleine `clock.json`. GitHub Pages stellt die Datei öffentlich bereit, und die Uhr holt
sie sich alle 30 Minuten selbst. Ein Server im Heimnetz ist nicht nötig, die Uhr braucht nur WLAN.

## Was die Uhr anzeigt

Jede Seite ist eine eigene App. Dazwischen steht jeweils 30 s die Uhrzeit
(Reihenfolge und Nachtschaltung: App „Nachtmodus“).

| App (Skript) | Inhalt |
|---|---|
| Animation (`animation.be`) | zufällige Animation, läuft einmal komplett durch (Liste in den App-Einstellungen; `name~` = kleines 8x8-Icon läuft durchs Bild) |
| Scholar (`scholar.be`) | holt die Daten für alle Scholar-Apps. Zeigt: Name als Laufschrift → „CITATIONS“ → goldene Anführungszeichen, Zitationen in Weiß, Zuwachs der letzten 48 h in Grün (gleiches Zeitfenster wie die News), unterste Zeile Fortschritt bis zum nächsten h-Index |
| Scholar-hIndex (`scholar_hindex.be`) | „h-index 5 · 2 more to h6“ |
| Scholar-Paper (`scholar_paper.be`) | „7 papers in the last 12 months“ |
| Scholar-Jahr (`scholar_jahr.be`) | „Citations in 2026: 1,234“ |
| Scholar-Ziel (`scholar_ziel.be`) | „22 citations to 150!“ (nächster Meilenstein) |
| Scholar-Top (`scholar_top.be`) | meistzitiertes Paper mit Jahr und Zitationszahl |
| Scholar-Jubilaeum (`scholar_jubilaeum.be`) | nur am Jahrestag eines der 3 meistzitierten Paper: „5 years ago today: …“ |
| Scholar-Chart (`scholar_chart.be`) | Erklärung als Laufschrift, dann laufen die Balken von rechts herein (laufendes Jahr in Gold): Zitationen pro Monat (ab 3 aufgezeichneten Monaten), vorher pro Jahr |
| Scholar-News (`scholar_news.be`) | nur wenn es etwas gibt: „New paper: …“ (24 h), „Cited by …“ (48 h), eigene Nachricht |
| Geburtstag (`geburtstag.be`) | am eingestellten Tag (6.12.) bunte Laufschrift mit Konfetti in der Rotation, um 8:30 Uhr große Party mit Happy-Birthday-Melodie. Daten nur auf der Uhr gespeichert |
| Nachricht (`nachricht.be`) | eigener Text als Laufschrift (Text, Farbe, Anzahl Durchläufe in den App-Einstellungen). Leer = nicht in der Rotation |
| Nachtmodus (`nachtmodus.be`) | zeigt nichts. 22–7 Uhr nur Uhrzeit, morgens wieder alle Apps |
| Party | klein bei neuen Zitationen („Heureka! +3 citations!“), groß bei neuem Paper, h-Index oder Meilenstein. Bleibt stehen, bis die mittlere Taste gedrückt wird. Nachts wartet sie bis 7 Uhr |

Ein roter Punkt oben rechts heißt: Die Daten sind veraltet (letzter Abruf fehlgeschlagen oder älter als 2 Tage).

## Dateien

```
config.json                     Einstellungen (Scholar-ID, ORCID, Zeiten, Meilensteine, Nachricht)
scripts/update.py               Abruf und Vergleich, schreibt docs/ und data/
.github/workflows/update.yml    Action 6x täglich zwischen 7 und 22 Uhr (Winterzeit) + manueller Start
docs/clock.json                 kleine Datei für die Uhr (wird erzeugt)
docs/full.json                  alle Daten zum Nachschauen (wird erzeugt)
data/state.json                 Gedächtnis zwischen den Läufen (wird erzeugt)
awtrix/*.be                     Skripte für die Uhr (Berry, AWTRIX NG), siehe oben
tests/fixtures/                 Testdaten für Läufe ohne Internet
```

## Einrichtung

1. **Repository anlegen:** auf github.com ein **öffentliches** Repository `scholar-counter` anlegen
   und diese Dateien hochladen. Achtung: Der Ordner `.github` ist auf dem Mac im Finder versteckt
   (Cmd+Shift+Punkt zeigt ihn). Ohne ihn läuft keine Action.
2. **SerpApi-Schlüssel hinterlegen:** Google Scholar blockiert direkte Abfragen von GitHub-Servern.
   Deshalb läuft der Abruf über SerpApi (kostenloser Tarif: 250 Anfragen im Monat, die Action
   braucht etwa 30). Auf serpapi.com ein Konto anlegen, den API-Key kopieren und im Repository unter
   Settings → Secrets and variables → Actions → New repository secret mit dem Namen `SERPAPI_KEY`
   speichern. Ohne diesen Schlüssel versucht die Action, Scholar direkt abzufragen.
3. **GitHub Pages einschalten:** Settings → Pages → Source „Deploy from a branch“ →
   Branch `main`, Ordner `/docs` → Save.
4. **Action zum ersten Mal starten:** Actions → „Scholar aktualisieren“ → Run workflow.
   Nach ein bis zwei Minuten sollte es diese Datei geben:
   `https://benknst.github.io/scholar-counter/clock.json`
   Der erste Lauf legt nur den Ausgangsstand fest. Neuigkeiten gibt es ab dem zweiten Lauf.
5. **Uhr:** In der Weboberfläche von AWTRIX NG je ein Skript pro Datei in `awtrix/` anlegen,
   Namen genau so: `Scholar`, `Scholar-hIndex`, `Scholar-Paper`, `Scholar-Chart`,
   `Scholar-News`, `Animation`, `Geburtstag`, `Nachricht`, `Nachtmodus`. Display → „Time per app“ = 30000 ms (Uhrzeit 30 s; die
   Scholar-Apps bestimmen ihre Dauer selbst). Die Reihenfolge stellt der Nachtmodus ein.

## Einstellungen (`config.json`)

| Schlüssel | Bedeutung |
|---|---|
| `scholar_id` | Teil nach `user=` in der Scholar-Profil-URL |
| `orcid` | optional, z. B. `0000-0002-1234-5678`, für „Zitiert in: …“ über OpenAlex |
| `new_publication_hours` | wie lange eine neue Publikation durchläuft (Standard 24) |
| `new_citation_hours` | wie lange neue Zitationen gemeldet werden (Standard 48) |
| `citation_milestones` | Zahlen, bei denen gefeiert wird |
| `message`, `message_until` | eigene Laufschrift, optional mit Enddatum `JJJJ-MM-TT` |

Eine Nachricht für die Uhr lässt sich direkt auf github.com in `config.json` ändern. Sie erscheint
nach dem nächsten Lauf der Action. Wer nicht warten will, startet die Action von Hand.

## Lokal testen

```
pip install --no-deps scholarly
pip install -r requirements.txt
python scripts/update.py                     # echter Abruf
python scripts/update.py --fixture tests/fixtures/day1.json --now 2026-11-17T05:00:00Z
python scripts/update.py --fixture tests/fixtures/day2.json --now 2026-11-18T05:00:00Z
```

Lokale Testläufe verändern `docs/` und `data/`. Den echten Stand danach mit `git checkout docs data`
zurückholen.

## Bekannte Grenzen

- Google Scholar hat keine offizielle API und blockiert Abfragen von GitHub-Servern (getestet:
  `MaxTriesExceededException`). Deshalb SerpApi. Schlägt auch das fehl, bleibt die alte Anzeige stehen, die Uhr zeigt den roten Punkt, und die Action schlägt fehl.
  GitHub verschickt in dem Fall eine E-Mail.
- In öffentlichen Repositories deaktiviert GitHub geplante Workflows nach 60 Tagen ohne Aktivität.
  Die Action committet zwar täglich, falls sie trotzdem einmal stehen bleibt:
  Actions → „Scholar aktualisieren“ → „Enable workflow“.
- SerpApi-Kontingent: Vor jedem Lauf fragt das Skript kostenlos den Kontostand ab. Reicht er nicht
  mehr für alle Läufe bis Monatsende, läuft es nur noch um 7 und 16 Uhr (Sparmodus). Extras wie
  Titel-Nachladen gibt es nur bei genug Reserve. Bei mehr als 100 Papern werden die 100
  meistzitierten abgefragt, dazu einmal täglich die 20 neuesten.
- Wird in `config.json` eine andere Scholar-ID eingetragen, legt das Skript den Ausgangsstand
  automatisch neu an (keine falschen „New paper“-Meldungen).
- SerpApi-Extras (nur bei genug Reserve): einmalig die Erscheinungsdaten der Paper aus diesem und dem
  letzten Jahr (max. 5 pro Lauf), und bei neuen Zitationen „wer hat zitiert“ (max. 3 Paper pro Lauf).
- Scholar kürzt lange Titel im Profil. Für neue Publikationen lädt die Action den vollen Titel nach.
- Scholar-Zahlen können sinken, wenn Google Einträge zusammenführt. Gemeldet werden nur Zuwächse.
- „Zitiert in“ kommt aus OpenAlex, nicht aus Scholar. Die Titel passen deshalb nicht immer genau zu den
  Zitationen, die Scholar zählt.
