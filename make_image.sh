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

# Print usage if requested
if [[ $# -ge 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    echo "Usage: $(basename "${BASH_SOURCE[0]}") [extra docker-build flags]"
    echo "Arguments read from the environment:"
    echo "  CUDA_VER : CUDA version to use (default: 11.5)"
    echo "  DEBUG : compile with debug symbols and w/o optimizations (default: 0)"
    echo "  DEBUG_RELEASE : compile with optimizations and some debug symbols (default: 0)"
    echo "  LEGION_REF : Legion branch/commit/tag to use (default: collective)"
    echo "  LINUX_VER : what distro to base the image on (default: ubuntu20.04)"
    echo "  NETWORK : Realm networking backend to use (default: gasnet1)"
    echo "  NOPULL : do not pull latest versions of Legion & Legate libraries (default: 0)"
    echo "  PLATFORM : what machine to build for (default: generic single-node"
    echo "             machine with volta GPUs)"
    echo "  PYTHON_VER : Python version to use (default: 3.8)"
    echo "  TAG : tag to use for the produced image (default: \`date +%Y-%m-%d-%H%M%S\`)"
    echo "  TAG_LATEST : whether to also tag the image as latest (default: 0)"
    echo "  USE_SPY : build Legion with detailed Spy logging enabled (default: 0)"
    exit
fi

# Read arguments
export CUDA_VER="${CUDA_VER:-11.5}"
export DEBUG="${DEBUG:-0}"
export DEBUG_RELEASE="${DEBUG_RELEASE:-0}"
export LEGION_REF="${LEGION_REF:-collective}"
export LINUX_VER="${LINUX_VER:-ubuntu20.04}"
export NETWORK="${NETWORK:-gasnet1}"
export NOPULL="${NOPULL:-0}"
export PLATFORM="${PLATFORM:-generic-volta}"
export PYTHON_VER="${PYTHON_VER:-3.9}"
export TAG="${TAG:-$(date +%Y-%m-%d-%H%M%S)}"
export TAG_LATEST="${TAG_LATEST:-0}"
export USE_SPY="${USE_SPY:-0}"

# Pull latest versions of legate libraries and Legion
function git_pull {
    if [[ ! -e "$2" ]]; then
        if [[ "$3" == HEAD ]]; then
            git clone "$1" "$2"
        else
            git clone "$1" "$2" -b "$3"
        fi
    fi
    if [[ "$NOPULL" == 1 ]]; then
        return
    fi
    cd "$2"
    git fetch --all
    if [[ "$3" == HEAD ]]; then
        # checkout remote HEAD branch
        REF="$(git remote show origin | grep HEAD | awk '{ print $3 }')"
    else
        REF="$3"
    fi
    git checkout "$REF"
    # update from the remote, if we are on a branch
    if [[ "$(git rev-parse --abbrev-ref HEAD)" != "HEAD" ]]; then
        git pull --ff-only
    fi
    cd -
}
git_pull https://gitlab.com/StanfordLegion/legion.git legion "$LEGION_REF"
git_pull https://github.com/nv-legate/legate.core.git legate.core HEAD
git_pull https://github.com/nv-legate/cunumeric.git cunumeric HEAD

# Build and push image
IMAGE=legate-"$PLATFORM"
if [[ "$PLATFORM" == generic-* ]]; then
    export NETWORK=none
else
    IMAGE="$IMAGE"-"$NETWORK"
fi
if [[ "$DEBUG" == 1 ]]; then
    IMAGE="$IMAGE"-debug
elif [[ "$DEBUG_RELEASE" == 1 ]]; then
    IMAGE="$IMAGE"-debugrel
fi
if [[ "$USE_SPY" == 1 ]]; then
    IMAGE="$IMAGE"-spy
fi
DOCKER_BUILDKIT=1 docker build -t "$IMAGE:$TAG" \
    --build-arg CUDA_VER="$CUDA_VER" \
    --build-arg DEBUG="$DEBUG" \
    --build-arg DEBUG_RELEASE="$DEBUG_RELEASE" \
    --build-arg LINUX_VER="$LINUX_VER" \
    --build-arg NETWORK="$NETWORK" \
    --build-arg PLATFORM="$PLATFORM" \
    --build-arg PYTHON_VER="$PYTHON_VER" \
    --build-arg USE_SPY="$USE_SPY" \
    "$@" .
if [[ "$TAG_LATEST" == 1 ]]; then
    docker tag "$IMAGE:$TAG" "$IMAGE:latest"
fi
