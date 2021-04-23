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

Legate Quickstart provides a collection of scripts to simplify building,
installing, and running Legate libraries. Currently there are two ways to
use Legate: building from source and using a pre-built Docker image.

Using a pre-built Docker image
==============================

At this time we provide two versions of an image containing all Legate
libraries, for the Volta and Ampere CUDA architectures. The images are available
on GitHub and can be used as follows:

```
docker pull ghcr.io/nv-legate/legate-other-volta:latest
docker run -it --rm ghcr.io/nv-legate/legate-other-volta:latest /bin/bash
```

and correspondingly for the `legate-other-ampere` image.

After entering the container, you can try running some examples:

```
# Legate NumPy 2d stencil example
/opt/legate/quickstart/run.sh 1 /opt/legate/legate.numpy/examples/stencil.py -n 1000 -t -b 10
# Legate Pandas join microbenchmark
/opt/legate/quickstart/run.sh 1 /opt/legate/legate.pandas/benchmarks/micro/merge.py --size_per_proc 10000 --num_runs 10
```

The `run.sh` script will automatically detect the resources available in the
container. If you wish to control that further, you can use the `legate` launcher
script directly:

```
# Legate NumPy 2d stencil example
legate --gpus 1 --fbmem 15000 /opt/legate/legate.numpy/examples/stencil.py -n 1000 -t -b 10
# Legate Pandas join microbenchmark
legate --gpus 1 --fbmem 15000 /opt/legate/legate.pandas/benchmarks/micro/merge.py --size_per_proc 10000 --num_runs 10
```

Invoke any script with `-h` to see more available options.

# Building from source

Find your platform below and follow the instructions to set up Legate. If you
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
  running Legate applications on GPUs. Use `CUDA_VER=none` to skip GPU support.
  You can skip the script entirely if you prefer to install the required
  packages manually; see the `conda/???.yml` files on the individual Legate
  libraries.
* `install_ib_ucx.sh`: This script will remove the UCX conda package and build
  UCX from source, adding Infiniband Verbs support. You can skip this if you
  will not be running multi-node Rapids algorithms over Infiniband.
* `~/.bashrc`: The commands we add to this file activate the environment we set
  up for Legate runs, and must be executed on every node in a multi-node run
  before invoking the Legate executable. Note that the order of commands
  matters; we want the paths set by `conda` to supersede those set by `module`.
* Invoke any script with `-h` to see more available options.

### Working on container-based clusters

* On container-based clusters typically each user will prepare an image
  ahead of time and provide it at job submission time, to be instantiated on
  each allocated node. The `run.sh` script can handle such worflows when run
  directly on the login node, but will need to be specialized for each
  particular cluster.
* You can use `Dockerfile` as a starting point for generating custom
  Legate images; you may need to remove parts of this recipe if your cluster
  does not use Nvidia GPUs or networking hardware. Pre-built images for any
  supported container-based clusters will be available on GitHub as
  `ghcr.io/nv-legate/legate-<platform>`, and `run.sh` will automatically use
  the latest version.
* All paths on the Legate command line refer to files within the image. The
  host's filesystem is not normally accessible while running; you need to
  explicitly mount directories inside the container (see the `MOUNTS` argument
  of `run.sh`).
* When porting Legate to a new container-based cluster note the following: In
  order to use Nvidia GPUs from inside a container the host needs to
  provide a CUDA installation at least as recent as the version used in the
  image, and a GPU-aware container execution engine like
  [nvidia-docker](https://github.com/NVIDIA/nvidia-docker). To use Nvidia
  networking hardware from inside a container the host and the image must use
  the same version of MOFED.

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

Build additional Legate libraries:

```
cd /path/to/legate/lib
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Run Legate programs:

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

Build additional Legate libraries:

```
cd /path/to/legate/lib
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Run Legate programs:

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

Build additional Legate libraries:

```
cd /path/to/legate/lib
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Run Legate programs:

```
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/run.sh prog.py
```

PizDaint @ ETH
==============

Add to `~/.bashrc`:

```
module swap PrgEnv-cray PrgEnv-gnu/6.0.9
module swap gcc/10.1.0 gcc/9.3.0
module load daint-gpu
module load cudatoolkit/11.0.2_3.33-7.0.2.1_3.1__g1ba0366
source "<conda-install-dir>/etc/profile.d/conda.sh"
conda activate legate
```

Log out and back in, then run:

```
CONDA_ROOT=<conda-install-dir> <quickstart-dir>/setup_conda.sh
source "<conda-install-dir>/etc/profile.d/conda.sh"
conda activate legate
cd /path/to/legate.core
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Build additional Legate libraries:

```
cd /path/to/legate/lib
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/build.sh
```

Run Legate programs:

```
LEGATE_DIR=<legate-install-dir> <quickstart-dir>/run.sh prog.py
```

Questions
=========

If you have questions, please contact us at legate(at)nvidia.com.
