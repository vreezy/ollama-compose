# Ollama with Podman Compose on Fedora

Run [Ollama](https://ollama.com) — a local LLM server — as a rootless container on Fedora, with
your models stored in the project folder instead of an anonymous volume.

Everything is driven by `podman compose`. There is no daemon, nothing runs as root, and the whole
setup is three small YAML files you can read in a minute.

**What you get**

- **Models in a folder you control.** They land in [`models/`](models/) right next to the compose
  file, so you can see them, back them up, move them to another machine, or delete them with `rm`.
  They survive `podman compose down`.
- **Reachable from your network.** The API listens on all interfaces, so other machines and other
  containers can use it. Not just `localhost`.
- **Optional AMD GPU acceleration** via ROCm, as a compose overlay you switch on when you want it.
- **Optional web UI** ([Open WebUI](https://github.com/open-webui/open-webui)), also as an overlay.

Inspired by [Running Ollama locally with Podman on Fedora Linux](https://fedoramagazine.org/running-ollama-locally-with-podman-on-fedora-linux/)
from Fedora Magazine, extended with persistent model storage, network access, GPU support and a UI.

---

## Contents

| File | Purpose |
|---|---|
| [`compose.yml`](compose.yml) | The base setup: Ollama on CPU |
| [`compose.rocm.yml`](compose.rocm.yml) | Overlay: AMD GPU acceleration (ROCm) |
| [`compose.webui.yml`](compose.webui.yml) | Overlay: Open WebUI browser front-end |
| [`models/`](models/) | Where models are stored (contents excluded from Git) |

The overlays are independent and combine freely — see [Usage](#usage).

---

## Requirements

- **Fedora** (tested on Fedora 44) or any distribution with Podman 5.x. Other distributions work,
  but the `dnf` commands and the SELinux notes below are Fedora-specific.
- **Disk space.** Models are large: 2–5 GB each, and the ROCm image alone is about 10 GB.
- **RAM.** A 3B model needs roughly 4 GB free, a 7B model roughly 8 GB.
- **For GPU acceleration:** an AMD GPU supported by ROCm, or an NVIDIA card with the
  [NVIDIA container toolkit](#nvidia).

---

## Installation

This walks through a **freshly installed Fedora** with nothing container-related set up yet.

### 1. Install Podman and a compose provider

```bash
sudo dnf install -y podman docker-compose
```

| Package | Why |
|---|---|
| `podman` | The container engine. No daemon, runs rootless under your own user account. |
| `docker-compose` | The compose provider Podman delegates to. **This is not Docker** — it is the Go implementation of the Compose v2 specification. Podman finds it automatically. |

> **Why not `podman-compose`?** Podman works with either provider, but `podman-compose` 1.6.0 does
> not implement the compose key `ipc:` and silently ignores it. The base CPU setup runs fine either
> way; the [GPU overlay](#amd-gpu-rocm) needs `ipc: host` and will fail without it. Installing
> `docker-compose` avoids the problem entirely.
>
> Do **not** install the `docker` package. It is not needed.

Optionally, `jq` makes the JSON output of the API examples further down easier to read:

```bash
sudo dnf install -y jq
```

### 2. Enable the Podman socket

The compose provider talks to Podman through a Docker-compatible socket, which is not active on a
fresh system. Enable it once as your **normal user** — no `sudo`:

```bash
systemctl --user enable --now podman.socket
```

Without this step every compose command fails with:

```
Cannot connect to the Docker daemon at unix:///run/user/1000/podman/podman.sock.
Is the docker daemon running?
```

### 3. Verify

```bash
podman --version          # tested with 5.8.4
podman compose version    # tested with Docker Compose 5.4.0
```

`podman compose` prints a notice naming the external provider it uses on every invocation. That is
normal, not an error.

### 4. Get the files

```bash
git clone <this-repo>
cd ollama-compose
```

### 5. Optional: survive logout and reboot

Rootless containers stop when your user session ends. To keep them running:

```bash
loginctl enable-linger $USER
systemctl --user enable --now podman-restart.service
```

---

## Usage

### Starting

Pick the combination you want:

```bash
# CPU only — the base setup
podman compose up -d

# With AMD GPU acceleration
podman compose -f compose.yml -f compose.rocm.yml up -d

# With the web UI
podman compose -f compose.yml -f compose.webui.yml up -d

# Both
podman compose -f compose.yml -f compose.rocm.yml -f compose.webui.yml up -d
```

To avoid retyping the overlay list, put your preferred combination in an `.env` file:

```bash
echo 'COMPOSE_FILE=compose.yml:compose.rocm.yml' > .env
```

From then on a plain `podman compose up -d` uses it.

### First model

Ollama ships without any models. Pull one:

```bash
podman compose exec ollama ollama pull llama3.2:3b
```

Then talk to it interactively:

```bash
podman compose exec ollama ollama run llama3.2:3b
```

Leave the chat with `/bye`.

### Everyday commands

```bash
podman compose ps                # what is running
podman compose logs -f           # follow the logs
podman compose restart           # restart
podman compose down              # stop and remove; models are kept
podman compose pull              # update the images
```

### Managing models

```bash
podman compose exec ollama ollama list             # installed models
podman compose exec ollama ollama pull qwen2.5:7b  # download
podman compose exec ollama ollama rm qwen2.5:7b    # delete
podman compose exec ollama ollama ps               # what is loaded in memory
```

Some models to start from:

| Model | Size | Notes |
|---|---|---|
| `llama3.2:1b` | ~1.3 GB | very fast, simple tasks |
| `llama3.2:3b` | ~2.0 GB | good general starting point |
| `qwen2.5:7b` | ~4.7 GB | noticeably stronger, still comfortable on 16 GB RAM |
| `gpt-oss:20b` | ~14 GB | needs a lot of memory |
| `nomic-embed-text` | ~274 MB | embeddings only, cannot chat |

The full catalogue is at [ollama.com/library](https://ollama.com/library).

### Where the models are stored

In [`models/`](models/), inside the project:

```
models/
├── blobs/         # the actual weights
└── manifests/     # which tag maps to which blobs
```

This is driven by `OLLAMA_MODELS=/models` plus the bind mount `./models:/models:Z` in
[`compose.yml`](compose.yml).

> **The `:Z` matters on Fedora.** SELinux runs in enforcing mode and would deny the container
> access to the host folder without a matching label. `:Z` applies it automatically. If you drop
> it, you get `permission denied`.

Models are excluded from Git via [`.gitignore`](.gitignore) — only the empty folder is tracked.

### Web UI

Ollama has no web interface of its own; the container is an API server, which is why
`curl http://localhost:11434/` answers with the plain string `Ollama is running`. The overlay
[`compose.webui.yml`](compose.webui.yml) adds [Open WebUI](https://github.com/open-webui/open-webui)
as a second container:

```bash
podman compose -f compose.yml -f compose.webui.yml up -d
```

Open <http://localhost:3000>. **The first account you create becomes the administrator**, so do
that before letting anyone else reach the port.

It gives you model management from the browser, persistent chat history, document upload with RAG,
reusable system prompts and multi-user accounts. The image is around 4 GB. Its data lives in a
named volume, not in this folder.

The UI reaches Ollama over the shared container network at `http://ollama:11434`, and `depends_on`
holds it back until Ollama reports healthy, so it never starts against a dead backend.

---

## Network access

### From other machines

The API listens on all interfaces (`OLLAMA_HOST=0.0.0.0:11434` in [`compose.yml`](compose.yml)), so
you only need to open the firewall:

```bash
sudo firewall-cmd --add-port=11434/tcp --permanent
sudo firewall-cmd --add-port=3000/tcp --permanent   # only if you use the web UI
sudo firewall-cmd --reload
```

Find your address with `ip -4 addr show scope global | grep inet`, then from another machine:

```bash
curl http://<HOST-IP>:11434/api/version
```

> **Ollama has no authentication.** Anyone who can reach port 11434 can use your models, delete
> them, and saturate your hardware. Only expose it on a network you trust, and never forward the
> port from the internet. If you need remote access, put a reverse proxy with authentication in
> front of it. Open WebUI on port 3000 *does* have real user accounts.

To keep it local only, change the mapping in [`compose.yml`](compose.yml):

```yaml
    ports:
      - "127.0.0.1:11434:11434"
```

### From other containers

[`compose.yml`](compose.yml) creates a network with the fixed name `ollama-net`. Other compose
projects can join it as an external network and reach Ollama by hostname — no IP addresses, no port
mappings:

```yaml
services:
  my-app:
    image: my-app:latest
    environment:
      OLLAMA_BASE_URL: "http://ollama:11434"
    networks:
      - ollama-net

networks:
  ollama-net:
    external: true
    name: ollama-net
```

Start this project first so the network exists. Verify from any container:

```bash
podman run --rm --network ollama-net docker.io/curlimages/curl \
  -s http://ollama:11434/api/version
```

---

## Using the API

All examples target `localhost`; from another machine, substitute its address. `jq` is only used to
extract fields from the JSON — without it you see the full response.

### Check that the server is up

```bash
curl http://localhost:11434/
```

```
Ollama is running
```

### List installed models

```bash
curl -s http://localhost:11434/api/tags | jq -c '.models[] | {name, size}'
```

```json
{"name":"llama3.2:3b","size":2019393189}
{"name":"qwen2.5:7b","size":4683087332}
```

### Generate text

```bash
curl -s http://localhost:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt": "Say hello",
  "stream": false
}' | jq -r '.response'
```

```
Hello! It's nice to meet you. Is there something I can help you with or would you like to chat?
```

### Chat with roles

```bash
curl -s http://localhost:11434/api/chat -d '{
  "model": "llama3.2:3b",
  "messages": [
    {"role": "system", "content": "Answer briefly."},
    {"role": "user", "content": "What is Podman?"}
  ],
  "stream": false
}' | jq -r '.message.content'
```

### Stream the response

Drop `"stream": false` and the answer arrives token by token as newline-delimited JSON:

```bash
curl -N http://localhost:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt": "Count from 1 to 5."
}'
```

### OpenAI-compatible endpoint

Ollama also speaks the OpenAI API format, so existing clients and SDKs work unchanged:

```bash
curl -s http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.2:3b",
    "messages": [{"role": "user", "content": "Say hello"}]
  }' | jq -r '.choices[0].message.content'
```

In an SDK, set `base_url` to `http://localhost:11434/v1`. The API key is ignored — any placeholder
works.

### Embeddings

Requires an embedding model. Chat models return an empty result here:

```bash
podman compose exec ollama ollama pull nomic-embed-text

curl -s http://localhost:11434/api/embed -d '{
  "model": "nomic-embed-text",
  "input": "Podman is a container runtime"
}' | jq '.embeddings[0] | length'
```

```
768
```

### Measure throughput

The response carries timing data, so you can compute tokens per second directly:

```bash
curl -s http://localhost:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt": "Explain container virtualization in 8 sentences.",
  "stream": false
}' | jq -r '"\(.eval_count/(.eval_duration/1e9)|round) tok/s"'
```

---

## GPU acceleration

### AMD GPU (ROCm)

The overlay [`compose.rocm.yml`](compose.rocm.yml) swaps in the `ollama/ollama:rocm` image, passes
`/dev/kfd` and `/dev/dri` through to the container, and sets `ipc: host`:

```bash
podman compose -f compose.yml -f compose.rocm.yml up -d
```

> The ROCm image is around 10 GB. The first pull takes a while.

**`ipc: host` is required, not a tuning option.** Without the host IPC namespace the ROCm runtime
aborts as soon as it loads a model:

```
Memory critical error by agent node-0 ... Reason: Memory in use.
llama-server process has terminated: signal: aborted (core dumped)
```

`shm_size`, a `/dev/shm` bind mount, `privileged: true`, `userns_mode: host` and `pid: host` were
all tested as substitutes and none of them work. This is also why the setup needs `docker-compose`
rather than `podman-compose` — see [Installation](#1-install-podman-and-a-compose-provider).

Check that the GPU was detected:

```bash
podman compose logs ollama | grep "inference compute"
```

```
msg="inference compute" id=0 library=ROCm compute=gfx1151 name=ROCm0
  description="Radeon 8060S Graphics" type=iGPU total="23.4 GiB" available="40.5 GiB"
```

And that it is actually being used — load a model, then:

```bash
podman compose exec ollama ollama ps
```

```
NAME           ID              SIZE      PROCESSOR    CONTEXT
llama3.2:3b    a80c4f17acd5    5.9 GB    100% GPU     32768
```

If your GPU is not detected, uncomment `HSA_OVERRIDE_GFX_VERSION` in
[`compose.rocm.yml`](compose.rocm.yml) and set the version matching your architecture — `11.5.1`
for Strix Halo, `11.0.0` for RDNA3 desktop cards. Many ROCm generations need this; gfx1151 does not.

### NVIDIA

Install the container toolkit and generate the CDI specification:

```bash
sudo dnf install -y nvidia-container-toolkit
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
nvidia-ctk cdi list
```

Then create `compose.nvidia.yml`:

```yaml
services:
  ollama:
    devices:
      - nvidia.com/gpu=all
    security_opt:
      - label=disable
```

```bash
podman compose -f compose.yml -f compose.nvidia.yml up -d
```

> Untested — the reference system has no NVIDIA hardware.

---

## Benchmarks: CPU vs. GPU

Whether the GPU is worth enabling depends on the model size, and on integrated GPUs the answer is
not always yes. These numbers come from the setup in this repository, measured with the
[throughput command](#measure-throughput) above.

### Reference system

| | |
|---|---|
| CPU | AMD Ryzen AI MAX+ PRO 395 — 16 cores / 32 threads (Zen 5) |
| GPU | Radeon 8060S, integrated (RDNA 3.5, `gfx1151`), 23.4 GiB addressable as VRAM |
| Memory | 46 GiB unified, shared between CPU and GPU |
| OS | Fedora 44, kernel 7.1.7 |
| Software | Podman 5.8.4, Ollama 0.32.9, ROCm runtime `rocm_v7_2` |

Both runs used identical models and prompts; the only change was the ROCm overlay. Single request
at a time, no batching.

### Results

| Model | Quantization | CPU | GPU | Difference |
|---|---|---|---|---|
| `llama3.2:3b` | Q4_K_M | **33 tok/s** | 30 tok/s | CPU ahead by ~10% |
| `qwen2.5:7b` | Q4_K_M | 16 tok/s | **21 tok/s** | GPU ahead by ~31% |

### What this means

**Below ~3B parameters the integrated GPU gains you nothing here.** Single-request inference is
limited by memory bandwidth rather than raw compute, and because this is an APU, CPU and GPU share
the same memory bus. There is no bandwidth advantage to win, and 16 Zen 5 cores keep up comfortably.

**From ~7B upwards the GPU pulls ahead** and the gap widens with model size, because the amount of
arithmetic per byte of loaded weights grows and parallel compute starts to matter.

**On a discrete graphics card the picture is different.** Dedicated VRAM has several times the
bandwidth of system memory, so the GPU wins across the board — provided the model fits in VRAM.

Practical takeaway: if you mostly run small models, the CPU setup is simpler and just as fast. If
you run 7B and larger, enable the GPU overlay. Measure your own mix rather than trusting either
answer — the [throughput command](#measure-throughput) takes ten seconds.

---

## Configuration

The settings live in the `environment` block of [`compose.yml`](compose.yml):

| Variable | Default here | Meaning |
|---|---|---|
| `OLLAMA_HOST` | `0.0.0.0:11434` | Address and port Ollama listens on |
| `OLLAMA_MODELS` | `/models` | Where models are stored (mapped to `./models`) |
| `OLLAMA_KEEP_ALIVE` | `5m` | How long a model stays in memory after the last request. `-1` keeps it loaded forever |
| `OLLAMA_NUM_PARALLEL` | `1` | Concurrent requests per model |
| `OLLAMA_ORIGINS` | `*` | Allowed CORS origins for browser clients |
| `OLLAMA_MAX_LOADED_MODELS` | unset | How many models may be resident at once |
| `OLLAMA_CONTEXT_LENGTH` | unset | Default context window, e.g. `8192` |

---

## Troubleshooting

**`Cannot connect to the Docker daemon at unix:///run/user/1000/podman/podman.sock`**

The Podman socket is not running:

```bash
systemctl --user enable --now podman.socket
```

**`llama-server process has terminated: signal: aborted (core dumped)`**

The GPU overlay is running without the host IPC namespace. Check:

```bash
podman inspect ollama --format '{{.HostConfig.IpcMode}}'
```

It must print `host`. If it prints `shareable`, `podman-compose` handled the file and dropped the
`ipc:` key — install `docker-compose` as described in [Installation](#1-install-podman-and-a-compose-provider).

**`permission denied` on `/models`**

SELinux. Make sure the bind mount in [`compose.yml`](compose.yml) still carries `:Z`, or relabel by
hand:

```bash
podman compose down
chcon -Rt container_file_t models/
podman compose up -d
```

**Port 11434 already in use**

Usually a native Ollama installation running as a system service:

```bash
ss -tlnp | grep 11434
sudo systemctl disable --now ollama
```

**Not reachable from another machine**

Check in order: locally with `curl http://localhost:11434/`, then the firewall with
`sudo firewall-cmd --list-ports`, then `OLLAMA_HOST` in [`compose.yml`](compose.yml).

**Open WebUI shows no models**

Check whether it can reach the backend:

```bash
podman exec open-webui curl -s http://ollama:11434/api/tags
```

If that fails, the containers are not on the same network. If it succeeds but the UI stays empty,
no models are installed yet.

**Forgot the Open WebUI admin password**

There is no reset from outside. Wipe its data and start over — this deletes all chats and accounts:

```bash
podman compose down
podman volume rm ollama-compose_open-webui-data
```

**`/api/embed` returns an empty array**

Chat models cannot produce embeddings. Use `nomic-embed-text` or `mxbai-embed-large`.

---

## Uninstalling

```bash
podman compose down

podman rmi docker.io/ollama/ollama:latest docker.io/ollama/ollama:rocm
podman rmi ghcr.io/open-webui/open-webui:main      # if you used the web UI

podman volume ls                                   # names are prefixed with the project name
podman volume rm ollama-compose_ollama-config
podman volume rm ollama-compose_open-webui-data    # deletes all chats and accounts

rm -rf models/*                                    # deletes all downloaded models
```
