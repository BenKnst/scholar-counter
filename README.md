# Scholar-Counter

Zeigt Google-Scholar-Zitationen auf einer Pixeluhr (Ulanzi TC001 mit AWTRIX NG).

Eine GitHub Action ruft einmal am Tag das Scholar-Profil ab, vergleicht es mit dem Vortag und
schreibt eine kleine `clock.json`. GitHub Pages stellt die Datei öffentlich bereit, und die Uhr holt
sie sich alle 30 Minuten selbst. Ein Server im Heimnetz ist nicht nötig, die Uhr braucht nur WLAN.

## Was die Uhr anzeigt

| Seite | Inhalt |
|---|---|
| Zitationen | Buch-Symbol, Gesamtzahl, grün der Zuwachs seit gestern |
| h-Index | „h-Index 5 – noch 2 bis h6“ |
| Verlauf | Balkendiagramm Zitationen pro Jahr |
| Neuigkeiten | Laufschrift: neue Publikation (24 h), „+2 für: …“ (48 h), „Zitiert in: …“ (48 h, nur mit ORCID), eigene Nachricht |
| Feier | einmalige Benachrichtigung mit Ton bei neuem h-Index oder Meilenstein (100, 150, 200 … Zitationen) |

Ein roter Punkt oben rechts heißt: Der letzte Scholar-Abruf ist fehlgeschlagen, die Zahlen sind
vom Vortag oder älter.

## Dateien

```
config.json                     Einstellungen (Scholar-ID, ORCID, Zeiten, Meilensteine, Nachricht)
scripts/update.py               Abruf und Vergleich, schreibt docs/ und data/
.github/workflows/update.yml    tägliche Action (04:17 UTC) + manueller Start
docs/clock.json                 kleine Datei für die Uhr (wird erzeugt)
docs/full.json                  alle Daten zum Nachschauen (wird erzeugt)
data/state.json                 Gedächtnis zwischen den Läufen (wird erzeugt)
awtrix/scholar.be               Skript für die Uhr (Berry, AWTRIX NG)
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
5. **Uhr:** In der Weboberfläche von AWTRIX NG den Inhalt von `awtrix/scholar.be` in den
   Skript-Editor einfügen und speichern. Die Adresse der `clock.json` lässt sich dort in den
   App-Einstellungen ändern.

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
- Scholar kürzt lange Titel im Profil. Für neue Publikationen lädt die Action den vollen Titel nach.
- Scholar-Zahlen können sinken, wenn Google Einträge zusammenführt. Gemeldet werden nur Zuwächse.
- „Zitiert in“ kommt aus OpenAlex, nicht aus Scholar. Die Titel passen deshalb nicht immer genau zu den
  Zitationen, die Scholar zählt.
