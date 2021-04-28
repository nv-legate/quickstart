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
