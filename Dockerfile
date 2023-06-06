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
FROM gpuci/miniforge-cuda:${CUDA_VER}-devel-${LINUX_VER}

# Build arguments
ARG CUDA_VER
ENV CUDA_VER=${CUDA_VER}
ARG DEBUG
ENV DEBUG=${DEBUG}
ARG DEBUG_RELEASE
ENV DEBUG_RELEASE=${DEBUG_RELEASE}
ARG LINUX_VER
ENV LINUX_VER=${LINUX_VER}
ARG NETWORK
ENV NETWORK=${NETWORK}
ARG PLATFORM
ENV PLATFORM=${PLATFORM}
ARG PYTHON_VER
ENV PYTHON_VER=${PYTHON_VER}
ARG USE_SPY
ENV USE_SPY=${USE_SPY}

# Execute RUN commands in strict mode
SHELL [ "/bin/bash", "-eo", "pipefail", "-c" ]

# Add third-party apt repos
RUN export LINUX_VER_URL="$(echo "$LINUX_VER" | tr -d '.')" \
 && curl -fsSL https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/amd64/nvidia.pub | apt-key add - \
 && echo "deb https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/amd64/ /" >> /etc/apt/sources.list.d/nsys.list

# Copy quickstart scripts to image (don't copy the entire directory; that would
# include the library repo checkouts, that we want to place elsewhere)
COPY build.sh common.sh /opt/legate/quickstart/

# Install apt packages
RUN source /opt/legate/quickstart/common.sh \
 && set_build_vars \
 && apt-get update \
 && if [[ "$NETWORK" != none ]]; then \
      apt-get install -y --no-install-recommends \
        `# requirements for MOFED packages` \
        libnl-3-200 libnl-route-3-200 libnl-3-dev libnl-route-3-dev \
        `# requirements for mpicc` \
        zlib1g-dev \
  ; fi \
 && apt-get install -y --no-install-recommends \
      `# useful utilities` \
      nsight-systems-cli numactl gdb vim \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Install Verbs, RDMA-CM, OpenMPI from MOFED
RUN source /opt/legate/quickstart/common.sh \
 && set_build_vars \
 && if [[ "$NETWORK" != none ]]; then \
      set_mofed_vars \
 &&   export MOFED_ID=MLNX_OFED_LINUX-${MOFED_VER}-${LINUX_VER}-x86_64 \
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
COPY entrypoint.sh ibdev2netdev legion/tools/print_backtraces.sh /usr/bin/

# Make sure libraries can find the MOFED libmpi at runtime
RUN mkdir -p /usr/mpi/gcc/openmpi \
 && ln -s /usr/mpi/gcc/openmpi-*/lib /usr/mpi/gcc/openmpi/lib
ENV LD_LIBRARY_PATH=/usr/mpi/gcc/openmpi/lib:${LD_LIBRARY_PATH}

# Install UCX
# We do this even when we're not using UCX directly, because Legate needs to
# initialize MPI when running on multiple nodes (regardless of networking
# backend), and recent versions of OpenMPI require UCX.
RUN source /opt/legate/quickstart/common.sh \
 && set_build_vars \
 && if [[ "$NETWORK" != none ]]; then \
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

# Create conda environment
COPY legate.core /opt/legate/legate.core
RUN export TMP_DIR="$(mktemp -d)" \
 && export YML_FILE="$TMP_DIR"/environment-test-linux-py${PYTHON_VER}-cuda${CUDA_VER}.yaml \
 && cd "$TMP_DIR" \
 && /opt/legate/legate.core/scripts/generate-conda-envs.py --python ${PYTHON_VER} --ctk ${CUDA_VER} --os linux --no-compilers --no-openmpi --no-ucx \
 && conda env create -n legate -f "$YML_FILE" \
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

# Build GASNet, Legion and legate.core
COPY legion /opt/legate/legion
RUN source activate legate \
 && export CUDA_PATH=/usr/local/cuda/lib64/stubs `# some conda packages, notably cupy, override CUDA_PATH` \
 && export LEGION_DIR=/opt/legate/legion \
 && cd /opt/legate/legate.core \
 && bash -x /opt/legate/quickstart/build.sh

# Build cunumeric
COPY cunumeric /opt/legate/cunumeric
RUN source activate legate \
 && export CUDA_PATH=/usr/local/cuda/lib64/stubs `# some conda packages, notably cupy, override CUDA_PATH` \
 && cd /opt/legate/cunumeric \
 && bash -x /opt/legate/quickstart/build.sh

# Set up run environment
ENTRYPOINT [ "entrypoint.sh" ]
CMD [ "/bin/bash" ]
RUN echo "conda activate legate" >> /root/.bashrc
ENV LD_LIBRARY_PATH="/opt/conda/envs/legate/lib:${LD_LIBRARY_PATH}"
