#!/bin/bash

# Copyright 2022 NVIDIA Corporation
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

# We have to manually reload modules when moving to a compute node, because the
# SLURM version installed on the head node is incompatible with that on the
# compute nodes.

unset module
unset MODULESHOME
unset LOADEDMODULES
unset MODULEPATH
unset _LMFILES_
. /usr/share/modules/init/bash
module load cuda/11.1 mpi/openmpi/4.1.0 slurm/20.11.4
"$@"
