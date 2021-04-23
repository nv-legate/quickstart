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
    echo "           see $LEGATE_DIR/bin/legate -h for options accepted by Legate"
    echo "           see the Legion README for options accepted by Legion"
    echo "Arguments read from the environment:"
    echo "  ACCOUNT : account/group/project to submit the job under (if applicable)"
    echo "  ENTRYPOINT : entrypoint script to use (for container-based clusters)"
    echo "               (default : /opt/legate/quickstart/entrypoint.sh)"
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
export ENTRYPOINT="${ENTRYPOINT:-/opt/legate/quickstart/entrypoint.sh}"
export IMAGE="${IMAGE:-ghcr.io/nv-legate/legate-$PLATFORM:latest}"
export INTERACTIVE="${INTERACTIVE:-0}"
true "$LEGATE_DIR"
export MOUNTS="${MOUNTS:-}"
export NODRIVER="${NODRIVER:-0}"
export NOWAIT="${NOWAIT:-0}"
export SCRATCH="${SCRATCH:-.}"
export TIMELIMIT="${TIMELIMIT:-60}"

# Prepare output directory
DATE="$(date +%Y/%m/%d)"
TIME="$(date +%H%M%S)"
mkdir -p "$SCRATCH/$DATE"
export HOST_OUT_DIR="$SCRATCH/$DATE/$TIME"
mkdir "$HOST_OUT_DIR"
echo "Redirecting output to $HOST_OUT_DIR"
export CMD_OUT_DIR="$HOST_OUT_DIR"

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
    THREADS_PER_OMP=8
    FB_PER_GPU=14500
else
    echo "Did not detect a supported cluster, assuming local-node run."
    if [[ "$NUM_NODES" != 1 ]]; then
        echo "Error: Only 1 node is available, but $NUM_NODES were requested" 1>&2
        exit 1
    fi
    # Auto-detect available resources
    NUM_SOCKETS="$(lscpu | grep 'Socket(s)' | awk '{print $2}')"
    NUMAS_PER_NODE="$NUM_SOCKETS"
    RAM_PER_NODE="$(free -m | head -2 | tail -1 | awk '{print $2}')"
    RAM_PER_NUMA=$(( RAM_PER_NODE * 4 / 5 / NUMAS_PER_NODE ))
    GPUS_PER_NODE="$(nvidia-smi -q | grep 'Attached GPUs' | awk '{print $4}')"
    CORES_PER_SOCKET=$(lscpu | grep 'Core(s) per socket' | awk '{print $4}')
    THREADS_PER_OMP=$(( CORES_PER_SOCKET - 4 ))
    FB_PER_GPU="$(nvidia-smi --format=csv,noheader,nounits --query-gpu=memory.total -i 0)"
    FB_PER_GPU=$(( FB_PER_GPU - 2000 ))
fi
NUM_OMPS=$(( NUMAS_PER_NODE * $NODE_RATIO ))
if [[ $NUM_OMPS -lt 1 ]]; then
    NUM_OMPS=1
    THREADS_PER_OMP=$(( THREADS_PER_OMP * NUMAS_PER_NODE * $NODE_RATIO ))
fi
NUM_GPUS=$(( GPUS_PER_NODE * $NODE_RATIO ))

# Add legate driver to command
if [[ "$NODRIVER" != "1" ]]; then
    set -- --nodes "$NUM_NODES" --verbose --logdir "$CMD_OUT_DIR" "$@"
    set -- --cpus 1 --omps "$NUM_OMPS" --ompthreads "$THREADS_PER_OMP" "$@"
    set -- --sysmem 256 --numamem "$RAM_PER_NUMA" "$@"
    set -- --gpus "$NUM_GPUS" --fbmem "$FB_PER_GPU" "$@"
    if [[ "$PLATFORM" == summit ]]; then
        set -- --cores-per-node 42 --launcher jsrun "$@"
    elif [[ "$PLATFORM" == cori ]]; then
        set -- --launcher srun "$@"
    elif [[ "$PLATFORM" == pizdaint ]]; then
        set -- --launcher srun "$@"
    else
        # Local run
        true
    fi
    set -- "$LEGATE_DIR/bin/legate" "$@" -logfile "$CMD_OUT_DIR"/%.log
fi

# Submit job to appropriate scheduler
if [[ "$PLATFORM" == summit ]]; then
    JOBSCRIPT="${JOBSCRIPT:-$SCRIPT_DIR/legate.lsf}"
    QUEUE="${QUEUE:-batch}"
    if [[ "$INTERACTIVE" == "1" ]]; then
        bsub -J legate -P "$ACCOUNT" -q "$QUEUE" -W "$TIMELIMIT" -nnodes "$NUM_NODES" -alloc_flags smt1 -Is "$JOBSCRIPT" "$@"
    else
        bsub -J legate -P "$ACCOUNT" -q "$QUEUE" -W "$TIMELIMIT" -nnodes "$NUM_NODES" -alloc_flags smt1 -o "$HOST_OUT_DIR/out.txt" "$JOBSCRIPT" "$@"
    fi
elif [[ "$PLATFORM" == cori ]]; then
    JOBSCRIPT="${JOBSCRIPT:-$SCRIPT_DIR/legate.slurm}"
    QUEUE="${QUEUE:-debug}"
    if [[ "$INTERACTIVE" == "1" ]]; then
        echo "Error: Interactive jobs not supported on this cluster (yet)" 1>&2
        exit 1
    else
        sbatch -J legate -A "$ACCOUNT" -p "$QUEUE" -t "$TIMELIMIT" -N "$NUM_NODES" --exclusive -C gpu -o "$HOST_OUT_DIR/out.txt" "$JOBSCRIPT" "$@"
    fi
elif [[ "$PLATFORM" == pizdaint ]]; then
    JOBSCRIPT="${JOBSCRIPT:-$SCRIPT_DIR/legate.slurm}"
    QUEUE="${QUEUE:-normal}"
    if [[ "$INTERACTIVE" == "1" ]]; then
        salloc -J legate -A "$ACCOUNT" -p "$QUEUE" -t "$TIMELIMIT" -N "$NUM_NODES" -C gpu "$JOBSCRIPT" "$@"
    else
        sbatch -J legate -A "$ACCOUNT" -p "$QUEUE" -t "$TIMELIMIT" -N "$NUM_NODES" -C gpu -o "$HOST_OUT_DIR/out.txt" "$JOBSCRIPT" "$@"
    fi
else
    # Local run
    echo "Command: $@" | tee -a "$CMD_OUT_DIR/out.txt"
    "$@" | tee -a "$CMD_OUT_DIR/out.txt"
fi

# Wait for batch job to start
if [[ "$INTERACTIVE" != "1" && "$NOWAIT" != "1" && "$PLATFORM" != other ]]; then
    echo "Waiting for job to start & piping output"
    echo "Press Ctrl-C anytime to exit (job will still run)"
    while [[ ! -f "$HOST_OUT_DIR/out.txt" ]]; do sleep 1; done
    echo "Job started"
    tail -n +0 -f "$HOST_OUT_DIR/out.txt" | sed '/^Job finished/ q'
fi
