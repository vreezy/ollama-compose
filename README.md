# podman-ai-stack

A local AI stack on Fedora, running rootless under Podman: a **chat LLM server**, a **browser UI**
for it, and **image generation** — each an optional piece you switch on with a compose overlay.

Everything is driven by `podman compose`. There is no daemon, nothing runs as root, and models and
data stay in folders you can see and back up rather than in anonymous volumes.

**What is in it**

- **[Ollama](https://ollama.com)** — runs chat models locally and serves them over an HTTP API,
  including an OpenAI-compatible endpoint.
- **[Open WebUI](https://github.com/open-webui/open-webui)** — a browser front-end for Ollama with
  chat history, model management and document upload.
- **[ComfyUI](https://github.com/comfyanonymous/ComfyUI)** — node-based image generation
  (Stable Diffusion and friends).
- **AMD GPU acceleration** via ROCm, for both Ollama and ComfyUI.

**Design choices**

- **Your data in your folders.** Ollama models land in [`models/`](models/), the whole ComfyUI tree
  in `comfyui/`. You can inspect them, back them up, copy them to another machine, or delete them
  with `rm`. They survive `podman compose down`.
- **Reachable from your network.** Services listen on all interfaces, so other machines and other
  containers can use them — not just `localhost`.
- **Nothing you did not ask for.** The base setup is Ollama on CPU. GPU support, the web UI and
  image generation are separate files you add when you want them.

The Ollama part started from [Running Ollama locally with Podman on Fedora Linux](https://fedoramagazine.org/running-ollama-locally-with-podman-on-fedora-linux/)
(Fedora Magazine) and grew from there.

---

## Contents

| File | Purpose |
|---|---|
| [`compose.yml`](compose.yml) | The base setup: Ollama on CPU |
| [`compose.rocm.yml`](compose.rocm.yml) | Overlay: AMD GPU acceleration for Ollama |
| [`compose.webui.yml`](compose.webui.yml) | Overlay: Open WebUI browser front-end |
| [`compose.comfyui.yml`](compose.comfyui.yml) | Overlay: ComfyUI image generation (AMD GPU) |
| [`models/`](models/) | Ollama models (contents excluded from Git) |
| `comfyui/` | ComfyUI tree: checkpoints, custom nodes, outputs (created on first start, excluded from Git) |

The overlays are independent and combine freely — see [Usage](#usage).

---

## Requirements

- **Fedora** (tested on Fedora 44) or any distribution with Podman 5.x. Other distributions work,
  but the `dnf` commands and the SELinux notes below are Fedora-specific.
- **Disk space.** Everything here is large. The base Ollama image is ~1.5 GB, the ROCm variant
  ~10 GB, Open WebUI ~4 GB and the ComfyUI image ~32 GB. Models add 2–5 GB each for LLMs and 4–7 GB
  per image-generation checkpoint. Budget generously.
- **RAM.** A 3B chat model needs roughly 4 GB free, a 7B model roughly 8 GB.
- **For GPU acceleration:** an AMD GPU supported by ROCm. NVIDIA needs a different image and the
  [container toolkit](#nvidia).

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
git clone <this-repo> podman-ai-stack
cd podman-ai-stack
```

> The folder name becomes the compose project name, which prefixes the named volumes
> (`podman-ai-stack_ollama-config` and so on). Pick a name you are happy to keep.

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
# Ollama on CPU — the base setup
podman compose up -d

# Ollama with AMD GPU acceleration
podman compose -f compose.yml -f compose.rocm.yml up -d

# Ollama plus the web UI
podman compose -f compose.yml -f compose.webui.yml up -d

# ComfyUI on its own — no Ollama involved
podman compose -f compose.comfyui.yml up -d

# Everything: Ollama on GPU, web UI and image generation
podman compose -f compose.yml -f compose.rocm.yml -f compose.webui.yml up -d
```

Chat and image generation are separate concerns, so
[`compose.comfyui.yml`](compose.comfyui.yml) is self-contained — it does not need
[`compose.yml`](compose.yml). Both files declare the same `ollama-net` network, which lets ComfyUI
run alone, run alongside Ollama, and reach it at `http://ollama:11434` when both are up.

Which ports that gives you:

| Service | URL | Enabled by |
|---|---|---|
| Ollama API | <http://localhost:11434> | always |
| Open WebUI | <http://localhost:3000> | `compose.webui.yml` |
| ComfyUI | <http://localhost:8188> | `compose.comfyui.yml` |

To avoid retyping the overlay list, put your preferred combination in an `.env` file:

```bash
echo 'COMPOSE_FILE=compose.yml:compose.rocm.yml:compose.comfyui.yml' > .env
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

## Image generation (ComfyUI)

[`compose.comfyui.yml`](compose.comfyui.yml) runs [ComfyUI](https://github.com/comfyanonymous/ComfyUI),
a node-based interface for Stable Diffusion and related image models.

### Starting it

ComfyUI is fully independent of Ollama, and normally you want just one of the two:

```bash
podman compose -f compose.comfyui.yml up -d
```

Open <http://localhost:8188>.

If you do want both — for workflows that have an LLM write or refine prompts — start them together
and ComfyUI can reach Ollama at `http://ollama:11434`:

```bash
podman compose -f compose.yml -f compose.rocm.yml -f compose.comfyui.yml up -d
```

> The image is about 32 GB, so the first pull takes a while. On first start it also unpacks a full
> ComfyUI tree into `comfyui/`, which takes another moment — until that finishes the port does not
> answer yet.

Check that it came up and is on the GPU:

```bash
curl -s http://localhost:8188/system_stats | jq '{version: .system.comfyui_version, device: .devices[0].name}'
```

```json
{
  "version": "0.15.0",
  "device": "cuda:0 AMD Radeon Graphics : native"
}
```

If `device` says `cpu`, the GPU was not picked up — see [Troubleshooting](#troubleshooting).
ROCm reports itself through PyTorch's CUDA API, so `cuda:0` is the correct and expected wording on
an AMD card.

### Adding models

ComfyUI ships **without** any models. Everything lives under `comfyui/models/`, which is a plain
folder on your host:

```
comfyui/models/
├── checkpoints/    # the main image models (SD 1.5, SDXL, Flux, ...)
├── loras/          # LoRA fine-tunes
├── vae/            # separate VAE files
├── controlnet/     # ControlNet models
├── upscale_models/ # ESRGAN and friends
└── ...
```

To install a model, drop the file into the matching folder — no container commands involved:

```bash
# example: Stable Diffusion 1.5 (~4 GB)
curl -L -o comfyui/models/checkpoints/v1-5-pruned-emaonly.safetensors \
  https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors
```

Then reload the ComfyUI page in your browser, or press **R**, and the checkpoint appears in the
loader node. A restart of the container is not needed.

[Civitai](https://civitai.com) and [Hugging Face](https://huggingface.co/models?pipeline_tag=text-to-image)
are the usual sources. Prefer `.safetensors` over `.ckpt`.

### Where your work is kept

Everything lives in `comfyui/` next to the compose files:

| Folder | Contents |
|---|---|
| `comfyui/models/` | the models you downloaded |
| `comfyui/output/` | generated images |
| `comfyui/input/` | images you upload for img2img, inpainting, ... |
| `comfyui/user/` | your workflows and UI settings |
| `comfyui/custom_nodes/` | installed extensions |

Because it is an ordinary folder, backing up means copying it, and installing a custom node means
cloning it into `comfyui/custom_nodes/` and restarting the container.

The folder is excluded from Git — it holds a full ComfyUI checkout plus many gigabytes of models.

### Updating

The container uses whatever ComfyUI version is in `comfyui/`, not the one baked into the image, so
you can update in place:

```bash
podman compose down
git -C comfyui pull
podman compose -f compose.yml -f compose.comfyui.yml up -d
```

To go back to the version shipped with the image, move the folder aside and let it repopulate:

```bash
podman compose down
mv comfyui comfyui.old
podman compose -f compose.yml -f compose.comfyui.yml up -d
```

### Removing it

If ComfyUI is all you were running:

```bash
podman compose -f compose.comfyui.yml down
```

If it was part of a larger stack, stop everything and start again without the overlay:

```bash
podman compose down
podman compose -f compose.yml -f compose.rocm.yml up -d   # continue without ComfyUI
```

To reclaim the space as well:

```bash
podman rmi docker.io/ignatberesnev/comfyui-gfx1151:v0.2   # ~32 GB
rm -rf comfyui/                                            # models, outputs and workflows
```

### A note on the image

The image is a community build targeting **gfx1151** (AMD Strix Halo / Ryzen AI MAX+ 395),
assembled on top of AMD's ROCm 7.2 PyTorch base:
[IgnatBeresnev/comfyui-gfx1151](https://github.com/IgnatBeresnev/comfyui-gfx1151). It is not an
official AMD or ComfyUI release. On other AMD architectures it may or may not work — verify with
the `system_stats` check above before assuming it does.

---

## Network access

### From other machines

The API listens on all interfaces (`OLLAMA_HOST=0.0.0.0:11434` in [`compose.yml`](compose.yml)), so
you only need to open the firewall:

```bash
sudo firewall-cmd --add-port=11434/tcp --permanent   # Ollama API
sudo firewall-cmd --add-port=3000/tcp --permanent    # Open WebUI
sudo firewall-cmd --add-port=8188/tcp --permanent    # ComfyUI
sudo firewall-cmd --reload
```

Find your address with `ip -4 addr show scope global | grep inet`, then from another machine:

```bash
curl http://<HOST-IP>:11434/api/version
```

> **Ollama and ComfyUI have no authentication.** Anyone who can reach port 11434 or 8188 can use
> your models, delete them, change your workflows and saturate your hardware. Only expose them on a
> network you trust, and never forward those ports from the internet. If you need remote access, put
> a reverse proxy with authentication in front. Open WebUI on port 3000 *does* have real user
> accounts.

To keep a service local only, change its mapping to bind to the loopback address — for example in
[`compose.yml`](compose.yml):

```yaml
    ports:
      - "127.0.0.1:11434:11434"
```

If you still want to reach it from your own laptop, an SSH tunnel gives you access without opening
anything to the network:

```bash
ssh -L 8188:localhost:8188 user@host    # then open http://localhost:8188 locally
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

### More GPU memory on the HP ZBook Ultra G1a

Applies to the reference machine: HP ZBook Ultra G1a 14", Ryzen AI MAX+ PRO 395 / Radeon 8060S,
64 GB RAM, BIOS X89 Ver. 01.06.02, Fedora 44. The goal is an even split of 32 GB for the GPU and
32 GB for the system.

The iGPU can use two kinds of memory:

- **VRAM carve-out**: set in the BIOS. This RAM is reserved for the GPU permanently and is invisible
  to Linux, even when no model is loaded. The factory setting is 16 GB.
- **GTT**: ordinary system RAM that the GPU borrows on demand. By default it is capped at half of
  the RAM that Linux sees. **On this iGPU, Ollama counts only the GTT limit** as its usable VRAM.

With the factory setting, Linux sees 46 GB and the GTT limit is 23.4 GiB, so Ollama reports
`total="23.4 GiB"` while most of the 16 GB carve-out sits unused. The fix is to shrink the
carve-out and raise the GTT limit instead.

**1. BIOS: shrink the carve-out.** Reboot straight into the firmware setup:

```bash
systemctl reboot --firmware-setup
```

You can also press **F10** repeatedly while the machine powers on (**Esc** opens the HP startup
menu). Find the setting for dedicated graphics memory (labelled "Dedicated …"), set it to the
minimum, and tick the option that lets the operating system manage the allocation. Save with
**F10**.

**2. Kernel: raise the GTT limit to 32 GiB.** The limit is given in 4 KiB pages:
32 × 1024³ / 4096 = `8388608`.

```bash
sudo grubby --update-kernel=ALL --args="ttm.pages_limit=8388608 ttm.page_pool_size=8388608"
sudo reboot
```

**3. Verify** after the reboot:

```bash
free -g                                               # total: 62
cat /sys/class/drm/card1/device/mem_info_vram_total   # 536870912 (512 MB carve-out)
cat /sys/class/drm/card1/device/mem_info_gtt_total    # 34359738368 (32 GiB)
cat /sys/module/ttm/parameters/pages_limit            # 8388608
podman compose logs ollama | grep "inference compute" # total="32.0 GiB"
```

| | Factory | After |
|---|---|---|
| VRAM carve-out | 16 GB | 512 MB |
| RAM visible to Linux | 46 GB | 62 GB |
| GTT limit / reported by Ollama | 23.4 GiB | 32.0 GiB |

The GPU takes the 32 GiB only while a model is loaded. When it is idle, the memory is available to
the system. To give the GPU more, use a larger page count. For example, `12582912` is 48 GiB.
Ollama raises its automatic default context above 32768 only from 48 GiB upwards.

To undo the kernel change:

```bash
sudo grubby --update-kernel=ALL --remove-args="ttm.pages_limit ttm.page_pool_size"
```

> Do not set the carve-out to 32 GB in the BIOS instead. That memory would be lost to the system at
> all times, and Ollama would not count it anyway.

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

**ComfyUI does not answer on port 8188**

On the very first start it unpacks a full ComfyUI tree into `comfyui/`, and the port stays closed
until that is done. Watch it happen:

```bash
podman compose logs -f comfyui
```

**ComfyUI runs on the CPU, or crashes when generating**

Confirm what PyTorch actually sees:

```bash
podman exec comfyui python3 -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_properties(0).gcnArchName)"
```

You want `True` and your GPU architecture. Note that detection alone is not proof — some ROCm
builds report a GPU correctly and then segfault on the first allocation. Test a real one:

```bash
podman exec comfyui python3 -c "import torch; print(float(torch.randn(64,64,device='cuda').sum()))"
```

If that segfaults, the image does not support your GPU architecture, and no environment variable
will fix it. Use an image built for your card.

**ComfyUI does not list a model you downloaded**

Reload the browser page (or press **R**). If it still does not show up, check that the file landed
in the right subfolder of `comfyui/models/` and is a `.safetensors` or `.ckpt` file.

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
podman volume ls | grep open-webui-data     # find the exact name
podman volume rm <prefix>_open-webui-data
```

**`/api/embed` returns an empty array**

Chat models cannot produce embeddings. Use `nomic-embed-text` or `mxbai-embed-large`.

---

## Uninstalling

```bash
podman compose down

podman rmi docker.io/ollama/ollama:latest docker.io/ollama/ollama:rocm
podman rmi ghcr.io/open-webui/open-webui:main             # if you used the web UI
podman rmi docker.io/ignatberesnev/comfyui-gfx1151:v0.2   # if you used ComfyUI

rm -rf models/     # all Ollama models
rm -rf comfyui/    # ComfyUI checkout, checkpoints, workflows and generated images
```

The named volumes are prefixed with the compose project name, which defaults to the name of the
folder you cloned into. List them first, then remove the ones you recognise:

```bash
podman volume ls
podman volume rm <prefix>_ollama-config
podman volume rm <prefix>_open-webui-data    # deletes all chats and accounts
```
