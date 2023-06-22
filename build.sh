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
export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$SCRIPT_DIR/common.sh"

# Print usage if requested
if [[ $# -ge 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    echo "Usage: $(basename "${BASH_SOURCE[0]}") [extra build args]"
    echo "Arguments read from the environment:"
    echo "  ACCOUNT : account/group/project to submit build job under (if applicable)"
    echo "  CONDUIT : GASNet conduit to use (if applicable) (default: auto-detected)"
    echo "  GPU_ARCH : CUDA architecture to build for (default: auto-detected)"
    echo "  LEGION_DIR : source directory to use for Legion (default: unset; the build"
    echo "               will pull a local copy of Legion)"
    echo "  NETWORK : Realm networking backend to use (default: auto-detected)"
    echo "  PLATFORM : what machine to build for -- provides defaults for other options"
    echo "             (default: auto-detected)"
    echo "  USE_CUDA : include CUDA support (default: auto-detected)"
    echo "  USE_OPENMP : include OpenMP support (default: auto-detected)"
    exit
fi

# Read arguments
detect_platform && set_build_vars

function check_not_overriding {
    if [ -e "$CONDA_PREFIX"/lib/python*/site-packages/"$1".egg-link ]; then
        if [[ ! . -ef "$(head -n 1 "$CONDA_PREFIX"/lib/python*/site-packages/"$1".egg-link)" ]]; then
            echo "Error: Library already installed in $CONDA_PREFIX from a different source" 1>&2
            exit 1
        fi
    fi
}

# Run appropriate build command for the target library
if [[ -d "legate/core" ]]; then
    check_not_overriding legate.core
    if [[ "$NETWORK" != none ]]; then
        set -- --network "$NETWORK" "$@"
    fi
    if [[ "$NETWORK" == gasnet1 || "$NETWORK" == gasnetex ]]; then
        set -- --conduit "$CONDUIT" "$@"
    fi
    if [[ "$USE_CUDA" == 1 ]]; then
        set -- --cuda --arch "$GPU_ARCH" "$@"
    fi
    if [[ "$USE_OPENMP" == 1 ]]; then
        set -- --openmp "$@"
    fi
    if [[ -n "${LEGION_DIR+x}" ]]; then
        set -- --legion-src-dir "$LEGION_DIR" "$@"
    fi
    run_build ./install.py \
              --verbose \
              --editable \
              "$@"
elif [[ -d "cunumeric" ]]; then
    check_not_overriding cunumeric
    run_build ./install.py \
              --verbose \
              --editable \
              "$@"
else
    echo "Error: Unsupported library" 1>&2
    exit 1
fi
