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
    echo "Usage: $(basename "${BASH_SOURCE[0]}") [extra build args]"
    echo "Arguments read from the environment:"
    echo "  ACCOUNT : account/group/project to submit build job under (if applicable)"
    echo "  DEBUG : compile with debug symbols and w/o optimizations (default: 0)"
    echo "  LEGATE_DIR : path to Legate installation directory"
    echo "  PLATFORM : what machine to build for (default: auto-detected)"
    echo "  USE_CUDA : include CUDA support (default: auto-detected)"
    echo "  USE_OPENMP : include OpenMP support (default: auto-detected)"
    exit
fi

# Read arguments
export DEBUG="${DEBUG:-0}"
export LEGATE_DIR="$LEGATE_DIR"
detect_platform && set_build_vars

# Run appropriate build command for the target library
if [[ -d "legate/core" ]]; then
    if [[ "$CONDUIT" == ibv ]]; then
        export GASNET_EXTRA_CONFIGURE_ARGS="--enable-ibv-multirail --with-ibv-max-hcas=$NUM_NICS"
    fi
    if [[ "$CONDUIT" != none ]]; then
        set -- --gasnet \
               --conduit "$CONDUIT" \
               "$@"
    fi
    if [[ "$USE_CUDA" == 1 ]]; then
        set -- --arch "$GPU_ARCH" \
               --with-cuda "$CUDA_HOME" \
               "$@"
    fi
    run_build ./install.py \
              --install-dir "$LEGATE_DIR" \
              --max-dim 4 \
              "$@"
elif [[ -d "legate/hello" ]]; then
    run_build ./install.py \
              --with-core "$LEGATE_DIR" \
              "$@"
elif [[ -d "legate/numpy" ]]; then
    run_build ./install.py \
              --with-core "$LEGATE_DIR" \
              --with-openblas "$CONDA_PREFIX" \
              "$@"
elif [[ -d "legate/pandas" ]]; then
    if [[ "$USE_CUDA" == 1 ]]; then
        set -- --with-rmm "$CONDA_PREFIX" \
               --with-nccl "$CONDA_PREFIX" \
               --with-cudf "$CONDA_PREFIX" \
               "$@"
    fi
    run_build ./install.py \
              --with-core "$LEGATE_DIR" \
              --with-arrow "$CONDA_PREFIX" \
              "$@"
else
    echo "Error: Unsupported library" 1>&2
    exit 1
fi
