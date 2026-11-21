# @name Scholar
# @description Google-Scholar-Zitationen, h-Index und Neuigkeiten
# @config url text "Adresse der clock.json" default="https://gist.githubusercontent.com/BenKnst/442b1a85615c2f88cb485fd3803e39f0/raw/clock.json"
# @config sound bool "Ton bei Party (nicht 22-7 Uhr)" default=true
# @config party_icon text "Party-Icon (Name, optional)" default="" help="Z. B. ein Konfetti-Icon aus dem AWTRIX Hub"
# @config icons text "Icons (Namen, mit Komma getrennt)" default="" help="Werden zufällig vor der Zitationszahl gezeigt. Leer = goldene Anführungszeichen."
# @config intro bool "Kurz CITATIONS einblenden" default=true
#
# ENTWURF fuer AWTRIX NG (Ulanzi TC001, 8 x 32 Pixel).
# Holt alle 30 Minuten die clock.json aus dem Gist und zeigt nacheinander:
#   1. Kurz "CITATIONS" als Laufschrift, dann goldene Anfuehrungszeichen + Zitationen in Weiss
#      (+ Zuwachs in Gruen), unterste Zeile: Fortschritt bis zum naechsten h-Index
#   2. Laufschrift: h-index und wie viele Zitationen bis zum naechsten fehlen
#   3. Laufschrift: Paper im laufenden Jahr (und im Vorjahr)
#   4. Balken: Zitationen pro Monat (sobald 3 Monate aufgezeichnet sind), sonst pro Jahr
#   5. Laufschrift: Neuigkeiten (neue Publikation, neue Zitationen, Nachricht)
# Party: kleine bei neuen Zitationen, grosse bei neuem Paper, h-Index oder Meilenstein.
# Sie bleibt stehen, bis jemand die mittlere Taste drueckt. Nachts (22-7 Uhr) ohne Ton.

import json

class Scholar
  var d, ticks, busy, pages, page, page_start, cur_icon, intro_done

  static GOLD  = 0xFFC800
  static WHITE = 0xFFFFFF
  static GREEN = 0x00FF66
  static BLUE  = 0x66CCFF
  static PINK  = 0xFF66CC
  static GREY  = 0x808080
  static RED   = 0xFF0000
  static BAR_OFF = 0x303030    # Fortschrittsbalken: noch nicht erreicht
  static INTRO_MAX_MS = 5000   # "CITATIONS" spaetestens nach 5 s fertig
  static STATIC_MS = 5000      # Anzeigedauer der festen Seiten
  static SCROLL_MAX_MS = 40000 # Laufschrift spaetestens nach 40 s weiter
  static STALE_S = 172800      # Daten aelter als 2 Tage -> roter Punkt

  # Goldene Anfuehrungszeichen, 5 x 3 Pixel (Zeilen 1-3)
  static QUOTE = [[0,1],[1,1],[3,1],[4,1],[0,2],[1,2],[3,2],[4,2],[1,3],[4,3]]

  def init()
    self.d = nil
    self.ticks = 3
    self.busy = false
    self.pages = []
    self.page = 0
    self.page_start = 0
    self.cur_icon = nil
    self.intro_done = false
  end

  # ------------------------------------------------------------ Daten holen
  def loop()
    self.ticks -= 1
    if self.ticks > 0 || self.busy
      return
    end
    self.ticks = 1800   # ca. alle 30 Minuten (loop laeuft etwa 1x pro Sekunde)
    var url = store.get("url", "https://gist.githubusercontent.com/BenKnst/442b1a85615c2f88cb485fd3803e39f0/raw/clock.json")
    self.busy = true
    var id = http.get(url, / body, status -> self.on_body(body, status), {"timeout": 20})
    if id == nil
      self.busy = false
      self.ticks = 60
    end
  end

  def on_body(body, status)
    self.busy = false
    if body == nil || status != 200
      self.ticks = 300   # Fehler: in 5 Minuten nochmal
      log("Scholar: Abruf fehlgeschlagen, Status " + str(status))
      return
    end
    var data = json.load(body)
    if !isinstance(data, map)
      log("Scholar: Antwort ist kein JSON")
      return
    end
    self.d = data
    self.build_pages()
    self.celebrate()
  end

  def get(key, default)
    if self.d == nil
      return default
    end
    var v = self.d.find(key)
    return v == nil ? default : v
  end

  # ------------------------------------------------------------ Seiten
  def build_pages()
    var p = []
    p.push({"kind": "cites"})
    var need = self.get("h_need", nil)
    var txt = "h-index " + str(self.get("h", "?"))
    if need != nil
      txt += "  ·  " + str(need) + " more to h" + str(self.get("h_next", "?"))
    end
    p.push({"kind": "scroll", "text": txt, "color": self.GOLD})
    var p12 = self.get("p12", nil)
    var py = self.get("py", nil)
    if p12 != nil
      p.push({"kind": "scroll", "color": self.GREEN,
              "text": str(p12) + (p12 == 1 ? " paper" : " papers") + " in the last 12 months"})
    elif py != nil
      var yn = self.get("y_now", 0)
      var pt = str(py) + (py == 1 ? " paper in " : " papers in ") + str(yn)
      var pp = self.get("py_prev", nil)
      if pp != nil
        pt += "  ·  " + str(pp) + " in " + str(yn - 1)
      end
      p.push({"kind": "scroll", "text": pt, "color": self.GREEN})
    end
    var months = self.get("months", [])
    var years = self.get("years", [])
    if isinstance(months, list) && months.size() >= 3
      p.push({"kind": "chart", "values": months})
    elif isinstance(years, list) && years.size() > 1
      p.push({"kind": "chart", "values": years})
    end
    var ticker = self.get("ticker", [])
    if isinstance(ticker, list)
      for t: ticker
        if isinstance(t, map) && t.find("t") != nil
          p.push({"kind": "scroll", "text": t["t"], "color": self.color_for(t.find("c"))})
        end
      end
    end
    self.pages = p
    if self.page >= p.size()
      self.page = 0
    end
  end

  def color_for(c)
    if c == "neu"
      return self.GREEN
    elif c == "zitiert" || c == "zitiert_in"
      return self.BLUE
    elif c == "msg"
      return self.PINK
    end
    return self.WHITE
  end

  def celebrate()
    var c = self.get("celebrate", nil)
    if !isinstance(c, map)
      return
    end
    var cid = c.find("id")
    if cid == nil || store.get("feier", "") == cid
      return
    end
    store.set("feier", cid)
    var big = c.find("lvl") == "big"
    # bleibt stehen, bis die mittlere Taste gedrueckt wird
    var spec = {"text": c.find("t"), "textColor": "#FFC800", "hold": true, "wakeup": true}
    var pi = store.get("party_icon", "")
    if pi != nil && pi != ""
      spec["icon"] = pi
    end
    var h = hour()
    var quiet = h >= 0 && (h >= 22 || h < 7)   # -1 = Uhrzeit noch unbekannt -> Ton erlaubt
    if store.get("sound", true) && !quiet
      if big
        spec["sound"] = {"rtttl": "fanfare:d=8,o=6,b=180:c,e,g,4c7,p,g,2c7"}
      else
        spec["sound"] = {"rtttl": "yay:d=16,o=6,b=200:c,e,g,8c7"}
      end
    end
    notify(spec)
  end

  # ------------------------------------------------------------ Rotation
  def should_show()
    return self.d != nil
  end

  def on_show()
    self.page = 0
    self.page_start = now_ms()
    self.intro_done = !store.get("intro", true)
    self.pick_icon()
  end

  # Waehlt bei jedem Erscheinen zufaellig ein Icon aus der Einstellung "icons"
  def pick_icon()
    self.cur_icon = nil
    var raw = store.get("icons", "")
    if raw == nil || raw == ""
      return
    end
    import string
    var names = []
    for part: string.split(raw, ",")
      var n = ""
      for i: 0 .. size(part) - 1
        if part[i] != " "
          n += part[i]
        end
      end
      if n != ""
        names.push(n)
      end
    end
    if names.size() > 0
      self.cur_icon = names[now_ms() % names.size()]
    end
  end

  def duration()
    # Gesamtzeit aller Seiten schaetzen (Laufschrift ca. 21 Pixel pro Sekunde)
    var ms = 0
    for p: self.pages
      if p["kind"] == "scroll"
        var w = text_width(p["text"])
        if w <= width()
          ms += self.STATIC_MS
        else
          var t = (w + width()) * 1000 / 21 + 1000
          ms += t < self.SCROLL_MAX_MS ? t : self.SCROLL_MAX_MS
        end
      elif p["kind"] == "cites" && store.get("intro", true)
        ms += self.STATIC_MS + 4000      # plus Laufschrift "CITATIONS"
      else
        ms += self.STATIC_MS
      end
    end
    return ms
  end

  def next_page()
    self.page += 1
    if self.page >= self.pages.size()
      self.page = 0
      self.intro_done = !store.get("intro", true)
    end
    self.page_start = now_ms()
  end

  # Veraltet, wenn der letzte Abruf bei GitHub fehlschlug oder die Daten aelter als 2 Tage sind
  # (z. B. weil die Uhr kein Internet hat oder die Action nicht mehr laeuft).
  def is_stale()
    if self.get("ok", true) == false
      return true
    end
    var upd = self.get("upd", 0)
    var ms = epoch_ms()
    if upd > 0 && ms > 0
      var age_s = int(ms / 1000) - upd
      return age_s > self.STALE_S
    end
    return false
  end

  # Zahl so kuerzen, dass sie in maxw Pixel passt: 1234 bleibt, 123456 -> 123k, 1234567 -> 1.2M
  def fmt_count(n, maxw)
    var s = str(n)
    if !isinstance(n, int) || text_width(s) <= maxw
      return s
    end
    import string
    if n >= 1000000
      s = string.format("%.1fM", n / 1000000.0)
      if text_width(s) > maxw
        s = str(n / 1000000) + "M"
      end
    else
      s = string.format("%.1fk", n / 1000.0)
      if text_width(s) > maxw
        s = str(n / 1000) + "k"
      end
    end
    return s
  end

  # ------------------------------------------------------------ Zeichnen
  def draw_quote(x0)
    for q: self.QUOTE
      pixel(x0 + q[0], q[1], self.GOLD)
    end
  end

  # Unterste Zeile: Fortschritt bis zum naechsten h-Index (Prozentwert aus der clock.json)
  def draw_progress()
    var prog = self.get("h_prog", nil)
    if prog == nil
      return
    end
    var n = int(prog * width() / 100)
    for x: 0 .. width() - 1
      pixel(x, 7, x < n ? self.GOLD : self.BAR_OFF)
    end
  end

  def draw()
    clear()
    if self.pages.size() == 0
      text(1, 6, "...", self.GREY)
      return
    end
    var p = self.pages[self.page]
    var elapsed = now_ms() - self.page_start
    var k = p["kind"]

    if k == "cites" && !self.intro_done
      # Variante C1: erst kurz "CITATIONS" als Laufschrift
      var runs = scroll_text(0, 6, width(), "CITATIONS", self.GOLD,
                             {"mode": "wrap", "entry": "offscreen", "speed": 100})
      if runs >= 1 || elapsed > self.INTRO_MAX_MS
        self.intro_done = true
        self.page_start = now_ms()
      end

    elif k == "cites"
      # Variante A: Anfuehrungszeichen (oder Icon aus der Liste) + Zahl + Fortschritt
      var x0 = 7                          # Textbeginn rechts von den Anfuehrungszeichen
      if self.cur_icon == nil || icon(self.cur_icon, 0, 0) == false
        self.draw_quote(0)
      else
        x0 = 9                            # rechts vom 8 Pixel breiten Icon
      end
      var num = self.fmt_count(self.get("cites", 0), width() - x0)
      var delta = self.get("delta", 0)
      var ds = delta > 0 ? "+" + str(delta) : ""
      var both_fit = ds == "" || x0 + text_width(num) + 1 + text_width(ds) <= width()
      if both_fit
        var x = x0 + text(x0, 6, num, self.WHITE)
        if ds != ""
          text(x + 1, 6, ds, self.GREEN)
        end
      elif elapsed < self.STATIC_MS / 2
        text(x0, 6, num, self.WHITE)          # erst die Zahl ...
      else
        text(x0, 6, ds, self.GREEN)           # ... dann der Zuwachs
      end
      self.draw_progress()
      if self.is_stale()
        pixel(width() - 1, 0, self.RED)   # roter Punkt: Daten sind veraltet
      end
      if elapsed > self.STATIC_MS
        self.next_page()
      end

    elif k == "chart"
      bar_chart(p["values"], self.BLUE, true)
      if elapsed > self.STATIC_MS
        self.next_page()
      end

    elif k == "scroll"
      var w = text_width(p["text"])
      if w <= width()
        text(0, 6, p["text"], p["color"])
        if elapsed > self.STATIC_MS
          self.next_page()
        end
      else
        var runs = scroll_text(0, 6, width(), p["text"], p["color"],
                               {"mode": "wrap", "entry": "offscreen", "speed": 100})
        if runs >= 1 || elapsed > self.SCROLL_MAX_MS
          self.next_page()
        end
      end
    end
  end
end

return Scholar()
