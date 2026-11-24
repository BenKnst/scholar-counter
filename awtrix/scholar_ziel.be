# @name Scholar Ziel
# @description Wie viele Zitationen bis zum naechsten Meilenstein fehlen
#
# Liest die Daten, die die App "Scholar" holt. Nachts (22-7 Uhr) ausgeblendet.

import json

class SZ
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


  # Teile der Laufschrift: [Text, Farbe]
  def parts()
    var m = self.get("m_next", nil)
    var need = self.get("m_need", nil)
    if m == nil || need == nil
      return []
    end
    return [[self.fmt(need), self.GREEN], [need == 1 ? " citation to " : " citations to ", self.WHITE],
            [self.fmt(m), self.GOLD], ["!", self.WHITE]]
  end

  def should_show()
    return self.d != nil && !self.night() && self.get("m_next", nil) != nil
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

  def total_w(ps)
    var w = 0
    for p: ps
      w += text_width(p[0])
    end
    return w
  end

  def duration()
    return (self.total_w(self.parts()) + width()) * 1000 / self.PX_S + 500
  end

  # mehrfarbige Laufschrift, einmal von rechts nach links
  def draw()
    clear()
    var x = width() - int((now_ms() - self.start) * self.PX_S / 1000)
    for p: self.parts()
      x += text(x, 6, p[0], p[1])
    end
  end
end

return SZ()
