#!/usr/bin/env python3
"""
Holt das Google-Scholar-Profil, vergleicht es mit dem letzten Stand und schreibt

  docs/clock.json   kleine Datei fuer die Uhr (AWTRIX NG, max. 8 KB)
  docs/full.json    alle Daten (Paperliste, Verlauf) zum Nachschauen
  data/state.json   Gedaechtnis fuer den naechsten Lauf (bekannte Paper, Ereignisse)

Datenquelle:
  Ist die Umgebungsvariable SERPAPI_KEY gesetzt, kommt das Profil ueber SerpApi
  (kostenloser Tarif: 250 Anfragen im Monat, ein Lauf braucht meist 1).
  Sonst wird Google Scholar direkt abgefragt (scholarly). Das klappt vom eigenen
  Rechner aus, wird aber von Google bei GitHub-Servern meist blockiert.

Aufruf:
  python scripts/update.py                       normaler Lauf (Scholar + optional OpenAlex)
  python scripts/update.py --fixture prof.json   ohne Netz, Profil aus Datei (zum Testen)
  python scripts/update.py --now 2026-11-18T05:00:00Z   Uhrzeit vorgeben (zum Testen)
"""

import argparse
import datetime as dt
import json
import os
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config.json"
STATE = ROOT / "data" / "state.json"
CLOCK = ROOT / "docs" / "clock.json"
FULL = ROOT / "docs" / "full.json"

TICKER_MAX = 6          # so viele Laufschrift-Meldungen hoechstens gleichzeitig
TITLE_MAX = 140         # Titel fuer die Uhr kuerzen (Speicher + Lesbarkeit)
EVENT_KEEP_DAYS = 60    # Ereignisse so lange in full.json behalten


# ---------------------------------------------------------------- Hilfsfunktionen

def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default


def save_json(path: Path, data, compact=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    if compact:
        text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    else:
        text = json.dumps(data, ensure_ascii=False, indent=2)
    path.write_text(text + "\n", encoding="utf-8")


def iso(t: dt.datetime) -> str:
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s: str) -> dt.datetime:
    return dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)


_REPL = {
    "‘": "'", "’": "'", "‚": "'", "‛": "'",
    "“": '"', "”": '"', "„": '"', "«": '"', "»": '"',
    "–": "-", "—": "-", "−": "-", "‐": "-", "‑": "-",
    "…": "...", " ": " ", " ": " ", " ": " ",
}


def clean_title(title: str, limit: int = TITLE_MAX) -> str:
    """Titel fuer die Pixelanzeige aufraeumen: typografische Zeichen ersetzen,
    Leerzeichen normalisieren, Zeichen ausserhalb der Uhr-Schrift entfernen."""
    if not title:
        return ""
    t = unicodedata.normalize("NFC", title)
    for a, b in _REPL.items():
        t = t.replace(a, b)
    # Zeichen, die die Uhr nicht kennt (Emoji, Symbole), weglassen
    t = "".join(ch for ch in t if ord(ch) < 0x0590 or ch.isspace())
    t = re.sub(r"\s+", " ", t).strip()
    t = re.sub(r'^(["\']) +', r"\1", t)          # '" Dinner' -> '"Dinner'
    t = re.sub(r' +(["\'])$', r"\1", t)
    if len(t) > limit:
        t = t[: limit - 3].rstrip() + "..."
    return t


def h_index(cites: list) -> int:
    s = sorted(cites, reverse=True)
    return sum(1 for i, c in enumerate(s) if c >= i + 1)


def h_countdown(cites: list) -> tuple:
    """(naechster h-Index, fehlende Zitationen)"""
    s = sorted(cites, reverse=True)
    h = h_index(s)
    target = h + 1
    top = s[:target] + [0] * max(0, target - len(s))
    return target, sum(max(0, target - c) for c in top)


# ---------------------------------------------------------------- Datenquellen

def fetch_scholar(scholar_id: str, known_ids: set) -> dict:
    from scholarly import scholarly

    author = scholarly.search_author_id(scholar_id)
    author = scholarly.fill(author, sections=["basics", "indices", "counts", "publications"])
    pubs = []
    for p in author.get("publications", []):
        bib = p.get("bib", {})
        entry = {
            "id": p.get("author_pub_id"),
            "titel": bib.get("title") or "",
            "jahr": bib.get("pub_year"),
            "zitationen": p.get("num_citations", 0) or 0,
        }
        # Nur fuer NEUE Paper den vollstaendigen Titel nachladen (1 Anfrage je Paper).
        # Beim allerersten Lauf (known_ids leer) nicht, sonst waeren es zu viele Anfragen.
        if known_ids and entry["id"] not in known_ids and entry["titel"].endswith("…"):
            try:
                full = scholarly.fill(p)
                entry["titel"] = full.get("bib", {}).get("title") or entry["titel"]
            except Exception as e:  # nicht schlimm, dann bleibt der gekuerzte Titel
                print(f"Hinweis: voller Titel nicht abrufbar ({e})")
        pubs.append(entry)
    return {
        "name": author.get("name"),
        "affiliation": author.get("affiliation"),
        "zitationen": author.get("citedby") or 0,
        "zitationen_5j": author.get("citedby5y"),
        "h_index": author.get("hindex"),
        "i10_index": author.get("i10index"),
        "pro_jahr": {str(k): v for k, v in (author.get("cites_per_year") or {}).items()},
        "publikationen": pubs,
    }


def _int(v, default=0):
    try:
        return int(str(v).replace(",", "").replace(".", "").strip())
    except (TypeError, ValueError):
        return default


def parse_serpapi(data: dict) -> dict:
    """Wandelt eine SerpApi-Antwort (engine=google_scholar_author) in unser Profilformat um."""
    author = data.get("author", {})
    table = data.get("cited_by", {}).get("table", [])

    def cell(i, key):
        # Eintraege sind {"citations": {"all": .., "since_2021": ..}}; Schluessel je nach Sprache
        if i >= len(table) or not isinstance(table[i], dict) or not table[i]:
            return None
        vals = next(iter(table[i].values()))
        if key == "all":
            return _int(vals.get("all"), None)
        others = [v for k, v in vals.items() if k != "all"]
        return _int(others[0], None) if others else None

    pubs = []
    for a in data.get("articles", []):
        pubs.append({
            "id": a.get("citation_id"),
            "titel": a.get("title") or "",
            "jahr": a.get("year") or None,
            "zitationen": _int((a.get("cited_by") or {}).get("value"), 0),
        })
    graph = data.get("cited_by", {}).get("graph", [])
    return {
        "name": author.get("name"),
        "affiliation": author.get("affiliations"),
        "zitationen": cell(0, "all") or 0,
        "zitationen_5j": cell(0, "recent"),
        "h_index": cell(1, "all"),
        "i10_index": cell(2, "all"),
        "pro_jahr": {str(g["year"]): _int(g.get("citations")) for g in graph if "year" in g},
        "publikationen": pubs,
    }


def fetch_serpapi(scholar_id: str, api_key: str, known_ids: set) -> dict:
    """Scholar-Profil ueber SerpApi (kostenlos: 250 Anfragen/Monat). Meist 1 Anfrage pro Lauf."""
    import requests

    url = "https://serpapi.com/search.json"
    base = {"engine": "google_scholar_author", "author_id": scholar_id,
            "hl": "en", "num": 100, "api_key": api_key}
    first, articles, start = None, [], 0
    while True:
        r = requests.get(url, params={**base, "start": start}, timeout=60)
        data = r.json()
        if r.status_code != 200 or data.get("error"):
            if first is None:
                raise RuntimeError(f"SerpApi: {data.get('error') or r.status_code}")
            break   # Folgeseite fehlgeschlagen: mit dem bisherigen weitermachen
        if first is None:
            first = data
        page = data.get("articles", [])
        articles += page
        if len(page) < 100 or start >= 900:   # mehr als 100 Paper -> weitere Seiten
            break
        start += 100
    prof = parse_serpapi({**first, "articles": articles})

    # Gekuerzte Titel neuer Paper nachladen (1 Anfrage je neuem Paper, kommt selten vor)
    if known_ids:
        for p in prof["publikationen"]:
            if p["id"] not in known_ids and p["titel"].endswith("…"):
                try:
                    r = requests.get(url, timeout=60, params={
                        "engine": "google_scholar_author", "view_op": "view_citation",
                        "citation_id": p["id"], "hl": "en", "api_key": api_key})
                    full = (r.json().get("citation") or {}).get("title")
                    if full:
                        p["titel"] = full
                except Exception as e:
                    print(f"Hinweis: voller Titel nicht abrufbar ({e})")
    return prof


def fetch_openalex_citing(orcid: str, n: int = 25) -> list:
    """Neueste zitierende Arbeiten laut OpenAlex: [{id, titel, datum}]"""
    import requests

    base = "https://api.openalex.org"
    headers = {"User-Agent": "scholar-counter (https://github.com)"}
    orcid = orcid.strip().split("orcid.org/")[-1]
    r = requests.get(f"{base}/authors/orcid:{orcid}", headers=headers, timeout=30)
    r.raise_for_status()
    author_id = r.json()["id"].split("/")[-1]
    r = requests.get(f"{base}/works", headers=headers, timeout=30, params={
        "filter": f"author.id:{author_id}", "per-page": 100, "select": "id"})
    r.raise_for_status()
    work_ids = [w["id"].split("/")[-1] for w in r.json().get("results", [])]
    if not work_ids:
        return []
    out = []
    # OpenAlex erlaubt bis zu 100 Werte pro OR-Filter; wir nehmen 50 pro Anfrage
    for i in range(0, len(work_ids), 50):
        r = requests.get(f"{base}/works", headers=headers, timeout=30, params={
            "filter": "cites:" + "|".join(work_ids[i:i + 50]),
            "sort": "publication_date:desc", "per-page": n,
            "select": "id,title,publication_date"})
        r.raise_for_status()
        for w in r.json().get("results", []):
            out.append({"id": w["id"].split("/")[-1], "titel": w.get("title") or "",
                        "datum": w.get("publication_date")})
    out.sort(key=lambda w: w["datum"] or "", reverse=True)
    seen, uniq = set(), []
    for w in out:
        if w["id"] not in seen:
            seen.add(w["id"])
            uniq.append(w)
    return uniq[:n]


# ---------------------------------------------------------------- Kernlogik

def update(cfg: dict, state: dict, prof: dict, citing: list, now: dt.datetime) -> tuple:
    """Vergleicht neues Profil mit altem Zustand. Gibt (state, clock, full) zurueck."""
    first_run = not state.get("pubs")
    old_pubs = state.get("pubs", {})
    events = state.get("events", [])
    today = now.date().isoformat()

    def add_event(kind, text, hours, key=None):
        ev = {"typ": kind, "text": text, "zeit": iso(now),
              "bis": iso(now + dt.timedelta(hours=hours))}
        if key:
            ev["key"] = key
        events.append(ev)
        print(f"Ereignis: {kind}: {text}")

    pubs = {p["id"]: p for p in prof["publikationen"] if p.get("id")}
    total = prof["zitationen"]
    cites_list = [p["zitationen"] for p in prof["publikationen"]]
    h = prof.get("h_index") if prof.get("h_index") is not None else h_index(cites_list)

    if not first_run:
        # 1) neue Publikationen
        for pid, p in pubs.items():
            if pid not in old_pubs:
                add_event("neu", "Neue Publikation: " + clean_title(p["titel"]),
                          cfg.get("new_publication_hours", 24))
        # 2) neue Zitationen je Paper (nur Zuwachs, Rueckgaenge ignorieren)
        for pid, p in pubs.items():
            old = old_pubs.get(pid)
            if old and p["zitationen"] > old["zitationen"]:
                d = p["zitationen"] - old["zitationen"]
                add_event("zitiert", f"+{d} für: " + clean_title(p["titel"]),
                          cfg.get("new_citation_hours", 48))
        # 3) h-Index gestiegen
        old_h = state.get("h_index")
        if old_h is not None and h > old_h:
            add_event("feier", f"h-Index {h}!", cfg.get("celebration_hours", 48), key=f"h{h}")
        # 4) Meilensteine bei den Gesamtzitationen
        old_total = state.get("zitationen", total)
        for m in cfg.get("citation_milestones", []):
            if old_total < m <= total:
                add_event("feier", f"{m} Zitationen!", cfg.get("celebration_hours", 48), key=f"c{m}")

    # 5) zitierende Arbeiten aus OpenAlex
    seen_citing = set(state.get("openalex_seen", []))
    if citing:
        if seen_citing:  # beim ersten OpenAlex-Lauf nur merken, nicht melden
            for w in citing:
                if w["id"] not in seen_citing:
                    add_event("zitiert_in", "Zitiert in: " + clean_title(w["titel"]),
                              cfg.get("new_citation_hours", 48))
        seen_citing |= {w["id"] for w in citing}

    # Tagesverlauf der Gesamtzitationen (fuer "+N seit gestern")
    daily = state.get("taeglich", {})
    daily[today] = total
    daily = dict(sorted(daily.items())[-400:])
    prev_days = [d for d in daily if d < today]
    delta = total - daily[prev_days[-1]] if prev_days else 0

    # abgelaufene Ereignisse fuer die Uhr ausfiltern, alte ganz loeschen
    keep_after = now - dt.timedelta(days=EVENT_KEEP_DAYS)
    events = [e for e in events if parse_iso(e["zeit"]) >= keep_after]
    active = [e for e in events if parse_iso(e["bis"]) > now]

    # ---- clock.json (klein halten!)
    ticker = []
    msg = (cfg.get("message") or "").strip()
    if msg:
        until = cfg.get("message_until") or ""
        if not until or until >= today:
            ticker.append({"t": clean_title(msg, 200), "c": "msg"})
    for e in sorted((e for e in active if e["typ"] != "feier"),
                    key=lambda e: e["zeit"], reverse=True):
        if len(ticker) >= TICKER_MAX:
            break
        ticker.append({"t": e["text"], "c": e["typ"]})

    celebrate = None
    feiern = sorted((e for e in active if e["typ"] == "feier"), key=lambda e: e["zeit"])
    if feiern:
        celebrate = {"id": feiern[-1]["key"], "t": feiern[-1]["text"]}

    years = sorted(prof.get("pro_jahr", {}).items())[-16:]
    h_next, h_need = h_countdown(cites_list)

    clock = {
        "v": 1,
        "upd": int(now.timestamp()),
        "ok": True,
        "cites": total,
        "delta": max(0, delta),
        "h": h,
        "i10": prof.get("i10_index"),
        "h_next": h_next,
        "h_need": h_need,
        "y0": int(years[0][0]) if years else None,
        "years": [v for _, v in years],
        "ticker": ticker,
    }
    if celebrate:
        clock["celebrate"] = celebrate

    full = {
        "aktualisiert": iso(now),
        "profil": {k: prof.get(k) for k in
                   ("name", "affiliation", "zitationen", "zitationen_5j", "h_index", "i10_index", "pro_jahr")},
        "h_countdown": {"naechster": h_next, "fehlend": h_need},
        "publikationen": sorted(prof["publikationen"], key=lambda p: -p["zitationen"]),
        "zitierend_openalex": citing[:10],
        "ereignisse": sorted(events, key=lambda e: e["zeit"], reverse=True),
    }

    new_state = {
        "pubs": {pid: {"titel": p["titel"], "zitationen": p["zitationen"]} for pid, p in pubs.items()},
        "zitationen": total,
        "h_index": h,
        "taeglich": daily,
        "events": events,
        "openalex_seen": sorted(seen_citing)[-500:],
        "letzter_erfolg": iso(now),
    }
    return new_state, clock, full


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture", help="Profil aus JSON-Datei statt Scholar (Test)")
    ap.add_argument("--serpapi-fixture", help="gespeicherte SerpApi-Antwort statt Abruf (Test)")
    ap.add_argument("--citing-fixture", help="OpenAlex-Ergebnis aus JSON-Datei (Test)")
    ap.add_argument("--now", help="Zeitpunkt vorgeben, z. B. 2026-11-18T05:00:00Z (Test)")
    args = ap.parse_args()

    cfg = load_json(CONFIG, {})
    state = load_json(STATE, {})
    now = parse_iso(args.now) if args.now else dt.datetime.now(dt.timezone.utc).replace(microsecond=0)

    # --- Scholar
    try:
        known = set(state.get("pubs", {}))
        serpapi_key = os.environ.get("SERPAPI_KEY", "").strip()
        if args.fixture:
            prof = load_json(Path(args.fixture), None)
        elif args.serpapi_fixture:
            prof = parse_serpapi(load_json(Path(args.serpapi_fixture), {}))
        elif serpapi_key:
            print("Quelle: SerpApi")
            prof = fetch_serpapi(cfg["scholar_id"], serpapi_key, known)
        else:
            print("Quelle: Google Scholar direkt (scholarly)")
            prof = fetch_scholar(cfg["scholar_id"], known)
        if not prof or not prof.get("publikationen"):
            raise RuntimeError("leeres Profil erhalten")
    except Exception as e:
        print(f"FEHLER beim Scholar-Abruf: {type(e).__name__}: {e}")
        # Alte Anzeige behalten, nur als veraltet markieren
        clock = load_json(CLOCK, None)
        if clock:
            clock["ok"] = False
            save_json(CLOCK, clock, compact=True)
        status = {"ok": False, "fehler": f"{type(e).__name__}: {e}", "zeit": iso(now)}
        save_json(ROOT / "data" / "status.json", status)
        sys.exit(0)  # der Workflow wertet status.json aus

    # --- OpenAlex (optional)
    citing = []
    try:
        if args.citing_fixture:
            citing = load_json(Path(args.citing_fixture), [])
        elif (cfg.get("orcid") or "").strip():
            citing = fetch_openalex_citing(cfg["orcid"])
    except Exception as e:
        print(f"Hinweis: OpenAlex nicht erreichbar ({e}), mache ohne weiter")

    state, clock, full = update(cfg, state, prof, citing, now)
    save_json(STATE, state)
    save_json(CLOCK, clock, compact=True)
    save_json(FULL, full)
    save_json(ROOT / "data" / "status.json", {"ok": True, "zeit": iso(now)})
    size = CLOCK.stat().st_size
    print(f"OK: {clock['cites']} Zitationen, h={clock['h']}, "
          f"{len(clock['ticker'])} Meldungen, clock.json = {size} Bytes")
    if size > 7000:
        print("WARNUNG: clock.json ist fast 8 KB gross, die Uhr koennte sie abschneiden")


if __name__ == "__main__":
    main()
