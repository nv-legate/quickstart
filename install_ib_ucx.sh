#!/bin/bash

# Copyright 2021 NVIDIA Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$SCRIPT_DIR/common.sh"

# Print usage if requested
if [[ $# -ge 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    echo "Usage: $(basename "${BASH_SOURCE[0]}")"
    echo "Arguments read from the environment:"
    echo "  ACCOUNT : account/group/project to submit build job under (if applicable)"
    echo "  DEBUG : compile with debug symbols and w/o optimizations (default: 0)"
    echo "  PLATFORM : what machine to build for (default: auto-detected)"
    exit
fi

# Read arguments
export DEBUG="${DEBUG:-0}"
detect_platform && set_build_vars

# Remove conda-sourced UCX
if [[ $(conda list ^ucx$ 2>&1 | wc -l) -ge 4 ]]; then
    conda remove --offline --force --yes ucx
fi

# Run build command
run_build bash -euo pipefail -c '
    TMP_DIR="$(mktemp -d)"
    git clone --recurse-submodules -b v1.10.x https://github.com/openucx/ucx "$TMP_DIR"
    cd "$TMP_DIR"
    if [[ "$GPU_ARCH" != none ]]; then
        wget -nv https://raw.githubusercontent.com/rapidsai/ucx-split-feedstock/master/recipe/cuda-alloc-rcache.patch
        git apply cuda-alloc-rcache.patch
    fi
    ./autogen.sh
    mkdir build
    cd build
    if [[ "$DEBUG" == 1 ]]; then
        CONFIGURE=(../configure \
                   --enable-debug \
                   --enable-stats \
                   --enable-logging \
                   --enable-debug-data)
    else
        CONFIGURE=(../contrib/configure-release \
                   --enable-compiler-opt=3 \
                   --enable-optimizations \
                   --with-march)
    fi
    if [[ "$GPU_ARCH" != none ]]; then
        CONFIGURE+=(--with-dm \
                    --with-cuda="$CUDA_HOME")
    fi
    "${CONFIGURE[@]}" \
        --prefix="$CONDA_PREFIX" \
        --disable-doxygen-doc \
        --without-java \
        --enable-mt \
        --enable-cma \
        --with-rdmacm \
        --with-rc \
        --with-ud \
        --with-dc \
        --with-verbs \
        --with-mlx5-dv
    make -j install
    cd
    rm -rf "$TMP_DIR"
'
