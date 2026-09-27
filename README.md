# laya-play

A REST wrapper around [Laya](https://github.com/convaiinnovations/laya), a
small "System-1" decision model: one forward pass answers several
`choice` / `score` / `noul` questions about a piece of text (routing,
urgency, sentiment, etc.) in tens of milliseconds.

This repo packages Laya's built-in `laya[serve]` HTTP server as Docker
images — no server code needed, `laya-serve` ships the whole API.

## REST API

`POST /v1/systemone` implements the TypeSafe Jev `/v1/systemone` wire
protocol: send `state` (the text) and `questions` (a dict of `choice` /
`score` / `noul` questions), get back `answers`, `usage`, and `routing`.

```bash
curl http://localhost:8080/v1/systemone \
  -H 'Content-Type: application/json' \
  -d '{
    "state": {"message": "I was charged twice for invoice 4411. Please refund me today."},
    "questions": {
      "route": {
        "type": "choice",
        "instructions": "Where should this ticket go?",
        "criteria": {"billing": "payments, refunds, invoices", "bug": "the product is broken", "account": "login or access"}
      },
      "urgency": {
        "type": "score",
        "instructions": "How urgent is this message?",
        "criteria": ["routine, no rush", "today", "urgent", "critical, about to churn"]
      },
      "escalate": {"type": "noul", "instructions": "Escalate to a human immediately?"}
    }
  }'
```

`GET /health` reports which checkpoints are loaded.

## Image tags

Each image bakes in **one** Laya checkpoint and **one** compute backend at
build time (`ARG LAYA_MODEL` / `ARG BACKEND` in the [Dockerfile](Dockerfile)),
so the container serves offline with no cold-start download. Every tag is a
multi-arch manifest covering both `linux/amd64` and `linux/arm64`.

| checkpoint | source | size (approx.) | notes |
|---|---|---|---|
| `english` | `convaiinnovations/laya` | ~2.4 GB weights | root/English, largest checkpoint — used for `:latest` |
| `multilingual` | `convaiinnovations/laya-multilingual` | ~0.7 GB weights | multi-language |
| `typed-decisions` | `convaiinnovations/laya-typed-decisions` | ~0.85 GB weights | typed decision schema |

Combined with backend, that's six concrete tags plus three aliases:

| tag | resolves to |
|---|---|
| `english-cpu`, `english-gpu` | English checkpoint, CPU or CUDA torch build |
| `multilingual-cpu`, `multilingual-gpu` | Multilingual checkpoint |
| `typed-decisions-cpu`, `typed-decisions-gpu` | Typed-decisions checkpoint |
| `latest`, `cpu` | alias for `english-cpu` |
| `gpu` | alias for `english-gpu` |

**`cpu` images are CUDA-free** — `uv.lock` pins torch to PyTorch's CPU-only
wheel index for Linux (`[tool.uv.sources]` in `pyproject.toml`), which drops
~15 NVIDIA/CUDA/triton packages nobody needs without a GPU (cut a test image
from 22 GB down to ~6 GB). **`gpu` images** reinstall a CUDA-enabled torch
wheel (`cu130`) on top of that base, for GPU hosts (e.g. a DigitalOcean GPU
Droplet). `LAYA_DEVICE` stays `auto` in both, so the same image just uses
whatever the host actually gives it at runtime.

## a. Use the published image (GHCR) — no build required

Images are published to `ghcr.io/teochenglim/laya` by
[CI](#ci-multi-arch-cpugpu-matrix) on every push to `main`:

```bash
# CPU, default checkpoint (english) — runs anywhere, no GPU needed
docker run -p 8080:8080 ghcr.io/teochenglim/laya

# a specific checkpoint / backend
docker run -p 8080:8080 ghcr.io/teochenglim/laya:multilingual-cpu

# GPU host (needs the NVIDIA Container Toolkit installed on the host)
docker run --gpus all -p 8080:8080 ghcr.io/teochenglim/laya:gpu
```

GHCR images are public, so no `docker login` is needed to pull them.

## b. Build and push (Docker Hub)

Maintainer flow — builds bake in model weights, so this needs Docker
credentials for `teochenglim/laya` and, optionally, `HF_TOKEN` in `.env`
(passed in as a build secret, never baked into a layer, only used to raise
Hugging Face rate limits since the checkpoints are public).

```bash
make build MODEL=english BACKEND=cpu   # single variant, local only
make build-all                         # all 3 models x 2 backends, local only

make push MODEL=english BACKEND=gpu    # build + push one tag, e.g. english-gpu
make push-all                          # build + push every tag
make push-aliases                      # point :latest / :cpu / :gpu at english
```

`push`/`push-all` use `docker buildx build --push` in a single step (not a
separate `build` then `push`) — on containerd-backed Docker (e.g. colima)
doing those separately can drop an attestation-manifest blob and fail push
with `content digest ... not found`. `ghcr-*` targets do the same against
GHCR instead of Docker Hub.

## c. Run locally

**Without Docker:**

```bash
uv sync
uv run python laya_init.py   # one-shot example, see laya_init.py
uv run laya-serve             # or: make serve — starts the REST API on :8000
```

**With Docker**, against whatever you just built or pulled:

```bash
make run MODEL=english BACKEND=cpu   # runs on :8080
make test                            # curl /health + /v1/systemone
make stop                            # stop the local container
```

Server env vars (set at `docker run` time, see `laya/serve.py`):

| env var | meaning | default |
|---|---|---|
| `LAYA_HOST` / `LAYA_PORT` | bind address | `0.0.0.0` / `8080` in the image |
| `LAYA_API_KEY` | require `Authorization: Bearer <key>` | unset (open) |
| `LAYA_MODELS` | which checkpoint(s) to preload | baked in at build time |
| `LAYA_DEVICE` | torch device | auto |
| `LAYA_THREADS` | cap CPU intra-op threads | torch default |

Set `LAYA_API_KEY` for anything beyond localhost — the endpoint has no auth
by default.

## CI: multi-arch CPU/GPU matrix

[`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml)
runs on every push to `main` (also on version tags / manual dispatch) and:

1. **`build`** — a `{model} x {backend} x {platform}` matrix (3 x 2 x 2 = 12
   jobs) builds each arch on its *native* runner (`ubuntu-latest` for amd64,
   `ubuntu-24.04-arm` for arm64 — no QEMU, since the build itself loads a
   multi-GB checkpoint and emulating that would be slow and flaky), pushing
   arch-specific staging tags like `english-cpu-amd64`.
2. **`merge`** — combines each pair into one multi-arch manifest under the
   public tag (e.g. `english-cpu`) via `docker buildx imagetools create`
   (registry-side, no pull needed).
3. **`tag-aliases`** — points `:latest`, `:cpu`, `:gpu` at the `english`
   checkpoint, same registry-side technique.

It authenticates with the repo's own `GITHUB_TOKEN` — no setup needed beyond
enabling Actions and, optionally, adding an `HF_TOKEN` repository secret for
higher Hugging Face rate limits during the build.
