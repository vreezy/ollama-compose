#!/usr/bin/env bash
#
# Create application-menu entries for the Ollama stack.
#
#   ./scripts/install-launchers.sh            install
#   ./scripts/install-launchers.sh --remove   remove them again
#
# The .desktop files are written to ~/.local/share/applications with the absolute
# path of this checkout baked in, which is why they are generated here rather than
# committed to the repository.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_DIR/scripts/ollama-stack.sh"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

PREFIX="ollama-stack"
ENTRIES=(
    "up|Ollama: Start|Start the Ollama stack (GPU + web UI)|media-playback-start"
    "down|Ollama: Stop|Stop the Ollama stack, keeping downloaded models|media-playback-stop"
    "logs|Ollama: Logs|Follow the container logs|utilities-terminal"
    "status|Ollama: Status|Show what is running and which models are installed|dialog-information"
)

if [[ "${1:-}" == "--remove" ]]; then
    for e in "${ENTRIES[@]}"; do
        rm -fv "$APPS_DIR/$PREFIX-${e%%|*}.desktop"
    done
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
    echo "Launchers removed."
    exit 0
fi

chmod +x "$SCRIPT"
mkdir -p "$APPS_DIR"

# Pick a terminal emulator. Terminal=true is the portable XDG way, but desktops
# disagree on how well they honour it, so launch one explicitly when we can.
TERM_CMD=""
for t in ptyxis gnome-terminal konsole xfce4-terminal alacritty kitty foot xterm; do
    if command -v "$t" >/dev/null 2>&1; then
        case "$t" in
            ptyxis)         TERM_CMD="$t --" ;;
            gnome-terminal) TERM_CMD="$t --" ;;
            konsole|xfce4-terminal) TERM_CMD="$t -e" ;;
            *)              TERM_CMD="$t -e" ;;
        esac
        break
    fi
done

for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r cmd name comment icon <<<"$entry"
    file="$APPS_DIR/$PREFIX-$cmd.desktop"

    if [[ -n "$TERM_CMD" ]]; then
        exec_line="env OLLAMA_STACK_LAUNCHER=1 $TERM_CMD $SCRIPT $cmd"
        terminal="false"
    else
        exec_line="env OLLAMA_STACK_LAUNCHER=1 $SCRIPT $cmd"
        terminal="true"
    fi

    cat >"$file" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$name
Comment=$comment
Exec=$exec_line
Path=$PROJECT_DIR
Icon=$icon
Terminal=$terminal
Categories=Development;System;
Keywords=ollama;podman;llm;ai;
StartupNotify=true
EOF

    chmod +x "$file"
    echo "Created $file"
done

update-desktop-database "$APPS_DIR" 2>/dev/null || true

echo
echo "Done. Search for \"Ollama\" in your application menu."
[[ -n "$TERM_CMD" ]] || echo "No terminal emulator found - falling back to Terminal=true."
