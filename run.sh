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
if [[ $# -lt 2 || ! "$1" =~ ^(1/)?[0-9]+(:[0-9]+)?$ ]]; then
    echo "Usage: $(basename "${BASH_SOURCE[0]}") <num-nodes>[:<ranks-per-node>] <prog.py> <arg1> <arg2> ..."
    echo "Positional arguments:"
    echo "  <num-nodes> : positive integer or ratio < 1 (e.g. 1/4, for partial-node runs)"
    echo "  <ranks-per-node> : positive integer (default: 1)"
    echo "  <argI> : arguments to the program itself, Legate or Legion"
    echo "           see legate -h for options accepted by Legate"
    echo "           see the Legion README for options accepted by Legion"
    echo "Arguments read from the environment:"
    echo "  ACCOUNT : account/group/project to submit the job under (if applicable)"
    echo "  IMAGE : which image to use (for container-based clusters)"
    echo "  INTERACTIVE : submit an interactive rather than a batch job (defaut: 0)"
    echo "  ITERATIONS : how many times to run the program (defaut: 1)"
    echo "  MOUNTS : comma-separated list of volume mounts (for container-based clusters)"
    echo "           (syntax depends on cluster) (default: none)"
    echo "  NODRIVER : don't invoke the Legate driver script (defaut: 0)"
    echo "  NOWAIT : don't wait for batch jobs to start (default: 0)"
    echo "  PLATFORM : what machine we are executing on (default: auto-detected)"
    echo "  QUEUE : what queue/partition to submit the job to (default: depends on cluster)"
    echo "  RESERVED_CORES : cores to reserve for kernel launches, Legion & Realm meta-work (default: 2)"
    echo "  SCRATCH : where to create an output directory (default: .)"
    echo "  TIMELIMIT : how much time to request for the job, in minutes (defaut: 60)"
    echo "  USE_CUDA : run with CUDA enabled (defaut: auto-detected)"
    echo "  USE_OPENMP : run with OpenMP enabled (defaut: auto-detected)"
    exit
fi

# Read arguments
NODE_STR="$1"
if [[ "$1" == *":"* ]]; then
    RANKS_PER_NODE="${NODE_STR#*:}"
    NODE_STR="${NODE_STR%%:*}"
else
    RANKS_PER_NODE=1
fi
if [[ "$NODE_STR" =~ ^1/[0-9]+$ ]]; then
    NUM_NODES=1
    RATIO_OF_NODE_USED="$NODE_STR"
else
    NUM_NODES="$NODE_STR"
    RATIO_OF_NODE_USED=1
fi
NODE_RATIO="$RATIO_OF_NODE_USED / $RANKS_PER_NODE"
shift
detect_platform
if [[ "$PLATFORM" == summit ]]; then
    CONTAINER_BASED=0
elif [[ "$PLATFORM" == cori ]]; then
    CONTAINER_BASED=0
elif [[ "$PLATFORM" == pizdaint ]]; then
    CONTAINER_BASED=0
elif [[ "$PLATFORM" == sapling ]]; then
    CONTAINER_BASED=0
elif [[ "$PLATFORM" == lassen ]]; then
    CONTAINER_BASED=0
else
    # Local run
    CONTAINER_BASED=0
fi
export INTERACTIVE="${INTERACTIVE:-0}"
export ITERATIONS="${ITERATIONS:-1}"
export MOUNTS="${MOUNTS:-}"
export NODRIVER="${NODRIVER:-0}"
export NOWAIT="${NOWAIT:-0}"
export RESERVED_CORES="${RESERVED_CORES:-2}"
export SCRATCH="${SCRATCH:-.}"
export TIMELIMIT="${TIMELIMIT:-60}"
if [[ "$CONTAINER_BASED" == 1 ]]; then
    # Can't auto-detect this outside the container, assume best-case scenario
    export USE_CUDA="${USE_CUDA:-1}"
    export USE_OPENMP="${USE_OPENMP:-1}"
else
    # Assuming editable conda install
    SITE_PACKAGES_DIR="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
    LEGATE_SRC_DIR="$(head -n 1 "$SITE_PACKAGES_DIR/legate.core.egg-link")"
    BUILD_CONFIG="$LEGATE_SRC_DIR"/build/legate_core-config.cmake
    if [[ -z "${USE_CUDA+x}" ]]; then
        if grep -q 'set(Legion_USE_CUDA ON)' "$BUILD_CONFIG"; then
            export USE_CUDA=1
        else
            export USE_CUDA=0
        fi
    fi
    if [[ -z "${USE_OPENMP+x}" ]]; then
        if grep -q 'set(Legion_USE_OpenMP ON)' "$BUILD_CONFIG"; then
            export USE_OPENMP=1
        else
            export USE_OPENMP=0
        fi
    fi
fi

# We explicitly add the Conda lib dir, to ensure the Conda libraries we load
# will look there for their dependencies first, instead of trying to link with
# the corresponding system-wide versions.
# We skip this on Mac, because then the system-wide vecLib would attempt to
# reuse the conda libcblas, which has SONAME version 0.0.0, whereas vecLib
# requires 1.0.0.
if [[ "$CONTAINER_BASED" == 0 ]]; then
    if [[ "$(uname)" != "Darwin" ]]; then
        export LD_LIBRARY_PATH="$CONDA_PREFIX"/lib:"${LD_LIBRARY_PATH:-}"
    fi
fi

# Prepare output directory
DATE="$(date +%Y/%m/%d)"
TIME="$(date +%H%M%S)"
mkdir -p "$SCRATCH/$DATE"
export HOST_OUT_DIR="$SCRATCH/$DATE/$TIME"
mkdir "$HOST_OUT_DIR"
echo "Redirecting stdout, stderr and logs to $HOST_OUT_DIR"
if [[ "$CONTAINER_BASED" == 1 ]]; then
    export CMD_OUT_DIR=/result
else
    export CMD_OUT_DIR="$HOST_OUT_DIR"
fi

# Retrieve resources available per node
# At this point we set aside some memory:
# - 1-2GB of framebuffer for the runtime and NCCL
# - ~1GB of RAM for GASNet
# - ~1GB of RAM for the Legion runtime
# - 256MB of RAM for sysmem/csize (reserved for the app, non-NUMA-aware)
# - 256MB of RAM for ib_rsize (reserved for remote DMA transfers)
# - 256MB of RAM for ib_csize (reserved for DMA transfers to/from the GPU)
if [[ "$PLATFORM" == summit ]]; then
    # 2 NUMA domains per node
    # 2 NICs per NUMA domain (4 NICs per node)
    # 21 cores per NUMA domain (1 more reserved for OS) (42 cores per node)
    # 4-way SMT per core
    # 256GB RAM per NUMA domain (512GB RAM per node)
    # 3 Tesla V100 GPUs per NUMA domain (6 GPUs per node)
    # 16GB FB per GPU
    NUMAS_PER_NODE=2
    RAM_PER_NUMA=200000
    GPUS_PER_NODE=6
    CORES_PER_NUMA=21
    FB_PER_GPU=14500
elif [[ "$PLATFORM" == cori ]]; then
    # 2 NUMA domains per node
    # 2 NICs per NUMA domain (4 NICs per node)
    # 20 cores per NUMA domain (40 cores per node)
    # 2-way SMT per core
    # 192GB per NUMA domain (384GB RAM per node)
    # 4 Tesla V100 GPUs per NUMA domain (8 GPUs per node)
    # 16GB FB per GPU
    NUMAS_PER_NODE=2
    RAM_PER_NUMA=150000
    GPUS_PER_NODE=8
    CORES_PER_NUMA=20
    FB_PER_GPU=14500
elif [[ "$PLATFORM" == pizdaint ]]; then
    # 1 NUMA domain per node
    # 1 NIC per node
    # 12 cores per NUMA domain
    # 2-way SMT per core
    # 64GB RAM per NUMA domain
    # 1 Tesla P100 GPU per node
    # 16GB FB per GPU
    NUMAS_PER_NODE=1
    RAM_PER_NUMA=55000
    GPUS_PER_NODE=1
    CORES_PER_NUMA=12
    FB_PER_GPU=14500
elif [[ "$PLATFORM" == sapling ]]; then
    # 2 NUMA domains per node
    # 1 NIC per node
    # 10 cores per NUMA domain
    # 2-way SMT per core
    # 128GB RAM per NUMA domain
    # 4 Tesla P100 GPUs per node (4/8 nodes)
    # 16GB FB per GPU
    NUMAS_PER_NODE=2
    RAM_PER_NUMA=100000
    GPUS_PER_NODE=4
    CORES_PER_NUMA=10
    FB_PER_GPU=14500
elif [[ "$PLATFORM" == lassen ]]; then
    # 2 NUMA domains per node
    # 2 NICs per NUMA domain (4 NICs per node)
    # 20 cores per NUMA domain (2 more reserved for OS) (40 cores per node)
    # 4-way SMT per core
    # 128GB RAM per NUMA domain (256GB RAM per node)
    # 2 Tesla V100 GPUs per NUMA domain (4 GPUs per node)
    # 16GB FB per GPU
    NUMAS_PER_NODE=2
    RAM_PER_NUMA=100000
    GPUS_PER_NODE=4
    CORES_PER_NUMA=20
    FB_PER_GPU=14500
else
    # Local run
    echo "Did not detect a supported cluster, assuming local-node run."
    export NOWAIT=1
    if [[ "$NUM_NODES" != 1 ]]; then
        echo "Error: Only 1 node is available, but $NUM_NODES were requested" 1>&2
        exit 1
    fi
    # Auto-detect available resources
    if [[ "$(uname)" == "Darwin" ]]; then
        NUMAS_PER_NODE=1
        RAM_PER_NODE=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
        CORES_PER_NUMA="$(sysctl -n machdep.cpu.core_count)"
    else
        NUMAS_PER_NODE="$(lscpu | grep 'Socket(s)' | awk '{print $2}')"
        RAM_PER_NODE="$(free -m | head -2 | tail -1 | awk '{print $2}')"
        CORES_PER_NUMA="$(lscpu | grep 'Core(s) per socket' | awk '{print $4}')"
    fi
    RAM_PER_NUMA=$(( RAM_PER_NODE / 2 / NUMAS_PER_NODE )) # use half the available system memory
    if [[ "$USE_CUDA" == 1 ]]; then
        GPUS_PER_NODE="$(nvidia-smi -q | grep 'Attached GPUs' | awk '{print $4}')"
        FB_PER_GPU=$(( $(nvidia-smi --format=csv,noheader,nounits --query-gpu=memory.total -i 0) - 2000 ))
    fi
fi

# Calculate available resources per OpenMP group
NUM_OMPS=$(( NUMAS_PER_NODE * $NODE_RATIO ))
if [[ $NUM_OMPS -lt 1 ]]; then
    NUM_OMPS=1
    CORES_PER_OMP=$(( CORES_PER_NUMA * NUMAS_PER_NODE * $NODE_RATIO ))
    RAM_PER_OMP=$(( RAM_PER_NUMA * NUMAS_PER_NODE * $NODE_RATIO ))
else
    CORES_PER_OMP="$CORES_PER_NUMA"
    RAM_PER_OMP="$RAM_PER_NUMA"
fi
NUM_CORES=$(( NUM_OMPS * CORES_PER_OMP ))
WORK_RAM=$(( NUM_OMPS * RAM_PER_OMP ))
if [[ "$USE_CUDA" == 1 ]]; then
    NUM_GPUS=$(( GPUS_PER_NODE * $NODE_RATIO ))
fi

# Add legate driver to command
if [[ "$NODRIVER" != 1 ]]; then
    set -- --nodes "$NUM_NODES" --ranks-per-node "$RANKS_PER_NODE" "$@"
    set -- --verbose --log-to-file "$@"

    # Split available resources between ranks
    if [[ "$USE_CUDA" == 1 ]]; then
        # Need at least 2 more cores, for 1 CPU processor and 1 Python processor
        RESERVED_CORES=$(( RESERVED_CORES + 2 ))
        if (( RESERVED_CORES > NUM_CORES )); then
            echo "Error: Not enough cores, try reducing RESERVED_CORES" 1>&2
            exit 1
        fi
        set -- --gpus "$NUM_GPUS" --fbmem "$FB_PER_GPU" "$@"
        set -- --cpus 1 --sysmem $(( WORK_RAM>4000 ? 4000 : WORK_RAM)) "$@"
    elif [[ "$USE_OPENMP" == 1 ]]; then
        # Need at least 2 more cores, for 1 CPU processor and 1 Python processor
        RESERVED_CORES=$(( RESERVED_CORES + 2 ))
        # These reserved cores must be subtracted equally from each OpenMP group
        RESERVED_PER_OMP=$(( ( RESERVED_CORES + NUM_OMPS - 1 ) / NUM_OMPS ))
        if (( RESERVED_PER_OMP >= CORES_PER_OMP )); then
            echo "Error: Not enough cores, try reducing RESERVED_CORES" 1>&2
            exit 1
        fi
        THREADS_PER_OMP=$(( CORES_PER_OMP - RESERVED_PER_OMP ))
        set -- --cpus 1 --sysmem 256 "$@"
        set -- --omps "$NUM_OMPS" --ompthreads "$THREADS_PER_OMP" "$@"
        set -- --numamem "$RAM_PER_OMP" "$@"
    else
        # Need at least 1 more core, for the Python processor
        RESERVED_CORES=$(( RESERVED_CORES + 1 ))
        if (( RESERVED_CORES >= NUM_CORES )); then
            echo "Error: Not enough cores, try reducing RESERVED_CORES" 1>&2
            exit 1
        fi
        set -- --cpus $(( NUM_CORES - RESERVED_CORES )) --sysmem "$WORK_RAM" "$@"
    fi

    # Add launcher options
    if [[ "$PLATFORM" == summit ]]; then
        set -- --launcher jsrun "$@"
    elif [[ "$PLATFORM" == cori ]]; then
        # Use the first NIC from each pair
        set -- --nic-bind mlx5_0,mlx5_2,mlx5_4,mlx5_6 "$@"
        set -- --launcher srun "$@"
    elif [[ "$PLATFORM" == pizdaint ]]; then
        set -- --launcher srun "$@"
    elif [[ "$PLATFORM" == sapling ]]; then
        set -- --launcher mpirun "$@"
    elif [[ "$PLATFORM" == lassen ]]; then
        set -- --launcher jsrun "$@"
    else
        # Local run
        if (( RANKS_PER_NODE > 1 )); then
            set -- --launcher mpirun "$@"
        else
            set -- --launcher none "$@"
        fi
    fi

    set -- legate "$@"
fi

# Submit job to appropriate scheduler
if [[ "$PLATFORM" == summit ]]; then
    set -- "$SCRIPT_DIR/legate.lsf" "$@"
    QUEUE="${QUEUE:-batch}"
    if [[ "$INTERACTIVE" == 1 ]]; then
        set -- -Is "$@"
    else
        set -- -o "$HOST_OUT_DIR/out.txt" "$@"
    fi
    set -- bsub -J legate -P "$ACCOUNT" -q "$QUEUE" -W "$TIMELIMIT" -nnodes "$NUM_NODES" -alloc_flags smt1 "$@"
    submit "$@"
elif [[ "$PLATFORM" == cori ]]; then
    set -- "$SCRIPT_DIR/legate.slurm" "$@"
    # We double the number of cores because SLURM counts virtual cores
    set -- -J legate -A "$ACCOUNT" -t "$TIMELIMIT" -N "$NUM_NODES" "$@"
    set -- --ntasks-per-node "$RANKS_PER_NODE" -c $(( 2 * NUM_CORES )) "$@"
    if [[ "$USE_CUDA" == 1 ]]; then
        set -- -C gpu --gpus-per-task "$NUM_GPUS" "$@"
    fi
    if [[ "$INTERACTIVE" == 1 ]]; then
        set -- salloc -q interactive "$@"
    else
        set -- sbatch -q regular -o "$HOST_OUT_DIR/out.txt" "$@"
    fi
    submit "$@"
elif [[ "$PLATFORM" == pizdaint ]]; then
    set -- "$SCRIPT_DIR/legate.slurm" "$@"
    QUEUE="${QUEUE:-normal}"
    set -- -J legate -A "$ACCOUNT" -p "$QUEUE" -t "$TIMELIMIT" -N "$NUM_NODES" "$@"
    if [[ "$USE_CUDA" == 1 ]]; then
        set -- -C gpu "$@"
    fi
    if [[ "$INTERACTIVE" == 1 ]]; then
        set -- salloc "$@"
    else
        set -- sbatch -o "$HOST_OUT_DIR/out.txt" "$@"
    fi
    submit "$@"
elif [[ "$PLATFORM" == sapling ]]; then
    set -- "$SCRIPT_DIR/legate.slurm" "$SCRIPT_DIR/sapling_run.sh" "$@"
    QUEUE="${QUEUE:-gpu}"
    set -- -J legate -p "$QUEUE" -t "$TIMELIMIT" -N "$NUM_NODES" "$@"
    if [[ "$RATIO_OF_NODE_USED" == 1 ]]; then
        set -- --exclusive "$@"
    fi
    if [[ "$INTERACTIVE" == 1 ]]; then
        set -- salloc "$@"
    else
        set -- sbatch -o "$HOST_OUT_DIR/out.txt" "$@"
    fi
    submit "$@"
elif [[ "$PLATFORM" == lassen ]]; then
    set -- "$SCRIPT_DIR/legate.lsf" "$@"
    QUEUE="${QUEUE:-pbatch}"
    if [[ "$INTERACTIVE" == 1 ]]; then
        set -- -Is "$@"
    else
        set -- -o "$HOST_OUT_DIR/out.txt" "$@"
    fi
    set -- bsub -J legate -P "$ACCOUNT" -q "$QUEUE" -W "$TIMELIMIT" -nnodes "$NUM_NODES" -alloc_flags smt1 "$@"
    submit "$@"
else
    # Local run
    run_command "$@" 2>&1 | tee -a "$CMD_OUT_DIR/out.txt"
fi

# Wait for batch job to start
if [[ "$INTERACTIVE" != 1 && "$NOWAIT" != 1 ]]; then
    echo "Waiting for job to start & piping stdout/stderr"
    echo "Press Ctrl-C anytime to exit (job will still run)"
    while [[ ! -f "$HOST_OUT_DIR/out.txt" ]]; do sleep 1; done
    echo "Job started"
    sed '/^Job finished/q' <( exec tail -n +0 -f "$HOST_OUT_DIR/out.txt" ) && kill $!
fi
