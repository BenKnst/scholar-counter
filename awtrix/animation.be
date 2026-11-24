# @name Animation
# @description Zufaellige Vollbild-Animation (32x8), jede laeuft einmal komplett durch
# @config anims text "Animationen (zufaellig)" default="enterprise-battle:11.2+enterprise-warp:9, nyan:3.6, yoshi:16.9, frog:2.5, mario-luigi:9.4, matrixcode:3.5, pikachu-2~:5, watermelon:7.6, st-george:4.3, minecraft-enderman:10.5, wx-snow:9@12-2" help="Pro Auftritt wird zufaellig eine Gruppe gezeigt. Gruppen mit Komma trennen, Name:Sekunden, mit + nacheinander. Name~ = kleines 8x8-Icon laeuft durchs Bild. @12-2 = nur in diesen Monaten (hier Dezember bis Februar). Die Icons muessen auf der Uhr sein."
#
# Nachts (22-7 Uhr) ausgeblendet. Fehlt ein Icon, wird es uebersprungen.

class Animation
  var seq, seq_i, start, fresh, last_group

  def init()
    self.seq = []
    self.seq_i = 0
    self.start = 0
    self.fresh = false
    self.last_group = -1
  end

  def trim(t)
    var a = 0
    var b = size(t) - 1
    while a <= b && t[a] == " "
      a += 1
    end
    while b >= a && t[b] == " "
      b -= 1
    end
    return a > b ? "" : t[a .. b]
  end

  # Liste von Gruppen, jede Gruppe = Liste von [Name, Millisekunden]
  def groups()
    import string
    var raw = store.get("anims", "")
    var out = []
    if raw == nil || raw == ""
      return out
    end
    for g: string.split(raw, ",")
      var steps = []
      var in_season = true
      for part0: string.split(g, "+")
        var part = part0
        var at = string.split(part0, "@")      # "...@12-2" = nur von Monat 12 bis 2
        if at.size() > 1
          part = at[0]
          var mm = string.split(self.trim(at[1]), "-")
          var m1 = int(mm[0])
          var m2 = mm.size() > 1 ? int(mm[1]) : m1
          var m = month()
          if m > 0
            in_season = m1 <= m2 ? (m >= m1 && m <= m2) : (m >= m1 || m <= m2)
          end
        end
        var bits = string.split(part, ":")
        var name = self.trim(bits[0])
        var walk = false
        if size(name) > 1 && name[-1] == "~"   # "name~" = 8x8-Icon laeuft durchs Bild
          walk = true
          name = name[0 .. size(name) - 2]
        end
        var ms = 5000
        if bits.size() > 1
          ms = int(real(self.trim(bits[1])) * 1000)
        end
        if name != ""
          steps.push([name, ms, walk])
        end
      end
      if steps.size() > 0 && in_season
        out.push(steps)
      end
    end
    return out
  end

  # Zufaellig eine Gruppe waehlen (nicht zweimal hintereinander dieselbe)
  def pick()
    if self.fresh
      return
    end
    var gs = self.groups()
    self.seq = []
    if gs.size() > 0
      var i = now_ms() % gs.size()
      if gs.size() > 1 && i == self.last_group
        i = (i + 1) % gs.size()
      end
      self.last_group = i
      self.seq = gs[i]
    end
    self.seq_i = 0
    self.fresh = true
  end

  def night()
    var h = hour()
    return h >= 0 && (h >= 22 || h < 7)
  end

  def should_show()
    return !self.night() && store.get("anims", "") != ""
  end

  def duration()
    self.pick()
    var ms = 0
    for st: self.seq
      ms += st[1]
    end
    return ms > 0 ? ms : 1000
  end

  def on_show()
    self.pick()
    self.seq_i = 0
    self.start = now_ms()
  end

  def draw()
    clear()
    if self.seq_i >= self.seq.size()
      return
    end
    var st = self.seq[self.seq_i]
    var e = now_ms() - self.start
    var gone = false
    if st[2]
      # von rechts herein, links hinaus (Icon 8 Pixel breit)
      var x = width() - int(e * (width() + 8) / st[1])
      icon(st[0], x, 0)
    else
      gone = icon(st[0], 0, 0) == false
    end
    if gone || e > st[1]
      self.seq_i += 1
      self.start = now_ms()
      if self.seq_i >= self.seq.size()
        self.fresh = false           # beim naechsten Auftritt neu auslosen
      end
    end
  end
end

return Animation()
