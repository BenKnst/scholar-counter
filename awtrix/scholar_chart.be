# @name Scholar Chart
# @description Balken: Zitationen pro Monat oder pro Jahr, mit Erklaerung vorweg; laufen von rechts nach links durch
#
# Liest die Daten, die die App "Scholar" holt. Nachts (22-7 Uhr) ausgeblendet.

import json

class SC
  var d, raw, start

  static GOLD  = 0xFFC800
  static WHITE = 0xFFFFFF
  static GREEN = 0x00FF66
  static BLUE  = 0x66CCFF
  static PINK  = 0xFF66CC
  static BAR_OFF = 0x303030
  static PX_S = 20             # Tempo der Laufschrift (Pixel pro Sekunde)

  def init()
    self.d = nil
    self.raw = nil
    self.start = 0
  end

  # Daten kommen von der App "Scholar" (shared "scholar", fuer andere Apps "Scholar.scholar")
  def loop()
    var r = shared.get("Scholar.scholar", nil)
    if r != nil && r != self.raw
      self.raw = r
      var x = json.load(r)
      if isinstance(x, map)
        self.d = x
      end
    end
  end

  def get(key, default)
    if self.d == nil
      return default
    end
    var v = self.d.find(key)
    return v == nil ? default : v
  end

  def night()
    var h = hour()
    return h >= 0 && (h >= 22 || h < 7)
  end

  def scroll_ms(txt)
    return (text_width(txt) + width()) * 1000 / self.PX_S + 500
  end

  # Text einmal von rechts nach links; true, sobald er ganz hinaus ist
  def scroll_once(txt, color, elapsed)
    var x = width() - int(elapsed * self.PX_S / 1000)
    text(x, 6, txt, color)
    return x < -text_width(txt)
  end

  def on_show()
    self.start = now_ms()
  end

  static BAR_W = 2              # Balkenbreite in Pixeln
  static GAP = 1                # Abstand zwischen den Balken
  static BAR_PX_S = 8           # Tempo, mit dem die Balken durchlaufen (Pixel pro Sekunde)
  static HOLD_MS = 4000         # so lange bleibt das Ende stehen
  static NOW_COL = 0xFFC800     # laufendes Jahr / laufender Monat (noch nicht fertig) in Gold

  # [Erklaerung, Werte]
  def chart()
    var months = self.get("months", [])
    if isinstance(months, list) && months.size() >= 3
      return ["New citations per month, last " + str(months.size()) + " months", months]
    end
    var years = self.get("years", [])
    if isinstance(years, list) && years.size() > 1
      var y0 = self.get("y0", 0)
      return ["Citations per year " + str(y0) + "-" + str(y0 + years.size() - 1), years]
    end
    return nil
  end

  def should_show()
    return self.d != nil && !self.night() && self.chart() != nil
  end

  # Breite aller Balken zusammen
  def strip_w(vals)
    return vals.size() * (self.BAR_W + self.GAP) - self.GAP
  end

  # Balken laufen von rechts herein, bis der letzte rechts am Rand steht
  def bars_ms(vals)
    return (self.strip_w(vals) * 1000) / self.BAR_PX_S + self.HOLD_MS
  end

  def duration()
    var c = self.chart()
    return c == nil ? 1000 : self.scroll_ms(c[0]) + self.bars_ms(c[1])
  end

  def draw_bars(vals, elapsed)
    var mx = 0
    for v: vals
      if v > mx
        mx = v
      end
    end
    if mx <= 0
      mx = 1
    end
    # Startposition: rechts ausserhalb; Ende: letzter Balken buendig am rechten Rand
    var end_x = width() - self.strip_w(vals)
    var x0 = width() - int(elapsed * self.BAR_PX_S / 1000)
    if x0 < end_x
      x0 = end_x
    end
    var h = height()
    var last = vals.size() - 1
    for i: 0 .. last
      var v = vals[i]
      var bh = v > 0 ? int(v * h / mx) : 0
      if v > 0 && bh < 1
        bh = 1
      end
      var col = i == last ? self.NOW_COL : self.BLUE
      var bx = x0 + i * (self.BAR_W + self.GAP)
      if bh > 0 && bx < width() && bx + self.BAR_W > 0
        rect_fill(bx, h - bh, self.BAR_W, bh, col)
      end
    end
  end

  def draw()
    clear()
    var c = self.chart()
    if c == nil
      return
    end
    var elapsed = now_ms() - self.start
    var lab = self.scroll_ms(c[0])
    if elapsed < lab
      self.scroll_once(c[0], self.BLUE, elapsed)
    else
      self.draw_bars(c[1], elapsed - lab)
    end
  end
end

return SC()
