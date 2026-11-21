# @name Scholar
# @description Zitationen. Holt auch die Daten fuer die anderen Scholar-Apps.
# @config url text "Adresse der clock.json" default="https://gist.githubusercontent.com/BenKnst/442b1a85615c2f88cb485fd3803e39f0/raw/clock.json"
# @config sound bool "Ton bei Party" default=true
# @config party_icon text "Party-Icon (Name, optional)" default="" help="Z. B. ein Konfetti-Icon aus dem AWTRIX Hub"
# @config icons text "Icons (Namen, mit Komma getrennt)" default="" help="Werden zufaellig vor der Zitationszahl gezeigt. Leer = goldene Anfuehrungszeichen."
# @config show_name bool "Namen als Laufschrift vorweg" default=true
# @config author text "Name (leer = aus Google Scholar)" default="" help="Nur ausfuellen, wenn ein anderer Name laufen soll als im Scholar-Profil."
# @config intro bool "CITATIONS als Laufschrift vorweg" default=true
# @config anims text "Animationen vorweg (zufaellig)" default="enterprise-battle:11.2+enterprise-warp:9, nyan:3.6, yoshi:16.9, frog:2.5, mario-luigi:9.4, matrixcode:3.5" help="Pro Auftritt wird zufaellig eine Gruppe gezeigt. Gruppen mit Komma trennen, Name:Sekunden, mit + nacheinander. Leer = keine Animation."
#
# Ulanzi TC001 (32 x 8) mit AWTRIX NG.
# Holt alle 30 Minuten die clock.json aus dem Gist und legt sie unter shared "scholar" ab.
# Daraus lesen die Apps Scholar-hIndex, Scholar-Paper, Scholar-Chart und Scholar-News.
# Diese App zeigt: Animation -> Name -> "CITATIONS" -> Anfuehrungszeichen + Zitationen
# (+ Zuwachs in Gruen), unterste Zeile = Fortschritt bis zum naechsten h-Index.
# Party (neue Zitationen, neues Paper, h-Index, Meilenstein): bleibt stehen, bis jemand die
# mittlere Taste drueckt. Nachts (22-7 Uhr) wartet sie bis 7 Uhr.

import json

class Scholar
  var d, ticks, busy, party_ticks, phase, phase_start, cur_icon
  var seq, seq_i, seq_fresh, last_group

  static GOLD  = 0xFFC800
  static WHITE = 0xFFFFFF
  static GREEN = 0x00FF66
  static GREY  = 0x808080
  static RED   = 0xFF0000
  static BAR_OFF = 0x303030
  static PX_S = 20             # Tempo der Laufschriften (Pixel pro Sekunde)
  static NUMBER_MS = 8000      # so lange steht die Zitationszahl
  static STALE_S = 172800      # Daten aelter als 2 Tage -> roter Punkt
  static QUOTE = [[0,1],[1,1],[3,1],[4,1],[0,2],[1,2],[3,2],[4,2],[1,3],[4,3]]

  def init()
    self.d = nil
    self.ticks = 3
    self.busy = false
    self.party_ticks = 0
    self.phase = 3
    self.phase_start = 0
    self.cur_icon = nil
    self.seq = []
    self.seq_i = 0
    self.seq_fresh = false
    self.last_group = -1
  end

  def night()
    var h = hour()
    return h >= 0 && (h >= 22 || h < 7)
  end

  def get(key, default)
    if self.d == nil
      return default
    end
    var v = self.d.find(key)
    return v == nil ? default : v
  end

  # ------------------------------------------------------------ Daten holen
  def loop()
    self.party_ticks -= 1
    if self.party_ticks <= 0
      self.party_ticks = 60          # jede Minute pruefen, ob eine Party wartet
      self.celebrate()
    end
    self.ticks -= 1
    if self.ticks > 0 || self.busy
      return
    end
    self.ticks = 1800                # ca. alle 30 Minuten
    var url = store.get("url", "https://gist.githubusercontent.com/BenKnst/442b1a85615c2f88cb485fd3803e39f0/raw/clock.json")
    self.busy = true
    var id = http.get(url, / body, status -> self.on_body(body, status), {"timeout": 20})
    if id == nil
      self.busy = false
      self.ticks = 60
    end
  end

  def on_body(body, status)
    self.busy = false
    if body == nil || status != 200
      self.ticks = 300
      log("Scholar: Abruf fehlgeschlagen, Status " + str(status))
      return
    end
    var data = json.load(body)
    if !isinstance(data, map)
      log("Scholar: Antwort ist kein JSON")
      return
    end
    self.d = data
    shared.set("scholar", body)
    self.celebrate()
  end

  def celebrate()
    var c = self.get("celebrate", nil)
    if !isinstance(c, map) || self.night()
      return                         # nachts wartet die Party bis 7 Uhr
    end
    var cid = c.find("id")
    if cid == nil || store.get("feier", "") == cid
      return
    end
    store.set("feier", cid)
    var spec = {"text": c.find("t"), "textColor": "#FFC800", "hold": true, "wakeup": true}
    var pi = store.get("party_icon", "")
    if pi != nil && pi != ""
      spec["icon"] = pi
    end
    if store.get("sound", true)
      if c.find("lvl") == "big"
        spec["sound"] = {"rtttl": "fanfare:d=8,o=6,b=180:c,e,g,4c7,p,g,2c7"}
      else
        spec["sound"] = {"rtttl": "yay:d=16,o=6,b=200:c,e,g,8c7"}
      end
    end
    notify(spec)
  end

  # ------------------------------------------------------------ Vorspann
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

  def anim_groups()
    import string
    var raw = store.get("anims", "")
    var groups = []
    if raw == nil || raw == ""
      return groups
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
        groups.push(steps)
      end
    end
    return groups
  end

  # Zufaellig eine Gruppe waehlen (nicht zweimal hintereinander dieselbe)
  def pick_anim()
    if self.seq_fresh
      return
    end
    var groups = self.anim_groups()
    self.seq = []
    if groups.size() > 0
      var i = now_ms() % groups.size()
      if groups.size() > 1 && i == self.last_group
        i = (i + 1) % groups.size()
      end
      self.last_group = i
      self.seq = groups[i]
    end
    self.seq_i = 0
    self.seq_fresh = true
  end

  def author_name()
    var a = store.get("author", "")
    if a != nil && a != ""
      return a
    end
    var n = self.get("name", "")
    return n == nil ? "" : str(n)
  end

  def show_name()
    return store.get("show_name", true) && self.author_name() != ""
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

  # Phasen: 0 Animation, 1 Name, 2 CITATIONS, 3 Zahl. Abgeschaltete werden uebersprungen.
  def go(p)
    if p == 0 && self.seq.size() == 0
      p = 1
    end
    if p == 1 && !self.show_name()
      p = 2
    end
    if p == 2 && !store.get("intro", true)
      p = 3
    end
    self.phase = p
    self.phase_start = now_ms()
  end

  # ------------------------------------------------------------ Rotation
  def should_show()
    return self.d != nil && !self.night()
  end

  def on_show()
    self.pick_anim()
    self.seq_i = 0
    self.pick_icon()
    self.go(0)
  end

  def duration()
    self.pick_anim()
    var ms = self.NUMBER_MS
    for st: self.seq
      ms += st[1]
    end
    if self.show_name()
      ms += self.scroll_ms(self.author_name())
    end
    if store.get("intro", true)
      ms += self.scroll_ms("CITATIONS")
    end
    return ms
  end

  def pick_icon()
    self.cur_icon = nil
    var raw = store.get("icons", "")
    if raw == nil || raw == ""
      return
    end
    import string
    var names = []
    for part: string.split(raw, ",")
      var n = self.trim(part)
      if n != ""
        names.push(n)
      end
    end
    if names.size() > 0
      self.cur_icon = names[now_ms() % names.size()]
    end
  end

  def is_stale()
    if self.get("ok", true) == false
      return true
    end
    var upd = self.get("upd", 0)
    var ms = epoch_ms()
    if upd > 0 && ms > 0
      return int(ms / 1000) - upd > self.STALE_S
    end
    return false
  end

  # 1234 bleibt, 123456 -> 123k, 1234567 -> 1.2M
  def fmt_count(n, maxw)
    var s = str(n)
    if !isinstance(n, int) || text_width(s) <= maxw
      return s
    end
    import string
    if n >= 1000000
      s = string.format("%.1fM", n / 1000000.0)
      if text_width(s) > maxw
        s = str(n / 1000000) + "M"
      end
    else
      s = string.format("%.1fk", n / 1000.0)
      if text_width(s) > maxw
        s = str(n / 1000) + "k"
      end
    end
    return s
  end

  def draw_progress()
    var prog = self.get("h_prog", nil)
    if prog == nil
      return
    end
    var n = int(prog * width() / 100)
    for x: 0 .. width() - 1
      pixel(x, 7, x < n ? self.GOLD : self.BAR_OFF)
    end
  end

  # ------------------------------------------------------------ Zeichnen
  def draw()
    clear()
    if self.d == nil
      text(1, 6, "...", self.GREY)
      return
    end
    var elapsed = now_ms() - self.phase_start

    if self.phase == 0
      var st = self.seq[self.seq_i]
      if icon(st[0], 0, 0) == false || elapsed > st[1]
        self.seq_i += 1
        self.phase_start = now_ms()
        if self.seq_i >= self.seq.size()
          self.seq_fresh = false     # beim naechsten Auftritt neu auslosen
          self.go(1)
        end
      end

    elif self.phase == 1
      var nm = self.author_name()
      if self.scroll_once(nm, self.WHITE, elapsed) || elapsed > self.scroll_ms(nm) + 1000
        self.go(2)
      end

    elif self.phase == 2
      if self.scroll_once("CITATIONS", self.GOLD, elapsed) || elapsed > self.scroll_ms("CITATIONS") + 1000
        self.go(3)
      end

    else
      var x0 = 7
      if self.cur_icon == nil || icon(self.cur_icon, 0, 0) == false
        for q: self.QUOTE
          pixel(q[0], q[1], self.GOLD)
        end
      else
        x0 = 9
      end
      var num = self.fmt_count(self.get("cites", 0), width() - x0)
      var delta = self.get("delta", 0)
      var ds = delta > 0 ? "+" + str(delta) : ""
      if ds == "" || x0 + text_width(num) + 1 + text_width(ds) <= width()
        var x = x0 + text(x0, 6, num, self.WHITE)
        if ds != ""
          text(x + 1, 6, ds, self.GREEN)
        end
      elif (elapsed / 3000) % 2 == 0
        text(x0, 6, num, self.WHITE)      # passt nicht beides: abwechselnd
      else
        text(x0, 6, ds, self.GREEN)
      end
      self.draw_progress()
      if self.is_stale()
        pixel(width() - 1, 0, self.RED)
      end
    end
  end
end

return Scholar()
