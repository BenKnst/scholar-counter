# @name Scholar News
# @description Neuigkeiten: neue Publikation, neue Zitationen, Nachricht (nur wenn vorhanden)
#
# Liest die Daten, die die App "Scholar" holt. Nachts (22-7 Uhr) ausgeblendet.

import json

class SN
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

  def items()
    var out = []
    var t = self.get("ticker", [])
    if isinstance(t, list)
      for x: t
        if isinstance(x, map) && x.find("t") != nil
          var c = x.find("c")
          var col = self.WHITE
          if c == "neu"
            col = self.GREEN
          elif c == "zitiert" || c == "zitiert_in"
            col = self.BLUE
          elif c == "msg"
            col = self.PINK
          end
          out.push([str(x["t"]), col])
        end
      end
    end
    return out
  end

  def should_show()
    return self.d != nil && !self.night() && self.items().size() > 0
  end

  def duration()
    var ms = 0
    for it: self.items()
      ms += self.scroll_ms(it[0])
    end
    return ms > 0 ? ms : 1000
  end

  # Meldungen nacheinander durchlaufen lassen
  def draw()
    clear()
    var elapsed = now_ms() - self.start
    for it: self.items()
      var ms = self.scroll_ms(it[0])
      if elapsed < ms
        self.scroll_once(it[0], it[1], elapsed)
        return
      end
      elapsed -= ms
    end
  end
end

return SN()
