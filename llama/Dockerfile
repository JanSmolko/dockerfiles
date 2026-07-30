FROM nvidia/cuda:12.2.2-devel-ubuntu22.04 AS builder

RUN apt-get update && apt-get install -y git build-essential cmake

# 1. Create the missing libcuda.so.1 stub symlink for the linker
RUN ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

# 2. Expose the CUDA stubs directory to the linker during build
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs:${LD_LIBRARY_PATH}
ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs:${LIBRARY_PATH}

WORKDIR /app
RUN git clone https://github.com/ggml-org/llama.cpp.git .

# 3. Target GTX 1060 Pascal architecture (sm_61)
RUN cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61
RUN cmake --build build --config Release -j$(nproc) --target llama-server

# Final lightweight runtime container
FROM nvidia/cuda:12.2.2-runtime-ubuntu22.04
WORKDIR /app

# Install runtime dependencies (OpenMP)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy all executables AND shared libraries (.so files) from build/bin
COPY --from=builder /app/build/bin/ /app/

# Tell Linux to look in /app for the shared libraries (libllama-server-impl.so, etc.)
ENV LD_LIBRARY_PATH=/app:${LD_LIBRARY_PATH}

# Retries CUDA init a few times before giving up - works around a driver race where
# cuInit() can fail right after a container (re)start on a GPU that's also driving
# the desktop; llama-server itself only warns and silently falls back to CPU, so
# Docker's restart policy never sees a failure to react to.
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
