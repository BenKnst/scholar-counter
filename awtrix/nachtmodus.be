# @name Nachtmodus
# @description Nachts nur die Uhrzeit: stellt die App-Reihenfolge abends um und morgens zurueck
# @config from number "Nachts ab" default=22 min=0 max=23 unit=h
# @config to number "Morgens ab" default=7 min=0 max=23 unit=h
# @config day text "Reihenfolge tagsueber" default="Time,Date,Time,Geburtstag,Time,Nachricht,Time,Animation,Time,Scholar,Time,Scholar-News,Time,Scholar-Jahr,Time,Scholar-Ziel,Time,Scholar-hIndex,Time,Scholar-Paper,Time,Scholar-Top,Time,Scholar-Chart,Time,Scholar-Jubilaeum,Time,Weather-Script,Time,Ghost-Parade" help="App-Namen mit Komma, wie im Skript-Tab. Wird jeden Morgen gesetzt - Aenderungen an der Reihenfolge bitte hier machen."
# @config night text "Reihenfolge nachts" default="Time"
# @config off text "Immer aus" default="Temperature,Humidity,Battery"
# @config host text "Adresse der Uhr" default="127.0.0.1" help="Nur aendern, falls die Umstellung im Log fehlschlaegt (dann die IP der Uhr eintragen)."
#
# Scholar-News, Geburtstag, Nachricht und Scholar-Jubilaeum stehen nur in der Reihenfolge, wenn sie etwas zu zeigen haben
# (sonst kaeme zweimal hintereinander die Uhrzeit).
# Diese App zeigt selbst nichts. Sie muss eingeschaltet bleiben, damit sie laufen kann.

import json

class Nachtmodus
  var ticks, busy, mode

  # Apps, die selbst melden (shared "aktiv"), ob sie etwas zu zeigen haben.
  # Ohne Inhalt laufen sie unsichtbar am Ende weiter, damit sie neue Inhalte melden koennen.
  static OPTIONAL = ["Nachricht", "Geburtstag", "Scholar-Jubilaeum"]

  def init()
    self.ticks = 5
    self.busy = false
    self.mode = ""
  end

  def names(key, default)
    import string
    var out = []
    var raw = store.get(key, default)
    if raw == nil
      return out
    end
    for part: string.split(raw, ",")
      var n = ""
      for i: 0 .. size(part) - 1
        if part[i] != " "
          n += part[i]
        end
      end
      if n != ""
        out.push(n)
      end
    end
    return out
  end

  # nil = Uhrzeit noch unbekannt
  def is_night()
    var h = hour()
    if h < 0
      return nil
    end
    var f = int(store.get("from", 22))
    var t = int(store.get("to", 7))
    if f > t
      return h >= f || h < t
    end
    return h >= f && h < t
  end

  # Gibt es gerade Neuigkeiten von Scholar?
  def has_news()
    var r = shared.get("Scholar.scholar", nil)
    if r == nil
      return false
    end
    var d = json.load(r)
    if !isinstance(d, map)
      return false
    end
    var t = d.find("ticker")
    return isinstance(t, list) && t.size() > 0
  end

  # Apps ohne Inhalt samt der Uhrzeit direkt davor weglassen
  def without(day, drop)
    var out = []
    for x: day
      if drop.find(x) != nil
        if out.size() > 0 && out[-1] == "Time"
          out.pop()
        end
      else
        out.push(x)
      end
    end
    return out
  end

  def loop()
    self.ticks -= 1
    if self.ticks > 0 || self.busy
      return
    end
    self.ticks = 30
    var n = self.is_night()
    if n == nil
      return
    end
    var drop = []
    if !self.has_news()
      drop.push("Scholar-News")
    end
    for a: self.OPTIONAL
      if shared.get(a + ".aktiv", false) != true
        drop.push(a)
      end
    end
    var want = n ? "night" : "day ohne " + str(drop)
    if want == self.mode
      return
    end
    var day = self.names("day", "Time")
    var order = n ? self.names("night", "Time") : self.without(day, drop)
    order.push("Nachtmodus")            # muss immer laufen
    for a: self.OPTIONAL
      if (drop.find(a) != nil || n) && order.find(a) == nil
        order.push(a)                   # laeuft weiter (am Ende, zeigt nichts), damit sie Neues melden kann
      end
    end
    var dis = []
    for x: day + self.names("night", "Time") + self.names("off", "")
      if order.find(x) == nil && dis.find(x) == nil
        dis.push(x)
      end
    end
    var body = json.dump({"order": order, "disabled": dis})
    var url = "http://" + store.get("host", "127.0.0.1") + "/api/v1/apps/order"
    self.busy = true
    var id = http.put(url, body, / b, st -> self.done(want, st, b),
                      {"timeout": 10, "headers": {"Content-Type": "application/json"}})
    if id == nil
      self.busy = false
      log("Nachtmodus: Anfrage nicht gestartet")
    end
  end

  def done(want, st, b)
    self.busy = false
    if st != nil && st >= 200 && st < 300
      self.mode = want
      log("Nachtmodus: " + want)
    else
      self.ticks = 120
      log("Nachtmodus: Umstellung fehlgeschlagen, Status " + str(st) + " " + str(b))
    end
  end

  def should_show()
    return false
  end

  def draw()
    clear()
  end
end

return Nachtmodus()
