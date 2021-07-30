#!/bin/bash -l

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

# Running this script in login mode, because some conda installations only
# load the conda commands in login shells.
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Print usage if requested
if [[ $# -ge 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    echo "Usage: $(basename "${BASH_SOURCE[0]}") [extra conda packages]"
    echo "Arguments read from the environment:"
    echo "  CONDA_ENV : name of conda environment to create (default: legate)"
    echo "  CONDA_ROOT : where to install conda (if not already installed)"
    echo "  CUDA_VER : CUDA runtime version to install from conda (if installing"
    echo "             Rapids) (default: match system version)"
    echo "  PYTHON_VER : Python version to use (default: 3.8)"
    echo "  USE_RAPIDS : whether to install Rapids (required for running"
    echo "               legate.pandas on GPUs) (default: 1)"
    exit
fi

# Read arguments
export CONDA_ENV="${CONDA_ENV:-legate}"
if [[ -z "${CUDA_VER+x}" ]]; then
    if command -v nvcc &> /dev/null; then
        export CUDA_VER="$(nvcc --version | grep release | awk '{ print $5 }' | sed 's/.$//')"
    fi
fi
export PYTHON_VER="${PYTHON_VER:-3.8}"
export USE_RAPIDS="${USE_RAPIDS:-1}"

# Install conda
if command -v conda &> /dev/null; then
    echo "Conda already installed, skipping conda installation"
else
    echo "Installing conda under $CONDA_ROOT"
    INSTALLER="$(mktemp --suffix .sh)"
    wget -O "$INSTALLER" -nv https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-"$(uname -m)".sh
    chmod +x "$INSTALLER"
    "$INSTALLER" -b -p "$CONDA_ROOT"
    rm "$INSTALLER"
    # Load conda functions into this subshell
    set +u
    source "$CONDA_ROOT"/etc/profile.d/conda.sh
    set -u
fi

# Create conda environment
if conda info --envs | grep -q "^$CONDA_ENV "; then
    echo "Error: Conda environment $CONDA_ENV already exists" 1>&2
    exit 1
fi
if [[ "$USE_RAPIDS" == 1 ]]; then
    conda create --yes --name "$CONDA_ENV" \
        -c rapidsai-nightly -c nvidia -c conda-forge -c defaults \
        python="$PYTHON_VER" cudatoolkit="$CUDA_VER" rapids=21.08 \
        "$@"
else
    conda create --yes --name "$CONDA_ENV" \
        -c conda-forge -c defaults \
        python="$PYTHON_VER" \
        cffi numpy pyarrow=1.0.1 arrow-cpp=1.0.1 arrow-cpp-proc=3.0.0 \
        "$@"
fi

# Copy conda activation scripts (these set various paths)
set +u
conda activate "$CONDA_ENV"
set -u
mkdir -p "$CONDA_PREFIX/etc"
cp -r "$SCRIPT_DIR/conda" "$CONDA_PREFIX/etc"
