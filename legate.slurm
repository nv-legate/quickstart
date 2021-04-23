#!/bin/bash
set -u

# This script reads the following variables from the environment:
#   CMD_OUT_DIR : output directory to use on the commands
#     Will be mounted appropriately on container-based clusters, to match
#     $HOST_OUT_DIR. Ignored on bare-metal clusters.
#   ENTRYPOINT : entrypoint script to use (for container-based clusters)
#   IMAGE : which image to use (for container-based clusters)
#   INTERACTIVE : submit an interactive rather than a batch job
#   HOST_OUT_DIR : output directory on the host filesystem
#   MOUNTS : comma-separated list of volume mounts (for container-based clusters)
#   PLATFORM : what machine we are executing on
#   $@ : the command to execute

if [[ "$PLATFORM" == cori ]]; then
    true
elif [[ "$PLATFORM" == pizdaint ]]; then
    true
else
    echo "Error: Unexpected platform $PLATFORM in SLURM script" 1>&2
    exit 1
fi

echo "Job ID: $SLURM_JOBID"
echo "Submitted from: $(pwd)"
echo "Started on: $(date)"
echo "Command: $@"
echo "Running on: $SLURM_JOB_NODELIST"
"$@"
echo "Job finished"
