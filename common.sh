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
    elif command -v dnsdomainname &> /dev/null && [[ "$(dnsdomainname)" == *"summit"* ]]; then
        export PLATFORM=summit
    elif [[ "$(uname -n)" == "cori"* ]]; then
        export PLATFORM=cori
    elif [[ "$(uname -n)" == *"daint"* ]]; then
        export PLATFORM=pizdaint
    elif [[ "$(uname -n)" == *"lassen"* ]]; then
        export PLATFORM=lassen
    else
        export PLATFORM=other
    fi
}

function set_build_vars {
    export CC="${CC:-gcc}"
    export CXX="${CXX:-g++}"
    export FC="${FC:-gfortran}"
    export USE_CUDA="${USE_CUDA:-1}"
    export USE_OPENMP="${USE_OPENMP:-1}"
    # Set base build variables according to target platform
    if [[ "$PLATFORM" == summit ]]; then
        export CONDUIT=ibv
        export NUM_NICS=4
        export CUDA_HOME="$CUDA_DIR"
        export GPU_ARCH=volta
    elif [[ "$PLATFORM" == cori ]]; then
        export CONDUIT=ibv
        export NUM_NICS=4
        # CUDA_HOME is already set (by module)
        export GPU_ARCH=volta
    elif [[ "$PLATFORM" == pizdaint ]]; then
        export CONDUIT=aries
        export NUM_NICS=1
        # CUDA_HOME is already set (by module)
        export GPU_ARCH=pascal
    elif [[ "$PLATFORM" == lassen ]]; then
        export CONDUIT=ibv
        export NUM_NICS=4
        # CUDA_HOME is already set (by module)
        export GPU_ARCH=volta
    elif [[ "$PLATFORM" == generic-* ]]; then
        export CONDUIT=none
        export GPU_ARCH="${PLATFORM#generic-}"
    else
        if [[ -f /proc/self/cgroup ]] && grep -q docker /proc/self/cgroup; then
            echo "Error: Detected a docker build for an unknown target platform" 1>&2
            exit 1
        fi
        echo "Did not detect a supported cluster, assuming local-node build"
        export CONDUIT=none
        if [[ -z "${GPU_ARCH+x}" ]]; then
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
                GPU_ARCH_NUM="$( "$TEST_EXE" )"
                rm "$TEST_EXE" "$TEST_SRC"
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
                    *) echo "Error: Unsupported GPU architecture $GPU_ARCH_NUM" 1>&2; exit 1 ;;
                esac
            else
                export USE_CUDA=0
            fi
        fi
        if ! echo "int main(){}" | "$CXX" -x c++ -fopenmp - &> /dev/null; then
            export USE_OPENMP=0
        fi
    fi
    if [[ -z "${CUDA_HOME+x}" ]]; then
        if command -v nvcc &> /dev/null; then
            NVCC_PATH="$(which nvcc | head -1)"
            export CUDA_HOME="${NVCC_PATH%/bin/nvcc}"
        fi
    fi
}

function set_mofed_vars {
    if [[ -n "${MOFED_VER+x}" ]]; then
        true
    else
        echo "Error: Unknown MOFED version for platform $PLATFORM" 1>&2
        exit 1
    fi
}

function run_build {
    # Invoke launcher if building on a bare-metal cluster outside of docker, and
    # only if not already inside an allocation
    if [[ -f /proc/self/cgroup ]] && grep -q docker /proc/self/cgroup; then
        "$@"
    elif [[ -n "${SLURM_JOBID+x}" || -n "${LSB_JOBID+x}" ]]; then
        "$@"
    elif [[ "$PLATFORM" == summit ]]; then
        bsub -nnodes 1 -W 60 -P "$ACCOUNT" -I "$@"
    elif [[ "$PLATFORM" == cori ]]; then
        srun -C gpu -N 1 -t 60 -G 1 -c 10 -A "$ACCOUNT" "$@"
    elif [[ "$PLATFORM" == pizdaint ]]; then
        srun -N 1 -p debug -C gpu -t 30 -A "$ACCOUNT" "$@"
    elif [[ "$PLATFORM" == lassen ]]; then
        lalloc 1 -q pdebug -W 60 -G "$GROUP" "$@"
    else
        "$@"
    fi
}
