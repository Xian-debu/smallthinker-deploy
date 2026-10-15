#!/usr/bin/env bash
# download-model.sh — download the abliterated Qwen3-30B-A3B GGUF (Q6_K).
#
# The model is NOT part of this repository (23.37 GiB). This script fetches it
# from the HF mirror used during development and verifies the expected size.
#
# Usage:
#   ./download-model.sh                 # -> ./models/Qwen3-30B-A3B-abliterated.Q6_K.gguf
#   ./download-model.sh /path/to/dir    # -> /path/to/dir/...
#
# Alternative manual sources (censored base models):
#   - https://huggingface.co/Qwen/Qwen3-30B-A3B-GGUF            (official, censored)
#   - https://huggingface.co/unsloth/Qwen3-30B-A3B-GGUF         (censored)
# Alternative abliterated quantizations:
#   - https://huggingface.co/mradermacher/Qwen3-30B-A3B-abliterated-GGUF

set -euo pipefail

OUT_DIR="${1:-$(pwd)/models}"
URL="https://hf-mirror.com/mradermacher/Qwen3-30B-A3B-abliterated-GGUF/resolve/main/Qwen3-30B-A3B-abliterated.Q6_K.gguf"
OUT_FILE="${OUT_DIR}/Qwen3-30B-A3B-abliterated.Q6_K.gguf"
EXPECTED_BYTES=25092532192

mkdir -p "${OUT_DIR}"

echo "==> Downloading Qwen3-30B-A3B abliterated Q6_K (23.37 GiB) ..."
echo "    ${URL}"
echo "    Note: hf-mirror is slow when the HF xet CDN is the bottleneck;"
echo "    on a fast link you can use huggingface.co directly instead."

if command -v aria2c >/dev/null 2>&1; then
    aria2c -x16 -s16 -k1M --file-allocation=falloc         -d "${OUT_DIR}" -o "Qwen3-30B-A3B-abliterated.Q6_K.gguf" "${URL}"
else
    curl -L --fail --retry 3 -C - -o "${OUT_FILE}" "${URL}"
fi

# 3. Verify size
if [ -f "${OUT_FILE}" ]; then
    actual=$(stat -c%s "${OUT_FILE}")
    if [ "${actual}" -eq "${EXPECTED_BYTES}" ]; then
        echo "==> OK: ${OUT_FILE} (${actual} bytes)"
    else
        echo "==> WARNING: size mismatch — expected ${EXPECTED_BYTES}, got ${actual}"
        exit 1
    fi
else
    echo "==> ERROR: download failed, file not found: ${OUT_FILE}"
    exit 1
fi
