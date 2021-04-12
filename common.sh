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

function detect_platform {
    if [[ -n "${PLATFORM+x}" ]]; then
        return
    elif [[ "$(dnsdomainname)" == *"summit"* ]]; then
        export PLATFORM=summit
    elif [[ "$(uname -n)" == "cori"* ]]; then
        export PLATFORM=cori
    else
        export PLATFORM=other
    fi
}

function set_build_vars {
    export CC=${CC:-gcc}
    export CXX=${CXX:-g++}
    export GPU_ARCH=${GPU_ARCH:-""}
    # Set base build variables according to target platform
    if [[ "$PLATFORM" == summit ]]; then
        export CONDUIT=ibv
        export NUM_HCAS=4
        export CUDA_HOME="$CUDA_DIR"
        export GPU_ARCH_NUM=70
    elif [[ "$PLATFORM" == cori ]]; then
        export CONDUIT=ibv
        export NUM_HCAS=4
        # CUDA_HOME is already set (by module)
        export GPU_ARCH_NUM=70
    elif [[ $( grep -q docker /proc/self/cgroup ) && $PLATFORM != other ]]; then
        echo "Error: Detected a docker build for an unknown target platform" 1>&2
        exit 1
    else
        echo "Did not detect a supported cluster, assuming local-node build"
        export CONDUIT=none
        if [[ -z "$GPU_ARCH" ]]; then
          if command -v nvcc &> /dev/null; then
              TEST_SRC="$(mktemp --suffix .cc)"
              echo "
                #include <iostream>
                #include <cuda_runtime.h>
                #include <stdlib.h>
                int main() {
                  cudaDeviceProp prop;
                  cudaError_t err = cudaGetDeviceProperties(&prop, 0);
                  if (err != cudaSuccess) { exit(1); }
                  std::cout << prop.major << prop.minor << std::endl;
                }
              " > "$TEST_SRC"
              TEST_EXE="$(mktemp)"
              nvcc -o "$TEST_EXE" "$TEST_SRC"
              export GPU_ARCH_NUM="$( "$TEST_EXE" )"
              rm "$TEST_EXE" "$TEST_SRC"
              NVCC_PATH="$(which nvcc | head -1)"
              export CUDA_HOME="${NVCC_PATH%/bin/nvcc}"
          else
              export GPU_ARCH_NUM=none
          fi
        fi  
    fi
    # Fill other info using base build variables
    if [[ -z "$GPU_ARCH" ]]; then
    case "$GPU_ARCH_NUM" in
        20) export GPU_ARCH=fermi   ;;
        30) export GPU_ARCH=kepler  ;;
        35) export GPU_ARCH=k20     ;;
        37) export GPU_ARCH=k80     ;;
        52) export GPU_ARCH=maxwell ;;
        60) export GPU_ARCH=pascal  ;;
        70) export GPU_ARCH=volta   ;;
        75) export GPU_ARCH=turing  ;;
        80) export GPU_ARCH=ampere  ;;
    esac
    fi
}

function set_mofed_vars {
    # Fill other info based on MOFED version
    case "$MOFED_VER" in
        4.5-1.0.1)   export MOFED_VER_LONG=4.5-1.0.1.0 ;;
        4.6-1.0.1)   export MOFED_VER_LONG=4.6-1.0.1.1 ;;
        4.7-1.0.0)   export MOFED_VER_LONG=4.7-1.0.0.1 ;;
        4.7-3.2.9)   export MOFED_VER_LONG=4.7-3.2.9.0 ;;
        5.0-1.0.0.0) export MOFED_VER_LONG=5.0-1.0.0.0 ;;
        5.0-2.1.8)   export MOFED_VER_LONG=5.0-2.1.8.0 ;;
        5.1-0.6.6)   export MOFED_VER_LONG=5.1-0.6.6.0 ;;
        5.1-2.3.7)   export MOFED_VER_LONG=5.1-2.3.7.1 ;;
        5.1-2.5.8)   export MOFED_VER_LONG=5.1-2.5.8.0 ;;
        5.2-1.0.4)   export MOFED_VER_LONG=5.2-1.0.4.0 ;;
        5.2-2.2.0)   export MOFED_VER_LONG=5.2-2.2.0.0 ;;
    esac
    case "$MOFED_VER" in
        4.5-1.0.1)   export MOFED_DEB_VER=45 ;;
        4.6-1.0.1)   export MOFED_DEB_VER=46 ;;
        4.7-1.0.0)   export MOFED_DEB_VER=47 ;;
        4.7-3.2.9)   export MOFED_DEB_VER=47 ;;
        5.0-1.0.0.0) export MOFED_DEB_VER=50 ;;
        5.0-2.1.8)   export MOFED_DEB_VER=50 ;;
        5.1-0.6.6)   export MOFED_DEB_VER=51 ;;
        5.1-2.3.7)   export MOFED_DEB_VER=51 ;;
        5.1-2.5.8)   export MOFED_DEB_VER=51 ;;
        5.2-1.0.4)   export MOFED_DEB_VER=52 ;;
        5.2-2.2.0)   export MOFED_DEB_VER=52 ;;
    esac
}

function run_build {
    # Invoke launcher if building on/for a bare-metal cluster, otherwise build locally
    if [[ "$PLATFORM" == summit && -z ${DOCKER_BUILD+x} ]]; then
        bsub -nnodes 1 -W 60 -P "$ACCOUNT" -I "$@"
    elif [[ "$PLATFORM" == cori && -z ${DOCKER_BUILD+x} ]]; then
        if [[ -n ${SLURM_JOBID+x} ]]; then
          "$@"
        else
          srun -C gpu -N 1 -t 60 -G 1 -c 10 -A "$ACCOUNT" "$@"
        fi
    else
        "$@"
    fi
} 
