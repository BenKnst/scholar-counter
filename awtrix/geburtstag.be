# @name Geburtstag
# @description Geburtstagsgruss an einem festen Tag im Jahr, mit Party und Melodie
# @config text text "Text" default="Happy Birthday Annie!"
# @config day number "Tag" default=6 min=1 max=31
# @config month number "Monat" default=12 min=1 max=12
# @config party_hours text "Party um (Uhr)" default="8:30" help="Zu diesen Uhrzeiten erscheint die grosse Party (Text und Melodie laufen, bis jemand die mittlere Taste drueckt). Mehrere mit Komma, z. B. 8:30,17:00"
# @config sound bool "Mit Melodie" default=true
# @config test bool "Testmodus (so tun, als waere heute Geburtstag)" default=false
#
# Am Geburtstag laeuft der Text bunt mit Konfetti durch (zwischen den anderen Apps).
# Zu den eingestellten Uhrzeiten holt sich die App die Anzeige, haelt die Rotation an und
# spielt die Melodie in Schleife - bis jemand die mittlere Taste drueckt. Nachts (22-7 Uhr) ist Ruhe.
# Meldet dem Nachtmodus ueber shared "aktiv", ob heute Geburtstag ist.

class Geburtstag
  var start, ticks, partying

  static PX_S = 20
  static MELODY = "HappyBday:d=4,o=5,b=125:8g.,16g,a,g,c6,2b,8g.,16g,a,g,d6,2c6,8g.,16g,g6,e6,c6,b,a,8f6.,16f6,e6,c6,d6,2c6"
  static SPARKLE = [0xFF0000, 0xFFC800, 0x00FF66, 0x66CCFF, 0xFF66CC, 0xFFFFFF]

  def init()
    self.start = 0
    self.ticks = 3
    self.partying = false
  end

  def night()
    var h = hour()
    return h >= 0 && (h >= 22 || h < 7)
  end

  def is_bday()
    if store.get("test", false)
      return true
    end
    return day() == int(store.get("day", 6)) && month() == int(store.get("month", 12))
  end

  def txt()
    var t = store.get("text", "Happy Birthday Annie!")
    return t == nil ? "" : str(t)
  end

  def loop()
    self.ticks -= 1
    if self.ticks > 0
      return
    end
    self.ticks = 10
    var on = self.is_bday() && !self.night()
    shared.set("aktiv", on)
    if on
      self.party()
    end
  end

  # Party zur letzten erreichten Uhrzeit aus "party_hours" (z. B. 8:30), jeweils einmal
  def party()
    import string
    var h = hour()
    if h < 0
      return
    end
    var now_min = h * 60 + minute()
    var slot = -1
    for p: string.split(str(store.get("party_hours", "8:30")), ",")
      var hm = string.split(p, ":")
      var m = int(hm[0]) * 60 + (hm.size() > 1 ? int(hm[1]) : 0)
      if m <= now_min && m > slot
        slot = m
      end
    end
    if slot < 0
      return
    end
    var key = str(year()) + "-" + str(month()) + "-" + str(day()) + "@" + str(slot)
    if store.get("party", "") == key || self.partying
      return
    end
    # Anzeige holen und festhalten; klappt das noch nicht (App gerade nicht in der Rotation),
    # wird es beim naechsten Durchlauf wieder versucht
    self.partying = true
    if !rotation.show()
      self.partying = false
      return
    end
    rotation.pause()
    store.set("party", key)
    self.start = now_ms()
    if store.get("sound", true)
      sound.play({"rtttl": self.MELODY, "loop": true})   # wiederholt sich bis zum Tastendruck
    end
  end

  def stop_party()
    if self.partying
      self.partying = false
      sound.stop()
      rotation.resume()
    end
  end

  # Mittlere Taste beendet die Party
  def on_button(btn)
    if self.partying && btn == "select"
      self.stop_party()
      rotation.next()
      return true
    end
    return false
  end

  # Mit links/rechts weggeschaltet: Party ebenfalls beenden
  def on_hide()
    self.stop_party()
  end

  def should_show()
    return self.partying || (self.txt() != "" && self.is_bday() && !self.night())
  end

  def one_ms()
    return (text_width(self.txt()) + width()) * 1000 / self.PX_S
  end

  def duration()
    if self.partying
      return 3600000                   # Party: bleibt, bis die Taste gedrueckt wird
    end
    return self.one_ms() * 2 + 500     # sonst zweimal durchlaufen
  end

  def on_show()
    if !self.partying
      self.start = now_ms()
    end
  end

  def draw()
    clear()
    var t = self.txt()
    var one = self.one_ms()
    var now = now_ms()
    var e = (now - self.start) % (one > 0 ? one : 1)
    var x = width() - int(e * self.PX_S / 1000)
    try
      ramp_text(x, 6, t, "Rainbow")
    except .. as err, msg
      text(x, 6, t, 0xFF66CC)
    end
    # Konfetti in der obersten und untersten Zeile
    var step = now / 150
    for i: 0 .. (self.partying ? 11 : 5)   # bei der Party doppelt so viel Konfetti
      var n = (step * 7 + i * 13) % 997
      var px = (n * 31) % width()
      var py = (n % 2 == 0) ? 0 : height() - 1
      pixel(px, py, self.SPARKLE[(n + i) % self.SPARKLE.size()])
    end
  end
end

return Geburtstag()
