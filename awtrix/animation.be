# @name Animation
# @description Zufaellige Vollbild-Animation (32x8), jede laeuft einmal komplett durch
# @config anims text "Animationen (zufaellig)" default="enterprise-battle:11.2+enterprise-warp:9, nyan:3.6, yoshi:16.9, frog:2.5, mario-luigi:9.4, matrixcode:3.5" help="Pro Auftritt wird zufaellig eine Gruppe gezeigt. Gruppen mit Komma trennen, Name:Sekunden, mit + nacheinander. Die Icons muessen auf der Uhr sein."
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
      for part: string.split(g, "+")
        var bits = string.split(part, ":")
        var name = self.trim(bits[0])
        var ms = 5000
        if bits.size() > 1
          ms = int(real(self.trim(bits[1])) * 1000)
        end
        if name != ""
          steps.push([name, ms])
        end
      end
      if steps.size() > 0
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
    if icon(st[0], 0, 0) == false || now_ms() - self.start > st[1]
      self.seq_i += 1
      self.start = now_ms()
      if self.seq_i >= self.seq.size()
        self.fresh = false           # beim naechsten Auftritt neu auslosen
      end
    end
  end
end

return Animation()
