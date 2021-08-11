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
    echo "  CUDA_VER : CUDA version to use (default: 11.2)"
    echo "  DEBUG : compile with debug symbols and w/o optimizations (default: 0)"
    echo "  LINUX_VER : what distro to base the image on (default: ubuntu20.04)"
    echo "  PLATFORM : what machine to build for (default: generic single-node"
    echo "             machine with volta GPUs)"
    echo "  PYTHON_VER : Python version to use (default: 3.8)"
    exit
fi

# Read arguments
export CUDA_VER="${CUDA_VER:-11.2}"
export DEBUG="${DEBUG:-0}"
export LINUX_VER="${LINUX_VER:-ubuntu20.04}"
export PLATFORM="${PLATFORM:-generic-volta}"
export PYTHON_VER="${PYTHON_VER:-3.8}"

# Pull latest versions of legate libraries and Legion
function git_pull {
    if [[ ! -e "$2" ]]; then
        git clone "$1" "$2"
    fi
    cd "$2"
    git pull --ff-only
    cd ..
}
git_pull https://github.com/nv-legate/legate.core.git legate.core
git_pull https://github.com/nv-legate/legate.numpy.git legate.numpy

# Build and push image
IMAGE=legate-"$PLATFORM"
TAG="$(date +%Y-%m-%d-%H%M%S)"
DOCKER_BUILDKIT=1 docker build -t "$IMAGE:$TAG" \
    --build-arg CUDA_VER="$CUDA_VER" \
    --build-arg DEBUG="$DEBUG" \
    --build-arg LINUX_VER="$LINUX_VER" \
    --build-arg PLATFORM="$PLATFORM" \
    --build-arg PYTHON_VER="$PYTHON_VER" \
    "$@" .
for REPO in ghcr.io/nv-legate; do
    docker tag "$IMAGE:$TAG" "$REPO/$IMAGE:$TAG"
    docker tag "$IMAGE:$TAG" "$REPO/$IMAGE:latest"
    docker push "$REPO/$IMAGE:$TAG"
    docker push "$REPO/$IMAGE:latest"
done
