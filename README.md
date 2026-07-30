# docker

Docker Compose configs for a home GPU-inference stack plus a couple of standalone
utility services. Each subfolder is an independent Compose project.

## Services

### llama/
A custom `llama-server:gtx1060` image (built from the local
`Dockerfile`) running [llama.cpp](https://github.com/ggml-org/llama.cpp)'s
`llama-server`, compiled for a GTX 1060 (CUDA arch `sm_61`). Serves an
OpenAI-compatible API on port `7000`.

- `Dockerfile` — multi-stage build: compiles `llama-server` with CUDA support,
  then copies it into a slim CUDA runtime image.
- `entrypoint.sh` — wraps `llama-server` with retry logic for a known CUDA
  context race on startup (see comments in the file).
- `gpu-recover.sh` — recovery script for a wedged `nvidia_uvm` kernel module
  (symptom: `ggml_cuda_init: failed to initialize CUDA: unknown error` while
  `nvidia-smi` still works). Reloads the module without a reboot and
  recreates the container.
- `models/` — GGUF model weights (gitignored-worthy, several GB each):
  Qwen2.5-Coder-3B, Qwen2.5-Coder-7B, DeepSeek-Coder-V2-Lite-Instruct.
- Compose files — several variants, one model configuration each:
  - `docker-compose.yml` — Qwen2.5-Coder-3B, joins the external `ai-network`
    (used together with `openwebui/`).
  - `docker-compose-qwen2_5-7b.yml` — Qwen2.5-Coder-7B, `ai-network` variant.
  - `docker-compose-qwen-2.5-coder-7b.yml` — Qwen2.5-Coder-7B bundled with its
    own `open-webui` service (standalone, no external network needed).
  - `docker-compose-deepsek-code-v2-lite-instruct.yml` — DeepSeek-Coder-V2-Lite
    (MoE), also bundled with its own `open-webui` service.

  Only run one model at a time — they all bind host port `7000`.

### openwebui/
[Open WebUI](https://github.com/open-webui/open-webui) chat frontend on port
`3000`, pointed at the `ai-network`-based `llama/` compose files via
`OPENAI_API_BASE_URLS`. Requires the external `ai-network` Docker network to
exist first.

### cloudbeaver/
[CloudBeaver](https://github.com/dbeaver/cloudbeaver) database UI on port
`8978`. Config in `.env` (DB connection settings — not committed values you
should reuse as-is). Workspace data lives on the host at
`/var/cloudbeaver/workspace`.

### portainer/
[Portainer CE](https://github.com/portainer/portainer) for Docker management,
on port `9443`. Mounts the host Docker socket, so it can manage this whole
stack.

## Usage

Standalone services:

```bash
cd cloudbeaver && docker compose up -d
cd portainer && docker compose up -d
```

GPU inference stack (llama-server + Open WebUI on a shared network):

```bash
docker network create ai-network   # once
cd llama && docker compose up -d --build   # pick ONE compose file / model
cd ../openwebui && docker compose up -d
```

Or run a bundled single-model + Open WebUI stack instead (no external network
needed):

```bash
cd llama && docker compose -f docker-compose-qwen-2.5-coder-7b.yml up -d --build
```

## Ports

| Service      | Port |
|--------------|------|
| llama-server | 7000 |
| Open WebUI   | 3000 |
| CloudBeaver  | 8978 |
| Portainer    | 9443 |
