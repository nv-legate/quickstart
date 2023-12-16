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
    echo "  CONDUIT : GASNet conduit to use (if applicable) (default: ibv)"
    echo "  CUDA_VER : CUDA version to use (default: 12.0.1)"
    echo "  DEBUG : compile with debug symbols and w/o optimizations (default: 0)"
    echo "  DEBUG_RELEASE : compile with optimizations and some debug symbols (default: 0)"
    echo "  LINUX_VER : what distro to base the image on (default: ubuntu20.04)"
    echo "  MOFED_VER : what MOFED version to use (default: 5.4-3.5.8.0)"
    echo "  NETWORK : Realm networking backend to use (default: ucx)"
    echo "  NOPULL : do not pull latest versions of Legion & Legate libraries (default: 0)"
    echo "  PYTHON_VER : Python version to use (default: 3.9)"
    echo "  RELEASE_BRANCH : Legate.core and cuNumeric branch to use, example: branch-23.05 (default: HEAD)"
    echo "  TAG : tag to use for the produced image (default: \`date +%Y-%m-%d-%H%M%S\`)"
    echo "  TAG_LATEST : whether to also tag the image as latest (default: 0)"
    echo "  USE_SPY : build Legion with detailed Spy logging enabled (default: 0)"
    echo "  CPU_ARCH : what CPU architecture to build for (choices: arm, x86; default: x86)"
    exit
fi

# Read arguments
export CONDUIT="${CONDUIT:-ibv}"
export CUDA_VER="${CUDA_VER:-12.0.1}"
if [[ ! "$CUDA_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: \$CUDA_VER must be given in the format X.Y.Z (patch version is required)" 1>&2
    exit 1
fi
export DEBUG="${DEBUG:-0}"
export DEBUG_RELEASE="${DEBUG_RELEASE:-0}"
export LINUX_VER="${LINUX_VER:-ubuntu20.04}"
export MOFED_VER="${MOFED_VER:-5.4-3.5.8.0}"
export NETWORK="${NETWORK:-ucx}"
export NOPULL="${NOPULL:-0}"
export PYTHON_VER="${PYTHON_VER:-3.9}"
export RELEASE_BRANCH="${RELEASE_BRANCH:-HEAD}"
export TAG="${TAG:-$(date +%Y-%m-%d-%H%M%S)}"
export TAG_LATEST="${TAG_LATEST:-0}"
export USE_SPY="${USE_SPY:-0}"
export CPU_ARCH="${CPU_ARCH:-x86}"

# Check out repos
function git_clone {
    if [[ ! -e "$1" ]]; then
        git clone "$2" "$1"
    fi
}
# Legion is optional
# git_clone legion https://gitlab.com/StanfordLegion/legion.git
git_clone legate.core https://github.com/nv-legate/legate.core.git
git_clone cunumeric https://github.com/nv-legate/cunumeric.git

# Pull latest versions of legate libraries and Legion
function git_pull {
    if [[ ! -e "$1" ]]; then
        echo "$1 git hash: (auto)"
        return
    fi
    cd "$1"
    if [[ "$NOPULL" == 0 ]]; then
        REMOTE=origin
        git fetch --quiet "$REMOTE"
        if [[ "$2" == HEAD ]]; then
            # checkout remote HEAD branch
            REF="$(git remote show "$REMOTE" | grep HEAD | awk '{ print $3 }')"
        else
            REF="$2"
        fi
        if git show-ref --quiet refs/heads/"$REF"; then
            git checkout "$REF"
        else
            git checkout --track "$REMOTE"/"$REF"
        fi
        # update from the remote, if we are on a branch
        if [[ "$(git rev-parse --abbrev-ref HEAD)" != "HEAD" ]]; then
            git pull --ff-only
        fi
    fi
    echo -n "$1 git hash: "
    git rev-parse HEAD
    cd -
}
git_pull legion control_replication
git_pull legate.core "$RELEASE_BRANCH"
git_pull cunumeric "$RELEASE_BRANCH"

# Build and push image
IMAGE=legate
IMAGE="$IMAGE"-"$CPU_ARCH"
if [[ "$NETWORK" != none ]]; then
    IMAGE="$IMAGE"-"$NETWORK"
fi
if [[ "$NETWORK" = gasnet* ]]; then
    IMAGE="$IMAGE"-"$CONDUIT"
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
    --build-arg CONDUIT="$CONDUIT" \
    --build-arg CUDA_VER="$CUDA_VER" \
    --build-arg DEBUG="$DEBUG" \
    --build-arg DEBUG_RELEASE="$DEBUG_RELEASE" \
    --build-arg LINUX_VER="$LINUX_VER" \
    --build-arg MOFED_VER="$MOFED_VER" \
    --build-arg NETWORK="$NETWORK" \
    --build-arg PYTHON_VER="$PYTHON_VER" \
    --build-arg USE_SPY="$USE_SPY" \
    --build-arg CPU_ARCH="$CPU_ARCH" \
    "$@" .
if [[ "$TAG_LATEST" == 1 ]]; then
    docker tag "$IMAGE:$TAG" "$IMAGE:latest"
fi
