<!--
Copyright 2021 NVIDIA Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

-->

Legate Quickstart
=================

Legate Quickstart provides two ways to simplify the use of Legate:

* Scripts for building Docker images containing source-builds of all Legate
  libraries

* Scripts for building Legate libraries from source and running Legate programs
  with appropriate defaults for a number of supported clusters (and
  auto-detected settings for local installs)

Building and using Docker images
================================

The `make_image.sh` script can be used to build Docker images containing all
Legate libraries.

Certain build options, such as the target CUDA architecture, must be specified
appropriately at docker build time, to match the environment where the image
will be used. These options are specified for each supported target `PLATFORM`
in `common.sh`. The default `PLATFORM` is a generic non-networked machine
containing Volta GPUs. You can add custom configurations as new `PLATFORM`s in
`common.sh`.

After building the image, you can use it to start a container :

```
docker run -it --rm --gpus all <image> /bin/bash
```

Inside the container you can try running some examples:

```
# CuNumeric 2d stencil example
/opt/legate/quickstart/run.sh 1 /opt/legate/cunumeric/examples/stencil.py -n 1000 -t -b 10
```

The `run.sh` script will automatically detect the resources available in the
container. If you wish to control that further, you can use the `legate` launcher
script directly:

```
# CuNumeric 2d stencil example
legate --gpus 1 --fbmem 15000 /opt/legate/cunumeric/examples/stencil.py -n 1000 -t -b 10
```

Invoke any script with `-h` to see more available options.

Note the following general requirements for using Nvidia hardware within
containers: To use Nvidia GPUs from inside a container the host needs to
provide a CUDA installation at least as recent as the version used in the
image, and a GPU-aware container execution engine like
[nvidia-docker](https://github.com/NVIDIA/nvidia-docker). To use Nvidia
networking hardware from inside a container the host and the image must use
the same version of MOFED.

Building and running on supported clusters
==========================================

The scripts in this repository will detect if you are running on a supported
cluster, and automatically use the appropriate flags to build and run Legate.

The scripts will automatically invoke the appropriate job scheduler commands, so
you don't need to create jobscripts yourself. Please run the commands directly
from the login node.

You can use the same scripts on your local machine, in which case the build/run
flags will be set according to the detected hardware resources.

Invoke any script with `-h` to see more available options.

Bare-metal clusters
-------------------

Legate's build system is generally flexible regarding where the dependencies are
pulled from. However, the quickstart workflow in particular assumes a
conda-based installation. Follow the instructions at
https://github.com/nv-legate/legate.core/blob/HEAD/BUILD.md#getting-dependencies-through-conda
to install Legate's dependencies from conda.

Make sure you use an environment file with a `--ctk` version matching the
system-wide CUDA version (i.e. the version provided by the CUDA `module` you
load). Most commonly on clusters you will want to use the system-provided
compilers and MPI implementation, therefore you will likely want to use an
environment generated with `--no-compilers` and `--no-openmpi`.

After you install and activate a suitable conda environment, you can build Legate libraries:

```
git clone https://gitlab.com/StanfordLegion/legion.git -b control_replication <legion-dir>
git clone https://github.com/nv-legate/legate.core <legate.core-dir>
git clone https://github.com/nv-legate/cunumeric <cunumeric-dir>
cd <legate.core-dir>
LEGION_DIR=<legion-dir> <quickstart-dir>/build.sh
cd <cunumeric-dir>
<quickstart-dir>/build.sh
```

and run Legate programs:

```
<quickstart-dir>/run.sh <num-nodes> <py-program> <args>
```

Suggested cluster configuration
-------------------------------

Here are some suggested module configurations for supported bare-metal clusters
(add these lines to `~/.bash_profile`, or similar shell startup file):

### Summit @ ORNL

```
module load cuda/11.0.3 gcc/9.3.0 openblas/0.3.20-omp
```

### CoriGPU @ LBL

```
# Cori runs even sub-shells in login mode, so guard these from running more than once
if [[ -z $CONDA_PREFIX ]]; then
    module purge
    module load cgpu esslurm cudatoolkit/10.2.89_3.28-7.0.1.1_2.1__g88d3d59 gcc/8.3.0 python/3.8-anaconda-2020.11 openmpi/4.0.2
fi
```

### PizDaint @ ETH

```
module swap PrgEnv-cray PrgEnv-gnu/6.0.9
module load daint-gpu
module load cudatoolkit/11.2.0_3.39-2.1__gf93aa1c
```

### Sapling @ Stanford

```
module load slurm/20.11.4
```

Note that the module environment needs to be reset as we enter a compute node,
since those nodes have a different lmod installation than the head node. The
switch is done in the `sapling_run.sh` script, which uses a pre-selected set of
modules, that you might wish to adjust.

### Lassen @ LLNL

```
module load gcc/8.3.1 cuda/11.1.0
```

Container-based clusters
------------------------

On container-based clusters typically each user prepares an image ahead of time
and provides it at job submission time, to be instantiated on each allocated
node. The `run.sh` script can handle such worflows when run directly on the
login node, but will need to be specialized for each particular cluster.

Even though you are meant to invoke the `run.sh` script from the login node, any
paths on the command line will refer to files within the image, not the
filesystem on the host cluster. For example, you cannot (by default) invoke a
python program stored on your home directory on the login node, only python
files already included within the image. If you wish to use files from a
directory on the host filesystem, you need to explicitly mount that directory
inside the container (see the `MOUNTS` argument of `run.sh`).

Also see the [general advice](#building-and-using-docker-images) on using the
Legate Docker images.

Questions
=========

If you have questions, please contact us at legate(at)nvidia.com.
