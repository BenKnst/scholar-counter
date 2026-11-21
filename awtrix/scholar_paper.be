# @name Scholar Paper
# @description Paper der letzten 12 Monate
#
# Liest die Daten, die die App "Scholar" holt. Nachts (22-7 Uhr) ausgeblendet.

import json

class SP
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

  # Daten kommen von der App "Scholar" (shared "scholar")
  def loop()
    var r = shared.get("scholar", nil)
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

  def txt()
    var p12 = self.get("p12", nil)
    if p12 != nil
      return str(p12) + (p12 == 1 ? " paper" : " papers") + " in the last 12 months"
    end
    var py = self.get("py", nil)
    if py == nil
      return ""
    end
    var yn = self.get("y_now", 0)
    return str(py) + (py == 1 ? " paper in " : " papers in ") + str(yn)
  end

  def should_show()
    return self.d != nil && !self.night() && self.txt() != ""
  end

  def duration()
    return self.scroll_ms(self.txt())
  end

  def draw()
    clear()
    if self.d != nil
      self.scroll_once(self.txt(), self.GREEN, now_ms() - self.start)
    end
  end
end

return SP()
