# syntax=docker/dockerfile:1
FROM python:3.13-slim AS base

# Pull the uv binary from Astral's distroless image instead of installing via pip.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH" \
    HF_HOME=/app/.cache/huggingface \
    LAYA_HOST=0.0.0.0 \
    LAYA_PORT=8080 \
    LAYA_PRELOAD=1

# Install dependencies first so they're cached separately from app code changes.
COPY pyproject.toml uv.lock README.md ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

COPY . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# uv.lock pins CPU-only torch (tool.uv.sources in pyproject.toml) so the default
# build never drags in the ~6-8GB of bundled CUDA libraries a Linux torch wheel
# normally carries. Set BACKEND=gpu to swap it for a CUDA build for GPU hosts
# (e.g. a DigitalOcean GPU Droplet) -- LAYA_DEVICE stays "auto" either way, so
# the same image just uses whatever the host actually gives it at runtime.
ARG BACKEND=cpu
ARG TORCH_CUDA_TAG=cu130
RUN --mount=type=cache,target=/root/.cache/uv \
    if [ "$BACKEND" = "gpu" ]; then \
        uv pip install --python .venv/bin/python --reinstall \
            --index-url "https://download.pytorch.org/whl/${TORCH_CUDA_TAG}" torch; \
    fi

# Which checkpoint this tag ships: english | multilingual | typed-decisions.
# Baked in at build time so the container serves offline with no cold-start download.
ARG LAYA_MODEL=english
ENV LAYA_MODELS=${LAYA_MODEL}

# HF_TOKEN is only needed for gated/private checkpoints or to raise rate limits; the
# published convaiinnovations/laya repos are public. Passed as a build secret (never
# baked into an image layer) via: docker build --secret id=hf_token,env=HF_TOKEN
RUN --mount=type=secret,id=hf_token,required=false \
    sh -c 'if [ -f /run/secrets/hf_token ]; then export HF_TOKEN="$(cat /run/secrets/hf_token)"; fi; \
           python -c "from laya.serve import build_router; build_router()"'

RUN groupadd --system laya && useradd --system --gid laya --home-dir /app laya \
    && chown -R laya:laya /app
USER laya

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=3)" || exit 1

CMD ["python", "-m", "laya.serve"]
