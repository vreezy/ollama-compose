#!/usr/bin/env bash
#
# Start, stop and inspect the Ollama stack.
#
# Works from anywhere: it locates the project folder from its own path, so the
# desktop launchers do not depend on a working directory being set.
#
#   ./scripts/ollama-stack.sh up       start the stack
#   ./scripts/ollama-stack.sh down     stop and remove the containers
#   ./scripts/ollama-stack.sh logs     follow the logs
#   ./scripts/ollama-stack.sh status   show what is running
#
# Which overlays are used can be overridden:
#   OLLAMA_STACK_FILES="compose.yml compose.rocm.yml" ./scripts/ollama-stack.sh up

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Default: full stack (GPU + web UI). Override with OLLAMA_STACK_FILES.
read -r -a STACK_FILES <<<"${OLLAMA_STACK_FILES:-compose.yml compose.rocm.yml compose.webui.yml}"

COMPOSE_ARGS=()
for f in "${STACK_FILES[@]}"; do
    [[ -f "$f" ]] || { echo "Missing compose file: $f" >&2; exit 1; }
    COMPOSE_ARGS+=(-f "$f")
done

compose() { podman compose "${COMPOSE_ARGS[@]}" "$@"; }

# Keep the window open when started from the application menu, so errors stay readable.
pause_if_launcher() {
    [[ -n "${OLLAMA_STACK_LAUNCHER:-}" ]] || return 0
    echo
    read -rsn1 -p "Press any key to close this window..."
    echo
}
trap pause_if_launcher EXIT

banner() { printf '\n\033[1m%s\033[0m\n\n' "$1"; }

case "${1:-up}" in

up)
    banner "Starting Ollama stack"
    printf 'Project:  %s\n' "$PROJECT_DIR"
    printf 'Overlays: %s\n\n' "${STACK_FILES[*]}"

    # The compose provider needs the Podman socket.
    systemctl --user is-active --quiet podman.socket || {
        echo "Podman socket is not running, starting it..."
        systemctl --user start podman.socket
    }

    compose up -d

    banner "Running"
    compose ps

    printf '\nOllama API:  http://localhost:11434\n'
    if printf '%s\n' "${STACK_FILES[@]}" | grep -q webui; then
        printf 'Web UI:      http://localhost:3000\n'
    fi
    ;;

down)
    banner "Stopping Ollama stack"
    compose down
    printf '\nStopped. Downloaded models in ./models are kept.\n'
    ;;

logs)
    banner "Following logs - press Ctrl+C to stop watching"
    printf 'The containers keep running when you leave this view.\n\n'
    trap - EXIT   # Ctrl+C should close this window directly
    compose logs -f --tail 50
    ;;

status)
    banner "Ollama stack status"
    compose ps
    printf '\n'
    if curl -sf --max-time 3 http://localhost:11434/ >/dev/null 2>&1; then
        printf 'API:     up at http://localhost:11434\n'
        printf 'Models:  '
        curl -s http://localhost:11434/api/tags |
            sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | paste -sd', ' - || true
        printf '\n'
    else
        printf 'API:     not responding\n'
    fi
    ;;

*)
    echo "Usage: $0 {up|down|logs|status}" >&2
    exit 1
    ;;
esac
