# @name Scholar Chart
# @description Balken: Zitationen pro Monat oder pro Jahr, mit Erklaerung vorweg
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

  static BARS_MS = 6000

  # [Erklaerung, Werte]
  def chart()
    var months = self.get("months", [])
    if isinstance(months, list) && months.size() >= 3
      return ["New citations per month, last " + str(months.size()) + " months", months]
    end
    var years = self.get("years", [])
    if isinstance(years, list) && years.size() > 1
      return ["Citations per year since " + str(self.get("y0", "")), years]
    end
    return nil
  end

  def should_show()
    return self.d != nil && !self.night() && self.chart() != nil
  end

  def duration()
    var c = self.chart()
    return c == nil ? 1000 : self.scroll_ms(c[0]) + self.BARS_MS
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
      bar_chart(c[1], self.BLUE, true)
    end
  end
end

return SC()
