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
    echo "  CUDA_VER : CUDA runtime version to request from conda (if applicable)"
    echo "             (default: match system version)"
    echo "  PYTHON_VER : Python version to use (default: 3.8)"
    echo "  USE_CUDA : include CUDA support (default: auto-detected)"
    exit
fi

# Read arguments
export CONDA_ENV="${CONDA_ENV:-legate}"
if [[ -z "${USE_CUDA+x}" ]]; then
    if command -v nvcc &> /dev/null; then
        export USE_CUDA=1
    elif command -v nvidia-smi &> /dev/null; then
        export USE_CUDA=1
    else
        export USE_CUDA=0
    fi
fi
if [[ "$USE_CUDA" == 1 && -z "${CUDA_VER+x}" ]]; then
    if command -v nvcc &> /dev/null; then
        export CUDA_VER="$(nvcc --version | grep release | awk '{ print $5 }' | sed 's/.$//')"
    elif command -v nvidia-smi &> /dev/null; then
        export CUDA_VER="$(nvidia-smi | head -3 | tail -1 | awk '{ print $9 }')"
    fi
fi
export PYTHON_VER="${PYTHON_VER:-3.8}"

# Install conda & load conda functions into this subshell
if command -v conda &> /dev/null; then
    echo "Conda already installed, skipping conda installation"
    set +u
    eval "$(conda shell.bash hook)"
    set -u
else
    echo "Installing conda under $CONDA_ROOT"
    INSTALLER="$(mktemp -d)/installer.sh"
    OSNAME="$(uname -s)"
    if [[ "$OSNAME" == Darwin ]]; then
        OSNAME=MacOSX
    fi
    curl -fsSL -o "$INSTALLER" https://repo.anaconda.com/miniconda/Miniconda3-latest-"$OSNAME"-"$(uname -m)".sh
    chmod +x "$INSTALLER"
    "$INSTALLER" -b -p "$CONDA_ROOT"
    rm "$INSTALLER"
    set +u
    source "$CONDA_ROOT"/etc/profile.d/conda.sh
    set -u
fi

# Create conda environment
if conda info --envs | grep -q "^$CONDA_ENV "; then
    echo "Error: Conda environment $CONDA_ENV already exists" 1>&2
    exit 1
fi
if [[ "$(uname -s)" == Darwin ]]; then
    SED="sed -i ''"
else
    SED="sed -i"
fi
YML_FILE="$(mktemp -d)/env.yml"
curl -fsSL -o "$YML_FILE" https://raw.githubusercontent.com/nv-legate/legate.core/HEAD/conda/environment-test-"$PYTHON_VER".yml
if [[ "$USE_CUDA" == 1 ]]; then
    echo "  - cudatoolkit=$CUDA_VER" >> "$YML_FILE"
else
    $SED '/^  - cutensor/d' "$YML_FILE"
    $SED '/^  - nccl/d' "$YML_FILE"
    $SED '/^  - pynvml/d' "$YML_FILE"
fi
for PACKAGE in "$@"; do
    echo "  - $PACKAGE" >> "$YML_FILE"
done
conda env create -n "$CONDA_ENV" -f "$YML_FILE"
rm "$YML_FILE"

# Copy conda activation scripts (these set various paths)
set +u
conda activate "$CONDA_ENV"
set -u
mkdir -p "$CONDA_PREFIX/etc"
cp -r "$SCRIPT_DIR/conda" "$CONDA_PREFIX/etc"
