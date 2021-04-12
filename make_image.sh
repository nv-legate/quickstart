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
    echo "  CUDA_VER : CUDA version to use (default: 11.0)"
    echo "  DEBUG : compile with debug symbols and w/o optimizations (default: 0)"
    echo "  LINUX_VER : what distro to base the image on (default: ubuntu18.04)"
    echo "  OMPI_VER : OpenMPI version to use (default: 4.0.5)"
    echo "  PLATFORM : what machine to build for"
    echo "  PYTHON_VER : Python version to use (default: 3.8)"
    exit
fi

# Read arguments
export CUDA_VER="${CUDA_VER:-11.0}"
export DEBUG="${DEBUG:-0}"
export LINUX_VER="${LINUX_VER:-ubuntu18.04}"
export OMPI_VER="${OMPI_VER:-4.0.5}"
export PLATFORM="$PLATFORM"
export PYTHON_VER="${PYTHON_VER:-3.8}"

# Pull latest versions of legate libraries and Legion
function git_pull {
    if [[ ! -e "$2" ]]; then
        git clone "$1"/"$2".git -b "$3"
    fi
    cd "$2"
    git checkout "$3"
    git pull --ff-only
    cd ..
}
git_pull ssh://git@gitlab-master.nvidia.com:12051/legate legate.core master
git_pull ssh://git@gitlab-master.nvidia.com:12051/legate legate.dask master
git_pull ssh://git@gitlab-master.nvidia.com:12051/legate legate.hello master
git_pull ssh://git@gitlab-master.nvidia.com:12051/legate legate.numpy master
git_pull ssh://git@gitlab-master.nvidia.com:12051/legate legate.pandas master
cd legate.core
git_pull https://gitlab.com/StanfordLegion legion control_replication
cd ..

# Build and push image
IMAGE=nvcr.io/nvidian/legion/legate-"$PLATFORM"
TAG="$(date +%Y-%m-%d-%H%M%S)"
DOCKER_BUILDKIT=1 docker build -t "$IMAGE:$TAG" -t "$IMAGE:latest" \
    --build-arg CUDA_VER="$CUDA_VER" \
    --build-arg DEBUG="$DEBUG" \
    --build-arg LINUX_VER="$LINUX_VER" \
    --build-arg OMPI_VER="$OMPI_VER" \
    --build-arg PLATFORM="$PLATFORM" \
    --build-arg PYTHON_VER="$PYTHON_VER" \
    "$@" .
docker push "$IMAGE:$TAG"
docker push "$IMAGE:latest"
