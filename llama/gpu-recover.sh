#!/bin/bash
# Recovers from a wedged nvidia_uvm module without a full reboot.
#
# Symptom: llama-server logs show
#   ggml_cuda_init: failed to initialize CUDA: unknown error
# while `nvidia-smi` still works fine and dmesg shows no Xid/NVRM errors.
#
# Root cause: the GPU also drives the desktop (Xorg), and after enough failed
# CUDA context creation attempts (or a driver idle/power transition), the
# nvidia_uvm kernel module can get stuck. Reloading just that module clears
# it without touching nvidia_drm/nvidia_modeset (what the desktop uses), so
# it doesn't require logging out or a reboot.
set -euo pipefail

echo "Stopping ksystemstats (releases its nvidia-smi dmon handle on /dev/nvidia-uvm)..."
systemctl --user stop plasma-ksystemstats.service || true

echo "Reloading nvidia_uvm..."
sudo rmmod nvidia_uvm
sudo modprobe nvidia_uvm

echo "Restarting ksystemstats..."
systemctl --user start plasma-ksystemstats.service || true

echo "Recreating the llama-server container..."
docker compose -f /home/jansmolko/docker/llama/docker-compose.yml \
  up -d --force-recreate llama-server-qwen2_5-coder-3b-instruct-q4_k_m

echo
echo "Tailing logs - confirm there's no 'ggml_cuda_init: failed' line, then Ctrl+C:"
docker logs -f llama-server-qwen2_5-coder-3b-instruct-q4_k_m
