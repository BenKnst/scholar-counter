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


def h_progress(cites: list) -> int:
    """Fortschritt zum naechsten h-Index in Prozent: Anteil der benoetigten Zitationen
    (die h+1 staerksten Paper brauchen je h+1), die schon erreicht sind."""
    s = sorted(cites, reverse=True)
    target = h_index(s) + 1
    top = s[:target] + [0] * max(0, target - len(s))
    have = sum(min(c, target) for c in top)
    return int(100 * have / (target * target))


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


def _cites_id(cb: dict):
    """ID fuer die 'Zitiert von'-Suche: direkt oder aus dem Link (…cites=123…)."""
    if cb.get("cites_id"):
        return str(cb["cites_id"])
    m = re.search(r"cites=([0-9,]+)", cb.get("link") or cb.get("serpapi_link") or "")
    return m.group(1) if m else None


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
            "cites_id": _cites_id(a.get("cited_by") or {}),
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


# Uhrzeiten (UTC) der geplanten Laeufe, muss zum cron in update.yml passen ("17 6-21/3 * * *")
RUN_HOURS_UTC = [6, 9, 12, 15, 18, 21]
SAVER_HOURS_UTC = [6, 15]   # im Sparmodus nur diese Laeufe (7 und 16 Uhr Winterzeit)
EXTRA_RESERVE = 5           # Extras (Titel, Neu-Check) nur, wenn so viele Anfragen uebrig bleiben


def serpapi_budget(api_key: str):
    """Restkontingent laut SerpApi-Account-API (kostet keine Anfrage). None, wenn unbekannt."""
    import requests
    try:
        r = requests.get("https://serpapi.com/account.json", params={"api_key": api_key}, timeout=30)
        d = r.json()
        left = d.get("plan_searches_left", d.get("total_searches_left"))
        return None if left is None else int(left)
    except Exception as e:
        print(f"Hinweis: Kontingent nicht abrufbar ({e}), mache normal weiter")
        return None


def runs_left_in_month(now: dt.datetime) -> int:
    """Wie viele geplante Laeufe es von jetzt (inklusive) bis Monatsende noch gibt."""
    count, day = 0, now.date()
    while day.month == now.month:
        for h in RUN_HOURS_UTC:
            slot = dt.datetime(day.year, day.month, day.day, h, 0, tzinfo=dt.timezone.utc)
            if slot >= now.replace(minute=0, second=0, microsecond=0):
                count += 1
        day += dt.timedelta(days=1)
    return count


def budget_plan(left, now: dt.datetime) -> dict:
    """Entscheidet anhand des Restkontingents, ob und wie dieser Lauf abfragt."""
    if left is None:
        return {"run": True, "extras": True, "grund": "Kontingent unbekannt"}
    runs = runs_left_in_month(now)
    if left < 1:
        return {"run": False, "extras": False, "grund": f"Kontingent aufgebraucht ({left} übrig)"}
    if left < runs:   # reicht nicht mehr fuer jeden Lauf -> nur noch 2x taeglich
        on = now.hour in SAVER_HOURS_UTC
        return {"run": on, "extras": False,
                "grund": f"Sparmodus: {left} Anfragen für {runs} Läufe übrig"}
    return {"run": True, "extras": left >= runs + EXTRA_RESERVE,
            "grund": f"{left} Anfragen für {runs} Läufe übrig"}


def fetch_serpapi(scholar_id: str, api_key: str, known_ids: set,
                  extras: bool = True, check_newest: bool = False) -> dict:
    """Scholar-Profil ueber SerpApi (kostenlos: 250 Anfragen/Monat).

    Grundsaetzlich genau 1 Anfrage: die 100 meistzitierten Paper samt Gesamtzahlen.
    Hat das Profil mehr als 100 Paper, kommen neue (meist noch unzitierte) Paper in dieser
    Liste nicht vor. Dann fragt check_newest einmal taeglich zusaetzlich die 20 neuesten ab.
    """
    import requests

    url = "https://serpapi.com/search.json"
    base = {"engine": "google_scholar_author", "author_id": scholar_id,
            "hl": "en", "num": 100, "api_key": api_key}
    r = requests.get(url, params=base, timeout=60)
    first = r.json()
    if r.status_code != 200 or first.get("error"):
        raise RuntimeError(f"SerpApi: {first.get('error') or r.status_code}")
    articles = list(first.get("articles", []))
    full_page = len(articles) >= 100
    newest_checked = False
    if full_page and check_newest and extras:
        try:
            r2 = requests.get(url, params={**base, "num": 20, "sort": "pubdate"}, timeout=60)
            seen = {a.get("citation_id") for a in articles}
            articles += [a for a in r2.json().get("articles", []) if a.get("citation_id") not in seen]
            newest_checked = True
        except Exception as e:
            print(f"Hinweis: neueste Paper nicht abrufbar ({e})")
    prof = parse_serpapi({**first, "articles": articles})
    prof["_mehr_als_100"] = full_page
    prof["_neueste_geprueft"] = newest_checked

    # Gekuerzte Titel neuer Paper nachladen (1 Anfrage je neuem Paper, kommt selten vor)
    if known_ids and extras:
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


def fetch_pub_date(api_key: str, citation_id: str):
    """Erscheinungsdatum eines Papers von seiner Scholar-Detailseite (1 Anfrage).
    Rueckgabe "JJJJ-MM-TT", "JJJJ-MM", "JJJJ" oder None."""
    import requests
    r = requests.get("https://serpapi.com/search.json", timeout=60, params={
        "engine": "google_scholar_author", "view_op": "view_citation",
        "citation_id": citation_id, "hl": "en", "api_key": api_key})
    c = (r.json() or {}).get("citation") or {}
    raw = c.get("publication_date") or next((v for k, v in c.items() if "date" in k and isinstance(v, str)), "")
    parts = [x for x in re.split(r"[/.-]", str(raw).strip()) if x.isdigit()]
    if not parts or len(parts[0]) != 4:
        return None
    return "-".join([parts[0]] + [x.zfill(2) for x in parts[1:3]])


def _first_author_year(summary: str) -> tuple:
    """'M Müller, A Smith - Journal, 2026 - Verlag' -> ('Müller et al.', '2026')"""
    summary = clean_title(summary or "", 300)
    authors = summary.split(" - ")[0]
    names = [a.strip() for a in authors.split(",") if a.strip() and "..." not in a]
    who = names[0].split()[-1] if names else ""
    if len(names) > 1 or "..." in authors:
        who += " et al."
    years = re.findall(r"\b(19\d\d|20\d\d)\b", summary)
    return who.strip(), (years[-1] if years else "")


def fetch_citing_scholar(api_key: str, cites_id: str, seen: set, n: int = 10) -> list:
    """Paper, die ein bestimmtes Paper zitieren, direkt aus Scholar (1 Anfrage).
    Neueste zuerst (scisbd), nur noch nicht gemeldete."""
    import requests
    r = requests.get("https://serpapi.com/search.json", timeout=60, params={
        "engine": "google_scholar", "cites": cites_id, "scisbd": 2, "num": n,
        "hl": "en", "api_key": api_key})
    out = []
    for res in (r.json() or {}).get("organic_results", []):
        rid = res.get("result_id")
        if not rid or rid in seen:
            continue
        who, year = _first_author_year((res.get("publication_info") or {}).get("summary", ""))
        out.append({"id": rid, "titel": res.get("title") or "", "wer": who, "jahr": year})
    return out


def cited_by_text(citing: dict, own_title: str, extra: int) -> str:
    """Variante C: 'Cited by Müller et al. 2026: "Zitierendes…" -> "Eigenes…"'"""
    head = "Cited by " + " ".join(x for x in (citing.get("wer"), citing.get("jahr")) if x)
    txt = f'{head}: "{clean_title(citing["titel"], 60)}" -> "{clean_title(own_title, 50)}"'
    if extra > 0:
        txt += f" (+{extra} more)"
    return txt


def papers_last_12_months(pubs: dict, pubdates: dict, now: dt.datetime) -> int:
    """Paper der letzten 12 Monate. Genaues Datum, wo bekannt; sonst nur das laufende Jahr."""
    cutoff = (now - dt.timedelta(days=365)).date().isoformat()
    count = 0
    for pid, p in pubs.items():
        d = pubdates.get(pid)
        if d and len(d) >= 7:                      # Monat bekannt
            if (d if len(d) == 10 else d + "-28") >= cutoff:
                count += 1
        elif str(p.get("jahr") or "") == str(now.year):
            count += 1                              # nur Jahr bekannt: laufendes Jahr zaehlt
    return count


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

def monthly_gains(daily: dict, now: dt.datetime, keep: int = 12) -> tuple:
    """Zitationszuwachs je Kalendermonat aus den gespeicherten Tageswerten.
    Scholar selbst liefert nur Jahreswerte; diese Monatsreihe waechst deshalb erst ab Start
    der Aufzeichnung. Rueckgabe: (erster Monat "JJJJ-MM" oder None, [Zuwaechse])."""
    if not daily:
        return None, []
    by_month = {}
    for day, total in sorted(daily.items()):
        by_month.setdefault(day[:7], []).append(total)
    months = sorted(by_month)
    gains, prev_end = [], None
    for m in months:
        vals = by_month[m]
        start = prev_end if prev_end is not None else vals[0]
        gains.append(max(0, vals[-1] - start))
        prev_end = vals[-1]
    months, gains = months[-keep:], gains[-keep:]
    return months[0], gains


def merged_pubs_preview(old_pubs: dict, pubs: dict) -> dict:
    merged = dict(old_pubs)
    merged.update({pid: {"titel": p["titel"], "zitationen": p["zitationen"], "jahr": p.get("jahr")}
                   for pid, p in pubs.items()})
    return merged


def papers_per_year(pubs: dict, now: dt.datetime) -> dict:
    """Anzahl Paper im laufenden und im Vorjahr (Scholar kennt nur das Jahr, keinen Monat)."""
    years = [str(p.get("jahr") or "") for p in pubs.values()]
    return {"this_year": years.count(str(now.year)), "prev_year": years.count(str(now.year - 1))}


def update(cfg: dict, state: dict, prof: dict, citing: list, now: dt.datetime,
           citing_by_pub: dict = None, pubdates: dict = None) -> tuple:
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
        # 1) neue Publikationen (+ grosse Party)
        for pid, p in pubs.items():
            if pid not in old_pubs:
                add_event("neu", "New paper: " + clean_title(p["titel"]),
                          cfg.get("new_publication_hours", 24))
                add_event("feier", "New paper!", cfg.get("celebration_hours", 48), key=f"n{pid}")
        # 2) neue Zitationen je Paper (nur Zuwachs, Rueckgaenge ignorieren)
        for pid, p in pubs.items():
            old = old_pubs.get(pid)
            if old and p["zitationen"] > old["zitationen"]:
                d = p["zitationen"] - old["zitationen"]
                cb = (citing_by_pub or {}).get(pid)
                if cb:
                    add_event("zitiert_in", cited_by_text(cb, p["titel"], d - 1),
                              cfg.get("new_citation_hours", 48))
                else:
                    add_event("zitiert", f"+{d} citation{'s' if d > 1 else ''}: " + clean_title(p["titel"]),
                              cfg.get("new_citation_hours", 48))
        # 2b) kleine Party fuer jeden Lauf mit neuen Zitationen
        inc = total - state.get("zitationen", total)
        if inc > 0:
            add_event("party", f"+{inc} citation{'s' if inc > 1 else ''}!",
                      cfg.get("celebration_hours", 48), key=f"z{iso(now)}")

        # 3) h-Index gestiegen
        old_h = state.get("h_index")
        if old_h is not None and h > old_h:
            add_event("feier", f"h-index {h}!", cfg.get("celebration_hours", 48), key=f"h{h}")
        # 4) Meilensteine bei den Gesamtzitationen
        old_total = state.get("zitationen", total)
        for m in cfg.get("citation_milestones", []):
            if old_total < m <= total:
                add_event("feier", f"{m:,} citations!", cfg.get("celebration_hours", 48), key=f"c{m}")

    # 5) zitierende Arbeiten aus OpenAlex
    seen_citing = set(state.get("openalex_seen", []))
    if citing:
        if seen_citing:  # beim ersten OpenAlex-Lauf nur merken, nicht melden
            for w in citing:
                if w["id"] not in seen_citing:
                    add_event("zitiert_in", "Cited in: " + clean_title(w["titel"]),
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
    for e in sorted((e for e in active if e["typ"] not in ("feier", "party")),
                    key=lambda e: e["zeit"], reverse=True):
        if len(ticker) >= TICKER_MAX:
            break
        ticker.append({"t": e["text"], "c": e["typ"]})

    # Party: das neueste Ereignis; bei gleichem Zeitpunkt gewinnt die grosse Party
    celebrate = None
    feiern = sorted((e for e in active if e["typ"] in ("feier", "party")),
                    key=lambda e: (e["zeit"], e["typ"] == "feier"))
    if feiern:
        e = feiern[-1]
        celebrate = {"id": e["key"], "t": e["text"], "lvl": "big" if e["typ"] == "feier" else "small"}

    years = sorted(prof.get("pro_jahr", {}).items())[-16:]
    h_next, h_need = h_countdown(cites_list)

    months_from, months = monthly_gains(daily, now)
    papers = papers_per_year(merged_pubs_preview(old_pubs, pubs), now)

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
        "h_prog": h_progress(cites_list),
        "y0": int(years[0][0]) if years else None,
        "years": [v for _, v in years],
        "ticker": ticker,
        "m0": months_from,          # erster Monat der Monatsbalken, z. B. "2026-11"
        "months": months,           # Zitationszuwachs je Monat (aus eigenen Tageswerten)
        "py": papers["this_year"],  # Paper im laufenden Jahr
        "py_prev": papers["prev_year"],
        "p12": papers_last_12_months(merged_pubs_preview(old_pubs, pubs), pubdates or {}, now),
        "y_now": now.year,
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

    # Bekannte Paper behalten, auch wenn sie in diesem Lauf nicht abgefragt wurden
    # (bei mehr als 100 Papern kommen nur die 100 meistzitierten mit).
    merged_pubs = dict(old_pubs)
    merged_pubs.update({pid: {"titel": p["titel"], "zitationen": p["zitationen"], "jahr": p.get("jahr")}
                        for pid, p in pubs.items()})
    new_state = {
        "scholar_id": cfg.get("scholar_id"),
        "pubs": merged_pubs,
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
    ap.add_argument("--citing-by-fixture", help="'Cited by'-Treffer je Paper-ID aus Datei (Test)")
    ap.add_argument("--citing-fixture", help="OpenAlex-Ergebnis aus JSON-Datei (Test)")
    ap.add_argument("--now", help="Zeitpunkt vorgeben, z. B. 2026-11-18T05:00:00Z (Test)")
    args = ap.parse_args()

    cfg = load_json(CONFIG, {})
    state = load_json(STATE, {})
    now = parse_iso(args.now) if args.now else dt.datetime.now(dt.timezone.utc).replace(microsecond=0)

    # Wurde in config.json ein anderes Profil eingetragen? Dann altes Gedaechtnis verwerfen,
    # sonst gaelten alle Paper des neuen Profils als "neu". Paper-IDs beginnen mit der Scholar-ID.
    sid = cfg.get("scholar_id", "")
    old_ids = list(state.get("pubs", {}))
    if old_ids and (state.get("scholar_id", sid) != sid
                    or not any(i.startswith(sid + ":") for i in old_ids)):
        print(f"Neues Scholar-Profil ({sid}): Ausgangsstand wird neu angelegt.")
        state = {}

    # --- Scholar
    serpapi_key = os.environ.get("SERPAPI_KEY", "").strip()
    plan = {"run": True, "extras": True}
    try:
        known = set(state.get("pubs", {}))
        if args.fixture:
            prof = load_json(Path(args.fixture), None)
        elif args.serpapi_fixture:
            prof = parse_serpapi(load_json(Path(args.serpapi_fixture), {}))
        elif serpapi_key:
            plan = budget_plan(serpapi_budget(serpapi_key), now)
            print(f"Quelle: SerpApi ({plan['grund']})")
            if not plan["run"]:
                print("Lauf ausgelassen, um das Monatskontingent zu schonen. Anzeige bleibt unverändert.")
                save_json(ROOT / "data" / "status.json",
                          {"ok": True, "ausgelassen": plan["grund"], "zeit": iso(now)})
                sys.exit(0)
            check_newest = state.get("neueste_geprueft") != now.date().isoformat()
            prof = fetch_serpapi(sid, serpapi_key, known,
                                 extras=plan["extras"], check_newest=check_newest)
            if prof.get("_mehr_als_100"):
                print("Hinweis: Profil hat mehr als 100 Paper, abgefragt werden die 100 meistzitierten"
                      + (" + die 20 neuesten" if prof.get("_neueste_geprueft") else ""))
        else:
            print("Quelle: Google Scholar direkt (scholarly)")
            prof = fetch_scholar(cfg["scholar_id"], known)
        if not prof or not prof.get("publikationen"):
            raise RuntimeError("leeres Profil erhalten")
        # Plausibilitaetspruefung: Ein starker Einbruch ist fast immer ein Abruffehler.
        old_total = state.get("zitationen")
        new_total = prof.get("zitationen") or 0
        if old_total and (new_total == 0 or new_total < old_total * 0.7):
            raise RuntimeError(f"unplausible Zahlen: {new_total} statt bisher {old_total} "
                               "Zitationen, alte Anzeige bleibt stehen")
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

    # --- Extras ueber SerpApi (nur mit genug Kontingent-Reserve)
    pubdates = dict(state.get("pubdates", {}))
    seen_cb = set(state.get("scholar_citing_seen", []))
    citing_by_pub = {}
    if args.citing_by_fixture:
        citing_by_pub = load_json(Path(args.citing_by_fixture), {})
    if serpapi_key and plan["extras"] and not args.fixture and not args.serpapi_fixture:
        # a) Erscheinungsdaten fuer Paper aus diesem und letztem Jahr (einmalig, max. 5 pro Lauf)
        todo = [p for p in prof["publikationen"]
                if p.get("id") and p["id"] not in pubdates
                and str(p.get("jahr") or "") in (str(now.year), str(now.year - 1))][:5]
        for p in todo:
            try:
                pubdates[p["id"]] = fetch_pub_date(serpapi_key, p["id"]) or str(p.get("jahr") or "")
            except Exception as e:
                print(f"Hinweis: Datum fuer {p['id']} nicht abrufbar ({e})")
        # b) Wer hat zitiert? Nur fuer Paper mit neuen Zitationen, max. 3 pro Lauf
        old_pubs = state.get("pubs", {})
        gestiegen = sorted(
            (p for p in prof["publikationen"]
             if p.get("id") in old_pubs and p.get("cites_id")
             and p["zitationen"] > old_pubs[p["id"]].get("zitationen", 0)),
            key=lambda p: p["zitationen"] - old_pubs[p["id"]].get("zitationen", 0), reverse=True)[:3]
        for p in gestiegen:
            try:
                found = fetch_citing_scholar(serpapi_key, p["cites_id"], seen_cb)
                if found:
                    citing_by_pub[p["id"]] = found[0]
                    seen_cb |= {f["id"] for f in found}
            except Exception as e:
                print(f"Hinweis: zitierende Paper nicht abrufbar ({e})")
        # Beim allerersten Lauf eines Profils nichts melden, nur merken
        if not state.get("pubs"):
            citing_by_pub = {}

    newest_flag = state.get("neueste_geprueft")
    state, clock, full = update(cfg, state, prof, citing, now,
                                citing_by_pub=citing_by_pub, pubdates=pubdates)
    state["pubdates"] = pubdates
    state["scholar_citing_seen"] = sorted(seen_cb)[-1000:]
    state["neueste_geprueft"] = now.date().isoformat() if prof.get("_neueste_geprueft") else newest_flag
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
