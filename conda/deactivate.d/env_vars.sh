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

function path_remove {
  local P="$1"
  P="${P//":$2:"/:}" # delete any instances in the middle
  P="${P/#"$2:"/}" # delete any instance at the beginning
  P="${P/%":$2"/}" # delete any instance at the end
  echo "$P"
}
export CPATH="$( path_remove "$CPATH" "$CONDA_PREFIX/include" )"
export LIBRARY_PATH="$( path_remove "$LIBRARY_PATH" "$CONDA_PREFIX/lib" )"
# $CONDA_PREFIX/bin is removed from PATH automatically
