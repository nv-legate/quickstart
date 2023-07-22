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

# PLEASE USE make_image.sh INSTEAD OF USING THIS DOCKERFILE DIRECTLY

# Parent image
ARG CUDA_VER
ARG LINUX_VER
FROM nvidia/cuda:${CUDA_VER}-devel-${LINUX_VER}

# Build arguments
ARG CONDUIT
ENV CONDUIT=${CONDUIT}
ARG CUDA_VER
ENV CUDA_VER=${CUDA_VER}
ARG DEBUG
ENV DEBUG=${DEBUG}
ARG DEBUG_RELEASE
ENV DEBUG_RELEASE=${DEBUG_RELEASE}
ARG GPU_ARCH
ENV GPU_ARCH=${GPU_ARCH}
ARG LINUX_VER
ENV LINUX_VER=${LINUX_VER}
ARG MOFED_VER
ENV MOFED_VER=${MOFED_VER}
ARG NETWORK
ENV NETWORK=${NETWORK}
ARG PYTHON_VER
ENV PYTHON_VER=${PYTHON_VER}
ARG USE_SPY
ENV USE_SPY=${USE_SPY}
ENV USE_CUDA=1
ENV USE_OPENMP=1

# Execute RUN commands in strict mode
SHELL [ "/bin/bash", "-eo", "pipefail", "-c" ]

# Install apt packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && if [[ "$NETWORK" != none ]]; then \
      apt-get install -y --no-install-recommends \
        `# requirements for MOFED packages` \
        libnl-3-200 libnl-route-3-200 libnl-3-dev libnl-route-3-dev \
        `# requirements for mpicc` \
        zlib1g-dev \
  ; fi \
 && apt-get install -y --no-install-recommends \
      `# build utilities` \
      curl locales \
      `# NUMA support` \
      libnuma1 libnuma-dev numactl \
      `# requirements for Legion rust profiler` \
      pkg-config libssl-dev \
      `# programming/debugging utilities` \
      gdb vim \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Generate locales for 'en_US.UTF-8', required for 'readline' to work
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
 && locale-gen

# Install extra Nvidia packages
RUN export LINUX_VER_URL="$(echo "$LINUX_VER" | tr -d '.')" \
 && curl -fsSL https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/amd64/nvidia.pub | apt-key add - \
 && echo "deb https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/amd64/ /" >> /etc/apt/sources.list.d/nsys.list
RUN apt-get update \
 && apt-get install -y --no-install-recommends nsight-systems-cli \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy quickstart scripts to image (don't copy the entire directory; that would
# include the library repo checkouts, that we want to place elsewhere)
COPY build.sh common.sh /opt/legate/quickstart/

# Install Verbs, RDMA-CM, OpenMPI from MOFED
RUN if [[ "$NETWORK" != none ]]; then \
      export MOFED_ID=MLNX_OFED_LINUX-${MOFED_VER}-${LINUX_VER}-x86_64 \
 &&   cd /tmp \
 &&   curl -fsSL http://content.mellanox.com/ofed/MLNX_OFED-${MOFED_VER}/${MOFED_ID}.tgz | tar -xz \
 &&   cd ${MOFED_ID} \
 &&   dpkg -i $(echo $(find . -false \
        -or -name 'ibverbs-providers*.deb' \
        -or -name 'libibverbs*.deb' \
        -or -name 'librdmacm*.deb' \
        -or -name 'openmpi_*.deb')) \
 &&   cd /tmp \
 &&   rm -rf ${MOFED_ID} \
 &&   echo ${MOFED_VER} > /opt/mofed-ver \
  ; fi

# Copy executables to /usr/bin
# BCP wants mpirun to be in a well-known location at container boot
RUN for APP in mpicc mpicxx mpif90 mpirun; do \
      ln -s /usr/mpi/gcc/openmpi-*/bin/"$APP" /usr/bin/"$APP" \
  ; done
# useful scripts
COPY entrypoint.sh ibdev2netdev print_backtraces.sh /usr/bin/

# Make sure libraries can find the MOFED libmpi at runtime
RUN mkdir -p /usr/mpi/gcc/openmpi \
 && ln -s /usr/mpi/gcc/openmpi-*/lib /usr/mpi/gcc/openmpi/lib
ENV LD_LIBRARY_PATH=/usr/mpi/gcc/openmpi/lib:${LD_LIBRARY_PATH}

# Install UCX
# We do this even when we're not using UCX directly, because Legate needs to
# initialize MPI when running on multiple nodes (regardless of networking
# backend), and recent versions of OpenMPI require UCX.
RUN if [[ "$NETWORK" != none ]]; then \
      export UCX_VER=1.14.1 \
 &&   export UCX_RELEASE=1.14.1 \
 &&   cd /tmp \
 &&   curl -fsSL https://github.com/openucx/ucx/releases/download/v${UCX_RELEASE}/ucx-${UCX_VER}.tar.gz | tar -xz \
 &&   cd ucx-${UCX_VER} \
 &&   ./contrib/configure-release --enable-mt --with-cuda=/usr/local/cuda --with-java=no \
 &&   make -j install \
 &&   cd /tmp \
 &&   rm -rf ucx-${UCX_VER} \
  ; fi

# Install conda
ENV PATH=/opt/conda/bin:${PATH}
RUN cd /tmp \
 && curl -fsSLO https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Linux-x86_64.sh \
 && /bin/bash Mambaforge-Linux-x86_64.sh -b -p /opt/conda \
 && conda update --all --yes \
 && conda clean --all --yes \
 && rm Mambaforge-Linux-x86_64.sh

# Create conda environment
COPY legate.core /opt/legate/legate.core
RUN export TMP_DIR="$(mktemp -d)" \
 && export CUDA_VER_SHORT="$(expr "$CUDA_VER" : '\([0-9][0-9]*\.[0-9][0-9]*\)')" \
 && export YML_FILE="$TMP_DIR"/environment-test-linux-py${PYTHON_VER}-cuda${CUDA_VER_SHORT}.yaml \
 && cd "$TMP_DIR" \
 && /opt/legate/legate.core/scripts/generate-conda-envs.py --python ${PYTHON_VER} --ctk ${CUDA_VER_SHORT} --os linux --no-compilers --no-openmpi --no-ucx \
 && mamba env create -n legate -f "$YML_FILE" \
 && rm -rf "$TMP_DIR"

# Some conda libraries have recently started pulling ucx (namely libarrow).
# Remove that if present, to guarantee that our custom UCX buid is used instead.
# Also remove rdma-core, so we build against the system Inifinband libs.
RUN source activate legate \
 && if (( $(conda list ^ucx$ | wc -l) >= 4 )); then \
      conda remove --offline --force ucx \
  ; fi \
 && if (( $(conda list ^rdma-core$ | wc -l) >= 4 )); then \
      conda remove --offline --force rdma-core \
  ; fi

# Copy the legion directory, if it exists. We have to do it in this weird way
# because COPY <src-dir> doesn't copy <src-dir> itself, only its contents, and
# a COPY with a glob that results in 0 source files will fail.
COPY build.sh legio[n] /opt/legate/legion/
RUN rm /opt/legate/legion/build.sh \
 && if [[ "$(ls -A /opt/legate/legion/)" == "" ]]; then rmdir /opt/legate/legion; fi

# Build GASNet, Legion and legate.core
RUN source activate legate \
 && export CUDA_PATH=/usr/local/cuda/lib64/stubs `# some conda packages, notably cupy, override CUDA_PATH` \
 && if [[ -e /opt/legate/legion/ ]]; then export LEGION_DIR=/opt/legate/legion; fi \
 && cd /opt/legate/legate.core \
 && bash -x /opt/legate/quickstart/build.sh --editable

# Build cunumeric
COPY cunumeric /opt/legate/cunumeric
RUN source activate legate \
 && export CUDA_PATH=/usr/local/cuda/lib64/stubs `# some conda packages, notably cupy, override CUDA_PATH` \
 && cd /opt/legate/cunumeric \
 && bash -x /opt/legate/quickstart/build.sh --editable

# Set up run environment
ENTRYPOINT [ "entrypoint.sh" ]
CMD [ "/bin/bash" ]
RUN echo "source /opt/conda/etc/profile.d/conda.sh" >> /root/.bashrc
RUN echo "conda activate legate" >> /root/.bashrc
ENV LD_LIBRARY_PATH="/opt/conda/envs/legate/lib:${LD_LIBRARY_PATH}"
