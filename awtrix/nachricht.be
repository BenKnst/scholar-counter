# @name Nachricht
# @description Eigener Text als Laufschrift (leer = App wird uebersprungen)
# @config text text "Text" default="" help="Laeuft einmal durch, dann kommt die naechste App. Leer lassen, wenn nichts angezeigt werden soll."
# @config palette select "Bunt (Farbverlauf)" default=Rainbow options=Aus,Rainbow,Party,Lava,Ocean,Forest,Heat,Cloud,Stripe help="Aus = einfarbig in der Farbe darunter."
# @config color color "Farbe (wenn Bunt aus)" default=#FF66CC
# @config times number "Wie oft durchlaufen" default=1 min=1 max=5
#
# Nachts (22-7 Uhr) ausgeblendet. Meldet dem Nachtmodus ueber shared "aktiv", ob es etwas zu zeigen gibt.

class Nachricht
  var start, ticks, warned

  static PX_S = 20             # Tempo der Laufschrift (Pixel pro Sekunde)

  def init()
    self.start = 0
    self.ticks = 0
    self.warned = false
  end

  def txt()
    var t = store.get("text", "")
    return t == nil ? "" : str(t)
  end

  # Farbe aus der Einstellung (Zahl oder "#RRGGBB")
  def col()
    var c = store.get("color", 0xFF66CC)
    if isinstance(c, int)
      return c
    end
    var s = str(c)
    if size(s) == 7 && s[0] == "#"
      return int("0x" + s[1 ..])
    end
    return 0xFF66CC
  end

  def night()
    var h = hour()
    return h >= 0 && (h >= 22 || h < 7)
  end

  def loop()
    self.ticks -= 1
    if self.ticks <= 0
      self.ticks = 10
      shared.set("aktiv", self.txt() != "")
    end
  end

  def should_show()
    return self.txt() != "" && !self.night()
  end

  def one_ms()
    return (text_width(self.txt()) + width()) * 1000 / self.PX_S
  end

  def duration()
    return self.one_ms() * int(store.get("times", 1)) + 500
  end

  def on_show()
    self.start = now_ms()
  end

  def draw()
    clear()
    var t = self.txt()
    if t == ""
      return
    end
    var one = self.one_ms()
    var e = (now_ms() - self.start) % (one > 0 ? one : 1)
    var x = width() - int(e * self.PX_S / 1000)
    var pal = store.get("palette", "Rainbow")
    if pal != nil && pal != "" && pal != "Aus"
      try
        ramp_text(x, 6, t, pal)       # bunter Farbverlauf ueber den Text
        return
      except .. as err, msg
        if !self.warned                # Palette unbekannt: einmal melden, dann einfarbig
          self.warned = true
          log("Nachricht: Farbverlauf geht nicht: " + str(msg))
        end
      end
    end
    text(x, 6, t, self.col())
  end
end

return Nachricht()
