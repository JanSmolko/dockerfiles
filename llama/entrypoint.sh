#!/bin/bash
set -u

MAX_RETRIES="${GPU_INIT_MAX_RETRIES:-5}"
RETRY_DELAY="${GPU_INIT_RETRY_DELAY:-3}"

for attempt in $(seq 1 "$MAX_RETRIES"); do
    echo "[entrypoint] attempt ${attempt}/${MAX_RETRIES}: starting llama-server"
    LOG_FILE=$(mktemp)
    /app/llama-server "$@" >"$LOG_FILE" 2>&1 &
    SERVER_PID=$!

    tail -n +1 -f "$LOG_FILE" &
    TAIL_PID=$!

    GPU_FAILED=0
    for i in $(seq 1 40); do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            break
        fi
        if grep -q "no usable GPU found" "$LOG_FILE"; then
            GPU_FAILED=1
            break
        fi
        if grep -q "model loaded" "$LOG_FILE"; then
            break
        fi
        sleep 0.5
    done

    if [ "$GPU_FAILED" -eq 0 ]; then
        # Either startup looks healthy (GPU acquired) or the process exited on its
        # own for an unrelated reason - hand control over and propagate its exit code.
        wait "$SERVER_PID"
        EXIT_CODE=$?
        kill "$TAIL_PID" 2>/dev/null
        rm -f "$LOG_FILE"
        exit "$EXIT_CODE"
    fi

    echo "[entrypoint] GPU init failed on attempt ${attempt} (CUDA context race) - retrying in ${RETRY_DELAY}s"
    kill "$SERVER_PID" "$TAIL_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    rm -f "$LOG_FILE"
    sleep "$RETRY_DELAY"
done

echo "[entrypoint] GPU init failed after ${MAX_RETRIES} attempts - exiting so Docker's restart policy retries the container"
exit 1
