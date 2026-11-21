# @name Scholar
# @description Google-Scholar-Zitationen, h-Index und Neuigkeiten
# @config url text "Adresse der clock.json" default="https://gist.githubusercontent.com/BenKnst/442b1a85615c2f88cb485fd3803e39f0/raw/clock.json"
# @config sound bool "Ton bei Party (nicht 22-7 Uhr)" default=true
# @config party_icon text "Party-Icon (Name, optional)" default="" help="Z. B. ein Konfetti-Icon aus dem AWTRIX Hub"
# @config icons text "Icons (Namen, mit Komma getrennt)" default="" help="Werden zufällig vor der Zitationszahl gezeigt. Leer = Doktorhut."
#
# ENTWURF fuer AWTRIX NG (Ulanzi TC001, 8 x 32 Pixel).
# Holt alle 30 Minuten die clock.json aus dem Gist und zeigt nacheinander:
#   1. Weisser Grund: Icon (zufaellig aus der Liste, sonst Doktorhut) + Zitationen in Schwarz (+ Zuwachs)
#   2. Laufschrift: h-index und wie viele Zitationen bis zum naechsten fehlen
#   3. Laufschrift: Paper im laufenden Jahr (und im Vorjahr)
#   4. Balken: Zitationen pro Monat (sobald 3 Monate aufgezeichnet sind), sonst pro Jahr
#   5. Laufschrift: Neuigkeiten (neue Publikation, neue Zitationen, Nachricht)
# Party: kleine bei neuen Zitationen, grosse bei neuem Paper, h-Index oder Meilenstein.
# Sie bleibt stehen, bis jemand die mittlere Taste drueckt. Nachts (22-7 Uhr) ohne Ton.

import json

class Scholar
  var d, ticks, busy, pages, page, page_start, cur_icon

  static GOLD  = 0xFFC800
  static WHITE = 0xFFFFFF
  static GREEN = 0x00FF66
  static BLUE  = 0x66CCFF
  static PINK  = 0xFF66CC
  static GREY  = 0x808080
  static RED   = 0xFF0000
  static HAT_W = 0xFFFFFF      # Hintergrund (weiss)
  static HAT_G = 0x808080      # Hutflaeche (grau)
  static HAT_O = 0xFF7A00      # Quaste (orange)
  static BLACK = 0x000000      # Schrift auf weissem Grund (Pixel aus)
  static DARKGREEN = 0x00A000  # Zuwachs auf weissem Grund
  static STATIC_MS = 5000      # Anzeigedauer der festen Seiten
  static SCROLL_MAX_MS = 40000 # Laufschrift spaetestens nach 40 s weiter
  static STALE_S = 172800      # Daten aelter als 2 Tage -> roter Punkt

  # Doktorhut, 8 x 8 Pixel (eigener Entwurf). Zeichen: W = weiss, K = Kontur (aus),
  # G = Hutflaeche, Y = Gold, O = Quaste
  static HAT = ["WWWKKWWW",
                "WWKGGKWW",
                "WKGGGGKW",
                "KGGGGYKW",
                "WKKGGKOW",
                "WWKGGKOW",
                "WWWKKOYW",
                "WWWWWOOW"]

  def init()
    self.d = nil
    self.ticks = 3
    self.busy = false
    self.pages = []
    self.page = 0
    self.page_start = 0
    self.cur_icon = nil
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
  def draw_hat(x0)
    var y = 0
    for row: self.HAT
      for x: 0 .. size(row) - 1
        var ch = row[x]
        if ch == "W"
          pixel(x0 + x, y, self.HAT_W)
        elif ch == "K"
          pixel(x0 + x, y, self.BLACK)
        elif ch == "G"
          pixel(x0 + x, y, self.HAT_G)
        elif ch == "Y"
          pixel(x0 + x, y, self.GOLD)
        elif ch == "O"
          pixel(x0 + x, y, self.HAT_O)
        end
      end
      y += 1
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

    if k == "cites"
      clear(self.HAT_W)   # ganzes Display weiss hinterlegt
      if self.cur_icon == nil || icon(self.cur_icon, 0, 0) == false
        self.draw_hat(0)
      end
      var x0 = 9                          # Textbeginn rechts vom Hut
      var num = self.fmt_count(self.get("cites", 0), width() - x0)
      var delta = self.get("delta", 0)
      var ds = delta > 0 ? "+" + str(delta) : ""
      var both_fit = ds == "" || x0 + text_width(num) + 1 + text_width(ds) <= width()
      if both_fit
        var x = x0 + text(x0, 6, num, self.BLACK)
        if ds != ""
          text(x + 1, 6, ds, self.DARKGREEN)
        end
      elif elapsed < self.STATIC_MS / 2
        text(x0, 6, num, self.BLACK)          # erst die Zahl ...
      else
        text(x0, 6, ds, self.DARKGREEN)       # ... dann der Zuwachs
      end
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
