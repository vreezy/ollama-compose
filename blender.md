# Blender per MCP an opencode anbinden (Stand 2026-10-29)

So spricht ein lokales Modell in opencode (über Ollama) mit Blender:

```
opencode  →  mcp-for-blender (MCP-Server, über pipx)  →  Socket 127.0.0.1:9876  →  Blender-Addon „MCP for Blender“
```

## Installation

```bash
# MCP-Server installieren (feste Version von PyPI, nicht von einem Git-Commit)
pipx install --force mcp-for-blender==2.2.6

# Passendes Blender-Addon installieren (landet in ~/.config/blender/<version>/scripts/addons/)
mcp-for-blender install-addon
```

Dann in Blender: **Preferences → Add-ons → „Interface: MCP for Blender“** einschalten (nach einem Update: aus- und wieder einschalten oder Blender neu starten). Danach in der Sidebar (N) im 3D-Viewport **Start MCP Server** klicken.

Eintrag in `~/.config/opencode/opencode.json` (opencode 2.1):

```json
"mcp": {
  "servers": {
    "blender": {
      "type": "local",
      "command": ["mcp-for-blender"],
      "codemode": false
    }
  }
}
```

### Warum `codemode: false`

Standardmäßig gibt opencode MCP-Tools im **Code Mode** weiter. Dann sieht das Modell nur ein einziges Tool `execute` und muss darin **JavaScript** schreiben, z. B. `tools.blender.execute_blender_code({ code: "..." })`. Kleine Modelle wie `qwen3.5:9b` schreiben dort Python-Syntax (`code="""..."""`, `name=wert`) und scheitern mit `Unknown identifier` oder `Unexpected token`.

Mit `codemode: false` bekommt das Modell die Tools direkt (`blender_get_scene_info`, `blender_execute_blender_code`, …) mit normalen JSON-Argumenten. Das klappt mit 9B.

**Achtung, Config-Format:** `codemode` wirkt nur unter `"mcp": { "servers": { ... } }`. Im alten Format `"mcp": { "blender": { ..., "enabled": true } }` wird der Schlüssel stillschweigend ignoriert. Im neuen Format gibt es kein `enabled` mehr, ausschalten geht dort mit `"disabled": true`.

## Nach jedem Update

Server und Addon müssen dieselbe Protokollversion haben, deshalb immer beides aktualisieren:

```bash
pipx install --force mcp-for-blender==<neue-version>
mcp-for-blender install-addon
# Blender: Addon aus/ein oder Blender neu starten, dann „Start MCP Server“
opencode service restart
```

**Wichtig:** opencode läuft als Hintergrund-Dienst (`opencode serve --service`). Wenn du nur die Oberfläche neu startest, behält der Dienst den alten MCP-Server. Nach Änderungen am Server oder an `opencode.json` immer `opencode service restart` ausführen.

Auch wenn Blender neu gestartet wurde, kann die Verbindung im laufenden MCP-Server abgerissen sein („Connection closed before receiving any data“). Dann hilft ebenfalls `opencode service restart`.

## Prüfen, ob alles läuft

```bash
# Lauscht Blender auf dem Port?
ss -ltnp | grep 9876

# Hat opencode den MCP-Server geladen?
opencode mcp list                 # erwartet: ✓ blender  connected
opencode service status

# Welche MCP-Prozesse laufen und seit wann? (Startzeit muss nach dem letzten Update liegen)
ps -o pid,lstart,args -p $(pgrep -d, -f 'bin/mcp-for-blender')

# Handshake direkt testen, ohne opencode
~/.local/share/pipx/venvs/mcp-for-blender/bin/python -c '
from blender_mcp import server as s
c = s.BlenderConnection("localhost", 9876); print("connect:", c.connect())
s._maybe_handshake_addon(c); print(s._addon_handshake)'
# erwartet: up_to_date=True, warning=None

# Log von opencode
grep -i 'mcp' ~/.local/share/opencode/log/opencode.log | tail
```

## Bekannte Fehler

| Meldung | Ursache | Lösung |
|---|---|---|
| `No module named 'blender_mcp.config'` | Bug in mcp-for-blender 2.1.9 (`config.py` fehlt im Paket) | Auf ≥ 2.2.6 aktualisieren (siehe oben) |
| `up_to_date: false`, `expected_protocol_version` passt nicht zum Addon | Server und Addon haben verschiedene Versionen | `mcp-for-blender install-addon`, Addon neu laden |
| `Connection closed before receiving any data` | Blender wurde neu gestartet oder der MCP-Server im Addon ist nicht gestartet | „Start MCP Server“ in Blender, dann `opencode service restart` |
| `pipx upgrade` meldet „already at latest version“ | Paket wurde von einem festen Git-Commit installiert | `pipx install --force mcp-for-blender==<version>` |
| Modell ruft `execute` mit `tools.blender.…(name=…)` auf, Fehler `Unknown identifier` / `Unexpected token (1:42)` | Code Mode aktiv, das Modell schreibt Python statt JavaScript | `codemode: false` im neuen Config-Format (siehe oben), `opencode service restart` |

## Testen, welche Tools das Modell bekommt

```bash
# Kurztest ohne Oberfläche. Erwartet: Aufruf von "blender_get_scene_info", nicht "execute"
opencode run -m ollama/qwen3.5:9b "Rufe das Blender-Tool get_scene_info auf und nenne die Objekte. Ändere nichts."
```

## Hinweis zum Modell

Getestet wird bewusst mit `qwen3.5:9b`, weil der Rechner in der Werkstatt kein größeres Modell schafft. Tool-Aufrufe klappen mit `codemode: false`. Bei längeren Blender-Skripten macht 9B aber weiter API-Fehler (z. B. `bpy.types.CYLINDER` gibt es nicht). Kleine, konkrete Aufträge Schritt für Schritt funktionieren besser als „bau einen ganzen Baum“.
