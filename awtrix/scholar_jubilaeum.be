# @name Scholar Jubilaeum
# @description Jahrestag eines der 3 meistzitierten Paper (nur an dem Tag)
#
# Liest die Daten, die die App "Scholar" holt. Nachts (22-7 Uhr) ausgeblendet.
# Meldet dem Nachtmodus ueber shared "aktiv", ob heute ein Jahrestag ist.

import json

class SA
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


  var ticks

  # Heutige Jahrestage: Liste von [Jahre, Titel]
  def today()
    var out = []
    var a = self.get("anniv", [])
    var m = month()
    var dd = day()
    if !isinstance(a, list) || m < 1
      return out
    end
    var md = (m < 10 ? "0" : "") + str(m) + "-" + (dd < 10 ? "0" : "") + str(dd)
    for x: a
      if isinstance(x, map) && x.find("md") == md
        var n = year() - int(x.find("y"))
        if n > 0
          out.push([n, str(x.find("t"))])
        end
      end
    end
    return out
  end

  def parts()
    var ps = []
    for x: self.today()
      if ps.size() > 0
        ps.push(["   ", self.WHITE])
      end
      ps.push([str(x[0]) + (x[0] == 1 ? " year" : " years") + " ago today: ", self.GOLD])
      ps.push([x[1], self.BLUE])
    end
    return ps
  end

  # meldet dem Nachtmodus, ob heute ein Jahrestag ist
  def loop()
    var r = shared.get("Scholar.scholar", nil)
    if r != nil && r != self.raw
      self.raw = r
      var x = json.load(r)
      if isinstance(x, map)
        self.d = x
      end
    end
    self.ticks = (self.ticks == nil ? 0 : self.ticks) - 1
    if self.ticks <= 0
      self.ticks = 30
      shared.set("aktiv", self.d != nil && !self.night() && self.today().size() > 0)
    end
  end

  def should_show()
    return self.d != nil && !self.night() && self.today().size() > 0
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

return SA()
