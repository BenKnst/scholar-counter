#!/usr/bin/env python3
"""
Kopiert docs/clock.json in ein (Secret) Gist, damit die Uhr sie ohne Anmeldung lesen kann,
waehrend das Repository privat bleibt.

Benoetigt zwei Repository-Secrets:
  GIST_ID     die ID des Gists (letzter Teil der Gist-Adresse)
  GIST_TOKEN  ein Token mit der Berechtigung "gist"

Die Uhr liest dann:
  https://gist.githubusercontent.com/<Benutzer>/<GIST_ID>/raw/clock.json
"""

import os
import sys
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent.parent
CLOCK = ROOT / "docs" / "clock.json"


def main():
    gist_id = os.environ.get("GIST_ID", "").strip()
    token = os.environ.get("GIST_TOKEN", "").strip()
    if not gist_id or not token:
        print("Kein GIST_ID/GIST_TOKEN hinterlegt, Gist wird nicht aktualisiert.")
        return 0
    if not CLOCK.exists():
        print("docs/clock.json gibt es noch nicht, nichts zu kopieren.")
        return 0

    content = CLOCK.read_text(encoding="utf-8")
    r = requests.patch(
        f"https://api.github.com/gists/{gist_id}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        json={"files": {"clock.json": {"content": content}}},
        timeout=30,
    )
    if r.status_code != 200:
        print(f"FEHLER beim Gist-Update: HTTP {r.status_code}: {r.text[:300]}")
        if r.status_code == 401:
            print("-> Token ungueltig oder abgelaufen.")
        elif r.status_code == 404:
            print("-> Gist-ID falsch, oder dem Token fehlt die Berechtigung 'gist'.")
        return 1
    raw = r.json().get("files", {}).get("clock.json", {}).get("raw_url", "")
    owner = r.json().get("owner", {}).get("login", "<Benutzer>")
    print(f"Gist aktualisiert ({len(content)} Bytes).")
    print(f"Adresse fuer die Uhr: https://gist.githubusercontent.com/{owner}/{gist_id}/raw/clock.json")
    if raw:
        print(f"(Diese Version: {raw})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
