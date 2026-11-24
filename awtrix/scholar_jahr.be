# @name Scholar Jahr
# @description Zitationen im laufenden Jahr (mit Jahreszahl)
#
# Liest die Daten, die die App "Scholar" holt. Nachts (22-7 Uhr) ausgeblendet.

import json

class SJ
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

  # Zitationen im laufenden Jahr: [Jahr, Anzahl]
  def this_year()
    var years = self.get("years", [])
    var y0 = self.get("y0", nil)
    var yn = self.get("y_now", nil)
    if !isinstance(years, list) || years.size() == 0 || y0 == nil || yn == nil
      return nil
    end
    if y0 + years.size() - 1 == yn
      return [yn, years[-1]]
    end
    return [yn, 0]                     # in diesem Jahr noch keine Zitation
  end

  # 110503 -> "110,503"
  def fmt(n)
    var s = str(n)
    var out = ""
    var k = 0
    var i = size(s) - 1
    while i >= 0
      out = s[i] + out
      k += 1
      if k % 3 == 0 && i > 0
        out = "," + out
      end
      i -= 1
    end
    return out
  end

  # Teile der Laufschrift: [Text, Farbe]
  def parts()
    var t = self.this_year()
    if t == nil
      return []
    end
    return [["Citations in ", self.WHITE], [str(t[0]), self.GOLD], [": ", self.WHITE],
            [self.fmt(t[1]), self.GREEN]]
  end

  def total_w(ps)
    var w = 0
    for p: ps
      w += text_width(p[0])
    end
    return w
  end

  def should_show()
    return self.d != nil && !self.night() && self.this_year() != nil
  end

  def duration()
    return (self.total_w(self.parts()) + width()) * 1000 / self.PX_S + 500
  end

  def draw()
    clear()
    var ps = self.parts()
    var x = width() - int((now_ms() - self.start) * self.PX_S / 1000)
    for p: ps
      x += text(x, 6, p[0], p[1])
    end
  end
end

return SJ()
