# llama

Custom CUDA build of [llama.cpp](https://github.com/ggml-org/llama.cpp)'s
`llama-server`, targeting an NVIDIA GTX 1060 (Pascal, `sm_61`). See the root
[README](../README.md) for how this fits with the rest of the stack.

## Prerequisites (host setup)

These are one-time host-level steps — done outside of Docker, before
`docker compose up --build` will work. Assumes Debian (trixie) with a
non-free-firmware apt component already enabled (default since the Debian
12+ installer offers it) — adjust package names if you're on Ubuntu.

### 1. NVIDIA GPU driver

```bash
sudo apt install linux-headers-amd64          # kernel headers, needed by DKMS
sudo apt install nvidia-driver firmware-misc-nonfree
sudo apt install nvidia-kernel-dkms           # builds the kernel module via DKMS
```

Reboot, then confirm the GPU is visible:

```bash
lspci -nnk | grep -iA3 vga
nvidia-smi
```

Enabling persistence mode avoids a driver idle/power-transition state that
can otherwise slow down or fail the first CUDA init after a period of
inactivity — this matters here because it's exactly the kind of state
`entrypoint.sh`'s retry loop and `gpu-recover.sh` work around.

```bash
sudo systemctl enable --now nvidia-persistenced
```

That daemon alone doesn't guarantee persistence mode is *on* before Docker
starts containers at boot, so this setup also adds a custom oneshot unit
that runs `nvidia-smi -pm 1` ahead of `docker.service`:

```bash
sudo tee /etc/systemd/system/nvidia-persistence-mode.service <<'EOF'
[Unit]
Description=Enable NVIDIA persistence mode
Before=docker.service
After=nvidia-persistenced.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pm 1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now nvidia-persistence-mode.service
```

### 2. NVIDIA Container Toolkit

Lets Docker containers request GPU access (`--gpus all` / the
`deploy.resources.reservations.devices` block used in these compose files).

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify a container can see the GPU:

```bash
docker run --rm --gpus all nvidia/cuda:12.2.2-base-ubuntu22.04 nvidia-smi
```

### 3. Docker Compose GPU reservations

The compose files here use:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu, utility, compute]
```

This requires Docker Compose v2 (`docker compose`, not the legacy
`docker-compose` v1 binary) plus the `nvidia` runtime configured above.

### Known issue: wedged `nvidia_uvm` module

Because this GPU also drives the desktop (Xorg), repeated failed CUDA
context creation (or a driver power-state transition) can wedge the
`nvidia_uvm` kernel module — `nvidia-smi` keeps working, but container
CUDA init fails with `ggml_cuda_init: failed to initialize CUDA: unknown
error`. `entrypoint.sh` retries a few times to dodge the race on container
start; if it still fails, run `./gpu-recover.sh` to reload just that module
without a full reboot.

## Build & run

See the root [README](../README.md#usage) for compose usage — pick one of
the model variants and run `docker compose up -d --build`.
