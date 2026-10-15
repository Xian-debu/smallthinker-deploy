#!/usr/bin/env bash
# build-engine.sh — build the SmallThinker engine (Tiiny-AI/PowerInfer,
# a llama.cpp 1594 fork) into a release llama-server / llama-cli.
#
# Usage:
#   ./build-engine.sh            # builds in ./third_party/PowerInfer
#   ENGINE_SRC=/path ./build-engine.sh
#
# Requirements:
#   - clang-18 / clang++-18 (older clang may not support all flags)
#   - cmake >= 3.20, make (or ninja), git
#   - ~20 GiB free disk for the build tree
#
# Environment:
#   ENGINE_URL     git URL of the engine repository
#   ENGINE_COMMIT  pinned commit (default: the commit this repo was tested on)
#   ENGINE_SRC     where to clone / expected source tree
#   BUILD_DIR      cmake build directory
#   JOBS           parallel build jobs (default: nproc)

set -euo pipefail

ENGINE_URL="${ENGINE_URL:-https://github.com/Tiiny-AI/PowerInfer.git}"
ENGINE_COMMIT="${ENGINE_COMMIT:-8bd56d6}"
ENGINE_SRC="${ENGINE_SRC:-$(pwd)/third_party/PowerInfer}"
BUILD_DIR="${BUILD_DIR:-${ENGINE_SRC}/build}"
JOBS="${JOBS:-$(nproc)}"

echo "==> Engine source : ${ENGINE_SRC}"
echo "==> Pinned commit : ${ENGINE_COMMIT}"

# 1. Obtain the source tree
if [ ! -d "${ENGINE_SRC}/.git" ]; then
    echo "==> Cloning ${ENGINE_URL} ..."
    git clone --filter=blob:none "${ENGINE_URL}" "${ENGINE_SRC}"
fi
git -C "${ENGINE_SRC}" checkout "${ENGINE_COMMIT}" 2>/dev/null     || { echo "==> Fetching pinned commit ..."; git -C "${ENGINE_SRC}" fetch origin "${ENGINE_COMMIT}"; git -C "${ENGINE_SRC}" checkout "${ENGINE_COMMIT}"; }

# 2. Configure with the tested toolchain
echo "==> Configuring cmake (Release, clang-18, -march=native, LLAMA_CURL=OFF) ..."
cmake -S "${ENGINE_SRC}" -B "${BUILD_DIR}"     -DCMAKE_BUILD_TYPE=Release     -DCMAKE_C_COMPILER=clang-18     -DCMAKE_CXX_COMPILER=clang++-18     -DCMAKE_C_FLAGS="-march=native -mtune=native"     -DCMAKE_CXX_FLAGS="-march=native -mtune=native"     -DLLAMA_CURL=OFF     -DLLAMA_BUILD_SERVER=ON

# 3. Build
echo "==> Building llama-server + llama-cli (-j ${JOBS}) ..."
cmake --build "${BUILD_DIR}" --target llama-server llama-cli -j "${JOBS}"

echo
echo "==> Done. Binaries:"
ls -lh "${BUILD_DIR}/bin/llama-server" "${BUILD_DIR}/bin/llama-cli"
