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

Legate Quickstart provides scripts for building Legate libraries from source
and running Legate programs with appropriate defaults for a number of supported
clusters (and auto-detected settings for local installs).

The scripts in this repository will detect if you are running on the login node
of a supported cluster, and automatically use the appropriate flags to build and
run Legate.

The scripts will automatically invoke the appropriate job scheduler commands, so
you don't need to create jobscripts yourself. Please run the commands directly
from the login node.

Even if your specific cluster is not covered, you may be able to adapt an
existing workflow; look for all the places where the `PLATFORM` variable is
checked and add a case for your cluster.

You can use the same scripts on your local machine, in which case the build/run
flags will be set according to the detected hardware resources.

Invoke any script with `-h` to see more available options.

Bare-metal clusters
===================

This section covers clusters where you build on a distributed filesystem, and
run your application directly on the compute node hardware.

Cluster configuration
---------------------

Find your cluster below, and add the corresponding suggested setup instructions
to `~/.bash_profile`, `~/.bashrc` or similar shell startup file.


### Perlmutter @ NERSC

```
module load python
module load cudatoolkit
module load craype-accel-nvidia80
module load cray-pmi
module del cray-libsci
```

### Summit @ ORNL

```
module load cuda/11.0.3 gcc/9.3.0
# optionally: module load openblas/0.3.20-omp
# can then skip openblas from conda env, and build cuNumeric using --with-openblas $OLCF_OPENBLAS_ROOT
```

### PizDaint @ ETH

```
module swap PrgEnv-cray PrgEnv-gnu/6.0.9
module load daint-gpu
module load cudatoolkit/11.2.0_3.39-2.1__gf93aa1c
```

### Sapling2 @ Stanford

```
module load cuda/11.7 mpi/openmpi/4.1.5 slurm/23.02.1
```

### Lassen @ LLNL

```
module load gcc/8.3.1 cuda/11.1.0
```

Create a conda environment
--------------------------

Legate's build system is generally flexible regarding where the dependencies are
pulled from. However, the quickstart workflow in particular assumes a
conda-based editable installation. Follow the instructions at
https://github.com/nv-legate/legate.core/blob/HEAD/BUILD.md#getting-dependencies-through-conda
to install Legate's dependencies from conda. Ignore the following instructions
about using `install.py`, the quickstart scripts will invoke that internally.

Make sure you use an environment file with a `--ctk` version matching the
system-wide CUDA version (i.e. the version provided by the CUDA `module` you
load). Most commonly on clusters you will want to use the system-provided
compilers and MPI implementation, therefore you will likely want to use an
environment generated with `--no-compilers` and `--no-openmpi`.

You may wish to auto-activate this environment on login, by doing `conda activate`
in your shell startup file.

Build Legate libraries
----------------------

```
git clone https://gitlab.com/StanfordLegion/legion.git -b control_replication <legion-dir>
git clone https://github.com/nv-legate/legate.core <legate.core-dir>
git clone https://github.com/nv-legate/cunumeric <cunumeric-dir>
cd <legate.core-dir>
LEGION_DIR=<legion-dir> <quickstart-dir>/build.sh
cd <cunumeric-dir>
<quickstart-dir>/build.sh
```

Run Legate programs
-------------------

```
<quickstart-dir>/run.sh <num-nodes> <py-program> <args>
```

Container-based clusters
========================

On container-based clusters typically each user prepares an image ahead of time
and provides it at job submission time, to be instantiated on each allocated
node. Such clusters utilize a cluster-aware container engine, such as
[Pyxis](https://github.com/NVIDIA/pyxis)/[Enroot](https://github.com/NVIDIA/enroot),
[Singularity](https://apptainer.org) or
[Shifter](https://www.nersc.gov/research-and-development/user-defined-images/).

Build an image
--------------

The `make_image.sh` script can be used to build Docker images containing all
Legate libraries.

Certain build options, such as the target CUDA architecture, must be specified
appropriately at docker build time, to match the environment where the image
will be used. These options are specified for each supported target `PLATFORM`
in `common.sh`. The default `PLATFORM` is a generic non-networked machine
containing Volta GPUs. You can add custom configurations as new `PLATFORM`s in
`common.sh`.

After building the image, you can test it locally:

```
docker run -it --rm --gpus all <image> /bin/bash
```

Once inside the container, you can try running some examples:

```
legate --gpus 1 --fbmem 15000 /opt/legate/cunumeric/examples/gemm.py
```

Note the following general requirements for using Nvidia hardware within
containers: To use Nvidia GPUs from inside a container the host needs to
provide a CUDA installation at least as recent as the version used in the
image, and a GPU-aware container execution engine like
[nvidia-docker](https://github.com/NVIDIA/nvidia-docker). To use Nvidia
networking hardware from inside a container the host and the image must use
the same version of MOFED.

Run on the cluster
------------------

The `run.sh` script can handle container-based workflows when run directly on the
login node, but will need to be specialized for each particular cluster; look for
all the places where the `PLATFORM` variable is checked in `run.sh`, and add a
case for your cluster.

Even though you are meant to invoke the `run.sh` script from the login node, any
paths on the command line will refer to files within the image, not the
filesystem on the host cluster. For example, you cannot (by default) invoke a
python program stored on your home directory on the login node, only python
files already included within the image. If you wish to use files from a
directory on the host filesystem, you need to explicitly mount that directory
inside the container (see the `MOUNTS` argument of `run.sh`).

Questions
=========

If you have questions, please contact us at legate(at)nvidia.com.
