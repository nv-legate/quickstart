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
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$SCRIPT_DIR/common.sh"

# Print usage if requested
if [[ $# -lt 2 || ! "$1" =~ ^(1/)?[0-9]+$ ]]; then
    echo "Usage: $(basename "${BASH_SOURCE[0]}") <num-nodes> <prog.py> <arg1> <arg2> ..."
    echo "Positional arguments:"
    echo "  <num-nodes> : positive integer or ratio < 1 (e.g. 1/4, for partial-node runs)"
    echo "  <argI> : arguments to the program itself, Legate or Legion"
    echo "           see \$LEGATE_DIR/bin/legate -h for options accepted by Legate"
    echo "           see the Legion README for options accepted by Legion"
    echo "Arguments read from the environment:"
    echo "  ACCOUNT : account/group/project to submit the job under (if applicable)"
    echo "  IMAGE : which image to use (for container-based clusters)"
    echo "          (default : ghcr.io/nv-legate/legate-\$PLATFORM:latest)"
    echo "  INTERACTIVE : submit an interactive rather than a batch job (defaut: 0)"
    echo "  JOBSCRIPT : what jobscript to submit (defaut: appropriate script in $SCRIPT_DIR)"
    echo "  LEGATE_DIR : path to Legate installation directory"
    echo "  MOUNTS : comma-separated list of volume mounts (for container-based clusters)"
    echo "           (syntax depends on cluster) (default: none)"
    echo "  NODRIVER : don't invoke the Legate driver script (defaut: 0)"
    echo "  NOWAIT : don't wait for batch jobs to start (default: 0)"
    echo "  PLATFORM : what machine we are executing on (default: auto-detected)"
    echo "  QUEUE : what queue/partition to submit the job to (default: depends on cluster)"
    echo "  SCRATCH : where to create an output directory (default: .)"
    echo "  TIMELIMIT : how much time to request for the job, in minutes (defaut: 60)"
    echo "  USE_CUDA : run with CUDA enabled (defaut: auto-detected)"
    echo "  USE_OPENMP : run with OpenMP enabled (defaut: auto-detected)"
    exit
fi

# Read arguments
if [[ "$1" =~ [0-9]+/[0-9]+ ]]; then
    NUM_NODES=1
    NODE_RATIO="$1"
else
    NUM_NODES="$1"
    NODE_RATIO=1
fi
shift
detect_platform
if [[ "$PLATFORM" == summit ]]; then
    CONTAINER_BASED=0
elif [[ "$PLATFORM" == cori ]]; then
    CONTAINER_BASED=0
elif [[ "$PLATFORM" == pizdaint ]]; then
    CONTAINER_BASED=0
elif [[ "$PLATFORM" == lassen ]]; then
    CONTAINER_BASED=0
else
    CONTAINER_BASED=0
fi
export IMAGE="${IMAGE:-ghcr.io/nv-legate/legate-$PLATFORM:latest}"
export INTERACTIVE="${INTERACTIVE:-0}"
if [[ "$CONTAINER_BASED" == 1 ]]; then
    export LEGATE_DIR=/opt/legate/install
else
    true "$LEGATE_DIR"
fi
export MOUNTS="${MOUNTS:-}"
export NODRIVER="${NODRIVER:-0}"
export NOWAIT="${NOWAIT:-0}"
export SCRATCH="${SCRATCH:-.}"
export TIMELIMIT="${TIMELIMIT:-60}"
export USE_CUDA="${USE_CUDA:-1}"
if ! grep -q '#define REALM_USE_CUDA' "$LEGATE_DIR"/include/realm_defines.h; then
    export USE_CUDA=0
fi
export USE_OPENMP="${USE_OPENMP:-1}"
if ! grep -q '#define REALM_USE_OPENMP' "$LEGATE_DIR"/include/realm_defines.h; then
    export USE_OPENMP=0
fi

# We explicitly add the Conda lib dir, to ensure the Conda libraries we load
# will look there for their dependencies first, instead of trying to link with
# the corresponding system-wide versions.
if [[ "$CONTAINER_BASED" == 0 ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
        export DYLD_LIBRARY_PATH="$CONDA_PREFIX"/lib:"${DYLD_LIBRARY_PATH:-}"
    else
        export LD_LIBRARY_PATH="$CONDA_PREFIX"/lib:"${LD_LIBRARY_PATH:-}"
    fi
fi

# Prepare output directory
DATE="$(date +%Y/%m/%d)"
TIME="$(date +%H%M%S)"
mkdir -p "$SCRATCH/$DATE"
export HOST_OUT_DIR="$SCRATCH/$DATE/$TIME"
mkdir "$HOST_OUT_DIR"
echo "Redirecting output to $HOST_OUT_DIR"
if [[ "$CONTAINER_BASED" == 1 ]]; then
    export CMD_OUT_DIR=/result
else
    export CMD_OUT_DIR="$HOST_OUT_DIR"
fi

# Calculate per-rank resources
# Note that we need to set aside some CPU cores:
# - 1 for the CPU processor
# - 1 for the python processor
# - 2 for the utility processors
# - a few more for Realm worker threads and GPU processors
# and some memory:
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
    THREADS_PER_OMP=16
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
    THREADS_PER_OMP=16
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
    THREADS_PER_OMP=8
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
    THREADS_PER_OMP=16
    FB_PER_GPU=14500
else
    echo "Did not detect a supported cluster, assuming local-node run."
    export NOWAIT=1
    if [[ "$NUM_NODES" != 1 ]]; then
        echo "Error: Only 1 node is available, but $NUM_NODES were requested" 1>&2
        exit 1
    fi
    # Auto-detect available resources
    NUMAS_PER_NODE="$(lscpu | grep 'Socket(s)' | awk '{print $2}')"
    RAM_PER_NODE="$(free -m | head -2 | tail -1 | awk '{print $2}')"
    RAM_PER_NUMA=$(( RAM_PER_NODE * 4 / 5 / NUMAS_PER_NODE ))
    CORES_PER_NUMA=$(lscpu | grep 'Core(s) per socket' | awk '{print $4}')
    THREADS_PER_OMP=$(( CORES_PER_NUMA - 4 ))
    if [[ "$USE_CUDA" == 1 ]]; then
        GPUS_PER_NODE="$(nvidia-smi -q | grep 'Attached GPUs' | awk '{print $4}')"
        FB_PER_GPU=$(( $(nvidia-smi --format=csv,noheader,nounits --query-gpu=memory.total -i 0) - 2000 ))
    fi
fi
NUM_OMPS=$(( NUMAS_PER_NODE * $NODE_RATIO ))
if [[ $NUM_OMPS -lt 1 ]]; then
    NUM_OMPS=1
    THREADS_PER_OMP=$(( THREADS_PER_OMP * NUMAS_PER_NODE * $NODE_RATIO ))
    RAM_PER_NUMA=$(( RAM_PER_NUMA * NUMAS_PER_NODE * $NODE_RATIO ))
fi
NUM_CORES=$(( NUMAS_PER_NODE * CORES_PER_NUMA * $NODE_RATIO ))
if [[ "$USE_CUDA" == 1 ]]; then
    NUM_GPUS=$(( GPUS_PER_NODE * $NODE_RATIO ))
fi

# Add legate driver to command
if [[ "$NODRIVER" != 1 ]]; then
    set -- --nodes "$NUM_NODES" --verbose --logdir "$CMD_OUT_DIR" "$@"
    if [[ "$USE_CUDA" == 1 ]]; then
        set -- --gpus "$NUM_GPUS" --fbmem "$FB_PER_GPU" "$@"
    fi
    if [[ "$USE_OPENMP" == 1 ]]; then
        set -- --cpus 1 --sysmem 256 "$@"
        set -- --omps "$NUM_OMPS" --ompthreads "$THREADS_PER_OMP" "$@"
        set -- --numamem "$RAM_PER_NUMA" "$@"
    else
        set -- --cpus $(( NUM_OMPS * THREADS_PER_OMP )) "$@"
        set -- --sysmem $(( NUM_OMPS * RAM_PER_NUMA )) "$@"
    fi
    if [[ "$PLATFORM" == summit ]]; then
        set -- --cores-per-node $(( NUMAS_PER_NODE * CORES_PER_NUMA)) --launcher jsrun "$@"
    elif [[ "$PLATFORM" == cori ]]; then
        set -- --launcher srun "$@"
    elif [[ "$PLATFORM" == pizdaint ]]; then
        set -- --launcher srun "$@"
    elif [[ "$PLATFORM" == lassen ]]; then
        set -- --cores-per-node $(( NUMAS_PER_NODE * CORES_PER_NUMA)) --launcher jsrun "$@"
    else
        # Local run
        true
    fi
    set -- "$LEGATE_DIR/bin/legate" "$@" -logfile "$CMD_OUT_DIR"/%.log
fi

# Submit job to appropriate scheduler
if [[ "$PLATFORM" == summit ]]; then
    JOBSCRIPT="${JOBSCRIPT:-$SCRIPT_DIR/legate.lsf}"
    set -- "$JOBSCRIPT" "$@"
    QUEUE="${QUEUE:-batch}"
    if [[ "$INTERACTIVE" == 1 ]]; then
        set -- -Is "$@"
    else
        set -- -o "$HOST_OUT_DIR/out.txt" "$@"
    fi
    set -- bsub -J legate -P "$ACCOUNT" -q "$QUEUE" -W "$TIMELIMIT" -nnodes "$NUM_NODES" -alloc_flags smt1 "$@"
    echo "Submitted: $@"
    "$@"
elif [[ "$PLATFORM" == cori ]]; then
    # Use the first NIC from each pair
    export GASNET_IBV_PORTS=mlx5_0+mlx5_2+mlx5_4+mlx5_6
    JOBSCRIPT="${JOBSCRIPT:-$SCRIPT_DIR/legate.slurm}"
    set -- "$JOBSCRIPT" "$@"
    # We double the number of cores because SLURM counts virtual cores
    set -- -J legate -A "$ACCOUNT" -t "$TIMELIMIT" -N "$NUM_NODES" --ntasks-per-node 1 -c $(( 2 * $NUM_CORES )) -C gpu --gpus-per-task "$NUM_GPUS" "$@"
    if [[ "$INTERACTIVE" == 1 ]]; then
        set -- salloc -q interactive "$@"
    else
        set -- sbatch -q regular -o "$HOST_OUT_DIR/out.txt" "$@"
    fi
    echo "Submitted: $@"
    "$@"
elif [[ "$PLATFORM" == pizdaint ]]; then
    JOBSCRIPT="${JOBSCRIPT:-$SCRIPT_DIR/legate.slurm}"
    set -- "$JOBSCRIPT" "$@"
    QUEUE="${QUEUE:-normal}"
    set -- -J legate -A "$ACCOUNT" -p "$QUEUE" -t "$TIMELIMIT" -N "$NUM_NODES" -C gpu "$@"
    if [[ "$INTERACTIVE" == 1 ]]; then
        set -- salloc "$@"
    else
        set -- sbatch -o "$HOST_OUT_DIR/out.txt" "$@"
    fi
    echo "Submitted: $@"
    "$@"
elif [[ "$PLATFORM" == lassen ]]; then
    JOBSCRIPT="${JOBSCRIPT:-$SCRIPT_DIR/legate.lsf}"
    set -- "$JOBSCRIPT" "$@"
    QUEUE="${QUEUE:-pbatch}"
    if [[ "$INTERACTIVE" == 1 ]]; then
        set -- -Is "$@"
    else
        set -- -o "$HOST_OUT_DIR/out.txt" "$@"
    fi
    set -- bsub -J legate -P "$ACCOUNT" -q "$QUEUE" -W "$TIMELIMIT" -nnodes "$NUM_NODES" -alloc_flags smt1 "$@"
    echo "Submitted: $@"
    "$@"
else
    # Local run
    echo "Command: $@" | tee -a "$CMD_OUT_DIR/out.txt"
    "$@" | tee -a "$CMD_OUT_DIR/out.txt"
fi

# Wait for batch job to start
if [[ "$INTERACTIVE" != 1 && "$NOWAIT" != 1 ]]; then
    echo "Waiting for job to start & piping output"
    echo "Press Ctrl-C anytime to exit (job will still run)"
    while [[ ! -f "$HOST_OUT_DIR/out.txt" ]]; do sleep 1; done
    echo "Job started"
    tail -n +0 -f "$HOST_OUT_DIR/out.txt" | sed '/^Job finished/ q'
fi
