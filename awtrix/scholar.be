# @name Scholar
# @description Google-Scholar-Zitationen, h-Index und Neuigkeiten
# @config url text "Adresse der clock.json" default="https://benknst.github.io/scholar-counter/clock.json"
# @config sound bool "Ton bei Meilensteinen" default=true
#
# ENTWURF fuer AWTRIX NG (Ulanzi TC001, 8 x 32 Pixel).
# Holt alle 30 Minuten die clock.json von GitHub Pages und zeigt nacheinander:
#   1. Buch-Symbol + Gesamtzitationen (+ Zuwachs seit gestern)
#   2. Laufschrift: h-Index und wie viele Zitationen bis zum naechsten fehlen
#   3. Balkendiagramm: Zitationen pro Jahr
#   4. Laufschrift: Neuigkeiten (neue Publikation, neue Zitationen, Nachricht)
# Bei einem neuen h-Index oder Meilenstein kommt einmalig eine Benachrichtigung mit Ton.

import json

class Scholar
  var d, ticks, busy, pages, page, page_start

  static GOLD  = 0xFFC800
  static WHITE = 0xFFFFFF
  static GREEN = 0x00FF66
  static BLUE  = 0x66CCFF
  static PINK  = 0xFF66CC
  static GREY  = 0x808080
  static RED   = 0xFF0000
  static STATIC_MS = 5000      # Anzeigedauer der festen Seiten
  static SCROLL_MAX_MS = 40000 # Laufschrift spaetestens nach 40 s weiter

  # offenes Buch, 7 x 5 Pixel
  static BOOK = [".WW.WW.", "W..W..W", "W..W..W", "W..W..W", "WWWWWWW"]

  def init()
    self.d = nil
    self.ticks = 3
    self.busy = false
    self.pages = []
    self.page = 0
    self.page_start = 0
  end

  # ------------------------------------------------------------ Daten holen
  def loop()
    self.ticks -= 1
    if self.ticks > 0 || self.busy
      return
    end
    self.ticks = 1800   # ca. alle 30 Minuten (loop laeuft etwa 1x pro Sekunde)
    var url = store.get("url", "https://benknst.github.io/scholar-counter/clock.json")
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
    var txt = "h-Index " + str(self.get("h", "?"))
    if need != nil
      txt += "  -  noch " + str(need) + " bis h" + str(self.get("h_next", "?"))
    end
    p.push({"kind": "scroll", "text": txt, "color": self.GOLD})
    var years = self.get("years", [])
    if isinstance(years, list) && years.size() > 1
      p.push({"kind": "chart"})
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
    var spec = {"text": c.find("t"), "textColor": self.GOLD, "wakeup": true}
    if store.get("sound", true)
      spec["sound"] = {"rtttl": "tusch:d=16,o=6,b=180:c,e,g,4c7"}
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

  # ------------------------------------------------------------ Zeichnen
  def draw_book(x0, color)
    var y = 1
    for row: self.BOOK
      for x: 0 .. size(row) - 1
        if row[x] == "W"
          pixel(x0 + x, y, color)
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
      self.draw_book(0, self.GOLD)
      var x = 9 + text(9, 6, str(self.get("cites", "?")), self.WHITE)
      var delta = self.get("delta", 0)
      if delta > 0
        var s = "+" + str(delta)
        if x + 1 + text_width(s) <= width()
          text(x + 1, 6, s, self.GREEN)
        end
      end
      if self.get("ok", true) == false
        pixel(width() - 1, 0, self.RED)   # roter Punkt: Daten sind veraltet
      end
      if elapsed > self.STATIC_MS
        self.next_page()
      end

    elif k == "chart"
      bar_chart(self.get("years", []), self.BLUE, true)
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
