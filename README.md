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

# Introduction

Legate quickstart provides a collection of scripts to simplify building,
installing, and running of Legate libraries.  Currently, there are two ways to
use Legate: building from source and using a pre-built Docker image.

# Using a pre-built Docker image

At this time, we provide two versions of Legate images: a Volta architecture
image and an Ampere architecture image.  The images are available at TODO and
can be accessed as follows with

```
docker pull TODO
```

for the Volta image and 

```
docker pull TODO
```

Here is an example of running one of some of the examples included on the
images:

```
docker run -it --rm TODO /bin/bash
```

One can begin by running some tests:

```
$ cd /opt/legate/legate.numpy/
$ ./test.py --use cuda --use cpus --use openmp
$ cd /opt/legate/legate.pandas/
$ ./test.py
$ ./test.py --use cuda
```

There are also some example programs to try:

``` 
$ cd /opt/legate/legate.numpy/examples
$ legate --gpus 1 stencil.py -n 1000 -t -b 10 --fbmem 15000
```

The `-n` option controls the size of the problem, the `-t` option turns on
timing, and the `-b` option controls how many times to repeat the benchmark.
A join micro benchmark in Legate Pandas can be run as follows:

```
$ cd /opt/legate/legate.pandas/
$ legate --gpus 1 --fbmem 15000 ./benchmarks/micro/merge.py --size_per_proc 10000 --num_runs 10
```

# Building from source

Find your platform below and follow the instructions to set up legate. If you
are running on a supported cluster then all the scripts will automatically
invoke the appropriate job scheduler commands, so you don't need to create
jobscripts yourself.

### Base requirements

* gcc 5.4+
* GNU build tools (make, autoconf, ...)
* CUDA 10.1+ (if running on GPUs)
* a PMI-based launcher (e.g. mpirun, jsrun, srun) (if running multi-node)
* a networking stack compatible with [GASNet](https://gasnet.lbl.gov) (e.g.
  Infiniband, RoCE, Aries) (if running multi-node)

### Customizing installation

* `setup_conda.sh`: This script will create a new conda environment suitable for
  running legate applications on GPUs. Use `CUDA_VER=none` to skip GPU support.
  You can skip the script entirely if you prefer to install the required
  packages manually; see the `requirements.txt` file on the individual legate
  libraries.
* `install_ib_ucx.sh`: This script will remove the UCX conda package and build
  UCX from source, adding Infiniband Verbs support. You can skip this if you
  will not be running multi-node Rapids algorithms over Infiniband.
* `~/.bashrc`: The commands we add to this file activate the environment we set
  up for legate runs, and must be executed on every node in a multi-node run
  before invoking the legate executable. Note that the order of commands
  matters; we want the paths set by `conda` to supersede those set by `module`.
* Invoke any script with `-h` to see more available options.

### Working on container-based clusters

* Images including all legate libraries are generated periodically for all
  supported container-based clusters (e.g. NGC, Circe, Selene), and `run.sh`
  will automatically use the latest version. On such clusters you don't need to
  build anything; just call `run.sh` from the login node.
* If you wish to use a custom image, you can set the `IMAGE` argument of
  `run.sh`. You can use `Dockerfile` as a starting point for generating custom
  legate images; you may need to remove parts of this recipe if your cluster
  doesn't use GPUs or Mellanox hardware.
* All paths on the legate command line refer to files within the image. The
  host's filesystem is not normally accessible while running; you need to
  explicitly mount directories inside the container (see the `MOUNTS` argument
  of `run.sh`).
* If you wish to port legate to a new container-based cluster note the
  following: In order to use GPUs from inside a container, the host needs to
  provide a CUDA installation at least as recent as the version used in the
  image, and a GPU-aware container execution engine like
  [nvidia-docker](https://github.com/NVIDIA/nvidia-docker). To use Mellanox
  hardware from inside a container, the host and the image must use the same
  version of MOFED.

Local machine
=============

Add to `~/.bashrc`:

```
source "<conda-install-dir>/etc/profile.d/conda.sh"
conda activate legate
```

Run basic setup:

```
CONDA_ROOT=<conda-install-dir> <quickstart-dir>/setup_conda.sh
source "<conda-install-dir>/etc/profile.d/conda.sh"
conda activate legate
cd /path/to/legate.core
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Build additional legate libraries:

```
cd /path/to/legate/lib
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Run legate programs:

```
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/run.sh prog.py
```

Summit @ ORNL
=============

Add to `~/.bashrc`:

```
module load cuda/11.0.3 gcc/9.3.0
source "<conda-install-dir>/etc/profile.d/conda.sh"
conda activate legate
```

Log out and back in, then run:

```
CUDA_VER=none CONDA_ROOT=<conda-install-dir> <quickstart-dir>/setup_conda.sh
source "<conda-install-dir>/etc/profile.d/conda.sh"
conda activate legate
cd /path/to/legate.core
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Build additional legate libraries:

```
cd /path/to/legate/lib
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Run legate programs:

```
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/run.sh prog.py
```

CoriGPU @ LBL
=============

Add to `~/.bash_profile`:

```
source ~/.bashrc
```

Add to `~/.bashrc`:

```
module purge
module load esslurm cuda/10.2.89 gcc/8.3.0 python/3.7-anaconda-2019.10 openmpi/4.0.2
source ~/.conda/etc/profile.d/conda.sh
conda activate legate
```

Log out and back in, then run:

```
CONDA_ROOT=~/.conda <quickstart-dir>/setup_conda.sh
source ~/.conda/etc/profile.d/conda.sh
conda activate legate
<quickstart-dir>/install_ib_ucx.sh
cd /path/to/legate.core
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Build additional legate libraries:

```
cd /path/to/legate/lib
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Run legate programs:

```
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/run.sh prog.py
```
