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
    echo "  DEBUG : compile with debug symbols and w/o optimizations (default: 0)"
    echo "  DEBUG_RELEASE : compile with optimizations and some debug symbols (default: 0)"
    echo "  EDITABLE : do an editable installation (default: 0)"
    echo "  LEGION_BRANCH : source branch to use for Legion (default: unset)"
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
    PACKAGE="$1"
    INSTALL_DIR="$2"
    if compgen -G "$CONDA_PREFIX"/lib/'python*'/site-packages/"$INSTALL_DIR" > /dev/null; then
        # Existing non-editable installation
        if [[ "$EDITABLE" == 1 ]]; then
            echo "Error: $PACKAGE already installed in non-editable mode, but editable was requested" 1>&2
            exit 1
        fi
    elif compgen -G "$CONDA_PREFIX"/lib/'python*'/site-packages/"$PACKAGE".egg-link > /dev/null; then
        # Pick an arbitrary .egg-link file; there should only be one, except in
        # the case of e.g. python 3.10, in which case conda creates a 3.1 copy
        for FILE in "$CONDA_PREFIX"/lib/python*/site-packages/"$PACKAGE".egg-link; do
            EGG_LINK_FILE="$FILE"
            break
        done
        # Existing editable installation
        if [[ "$EDITABLE" == 0 ]]; then
            echo "Error: $PACKAGE already installed in editable mode, but non-editable was requested" 1>&2
            exit 1
        fi
        if [[ ! . -ef "$(head -n 1 "$EGG_LINK_FILE")" ]]; then
            echo "Error: $PACKAGE already installed from a different source" 1>&2
            exit 1
        fi
    fi
}

# Run appropriate build command for the target library
if [[ -d "legate/core" ]]; then
    check_not_overriding legate.core legate/core
    if [[ "$NETWORK" != none ]]; then
        set -- --network "$NETWORK" "$@"
    fi
    if [[ "$NETWORK" == gasnet1 || "$NETWORK" == gasnetex ]]; then
        set -- --conduit "$CONDUIT" "$@"
    fi
    if [[ "$USE_CUDA" == 1 ]]; then
        set -- --cuda "$@"
    fi
    if [[ "$USE_OPENMP" == 1 ]]; then
        set -- --openmp "$@"
    fi
    if [[ -n "${GASNET_SYSTEM+x}" ]]; then
        set -- --gasnet-system "$GASNET_SYSTEM" "$@"
    fi
    if [[ -n "${LEGION_DIR+x}" ]]; then
        set -- --legion-src-dir "$LEGION_DIR" "$@"
    fi
    if [[ -n "${LEGION_BRANCH+x}" ]]; then
        set -- --legion-branch "$LEGION_BRANCH" "$@"
    fi
    if [[ "$DEBUG" == 1 ]]; then
        set -- --debug "$@"
    elif [[ "$DEBUG_RELEASE" == 1 ]]; then
        set -- --debug-release "$@"
    fi
    if [[ "$EDITABLE" == 1 ]]; then
        set -- --editable "$@"
    fi
    run_build ./install.py --verbose "$@"
elif [[ -d "cunumeric" ]]; then
    check_not_overriding cunumeric cunumeric
    if [[ "$DEBUG" == 1 ]]; then
        set -- --debug "$@"
    elif [[ "$DEBUG_RELEASE" == 1 ]]; then
        set -- --debug-release "$@"
    fi
    if [[ "$EDITABLE" == 1 ]]; then
        set -- --editable "$@"
    fi
    run_build ./install.py --verbose "$@"
else
    echo "Error: Unsupported library" 1>&2
    exit 1
fi
