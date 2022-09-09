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
ARG PLATFORM
ENV PLATFORM=${PLATFORM}
ARG PYTHON_VER
ENV PYTHON_VER=${PYTHON_VER}

# Set compile-time & runtime paths
ENV LEGATE_DIR=/opt/legate/install
ENV CUDA_HOME=/usr/local/cuda
# Our activation scripts will append conda dirs to PATH, CPATH and LIBRARY_PATH
# automaticaly on `conda activate`.

# Execute RUN commands in strict mode
SHELL [ "/bin/bash", "-eo", "pipefail", "-c" ]

# Create an alias for the stub libcuda, required when static-linking with UCX libraries
RUN cd ${CUDA_HOME}/lib64/stubs \
 && ln -s libcuda.so libcuda.so.1

# Add third-party apt repos
RUN export LINUX_VER_URL="$(echo "$LINUX_VER" | tr -d '.')" \
 && curl -fsSL https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/amd64/nvidia.pub | apt-key add - \
 && echo "deb https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/amd64/ /" >> /etc/apt/sources.list.d/nsys.list

# Copy quickstart scripts to image (don't copy the entire directory; that would
# include the library repo checkouts, that we want to place elsewhere)
COPY build.sh common.sh entrypoint.sh setup_conda.sh /opt/legate/quickstart/
COPY conda /opt/legate/quickstart/conda

# Install apt packages
RUN source /opt/legate/quickstart/common.sh \
 && set_build_vars \
 && apt-get update \
 && if [[ "$CONDUIT" == ibv || "$CONDUIT" == ucx ]]; then \
    apt-get install -y --no-install-recommends \
    `# requirements for MOFED packages` \
    libnl-3-200 libnl-route-3-200 libnl-3-dev libnl-route-3-dev \
  ; fi \
 && apt-get install -y --no-install-recommends \
    `# requirements for OpenBLAS build` \
    gfortran \
    `# requirements for Legion` \
    zlib1g-dev \
    `# useful utilities` \
    nsight-systems-cli numactl gdb \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Install Verbs, RDMA-CM, OpenMPI from MOFED
RUN source /opt/legate/quickstart/common.sh \
 && set_build_vars \
 && if [[ "$CONDUIT" == ibv || "$CONDUIT" == ucx ]]; then \
    set_mofed_vars \
 && export MOFED_ID=MLNX_OFED_LINUX-${MOFED_VER}-${LINUX_VER}-x86_64 \
 && cd /tmp \
 && curl -fsSL http://content.mellanox.com/ofed/MLNX_OFED-${MOFED_VER}/${MOFED_ID}.tgz | tar -xz \
 && cd ${MOFED_ID} \
 && dpkg -i $(echo $(find . -false \
    -or -name 'ibverbs-providers*.deb' \
    -or -name 'libibverbs*.deb' \
    -or -name 'librdmacm*.deb' \
    -or -name 'openmpi_*.deb')) \
 && cd /tmp \
 && rm -rf ${MOFED_ID} \
 && echo ${MOFED_VER} > /opt/mofed-ver \
  ; fi

# Copy MOFED executables to /usr/bin
RUN for APP in mpicc mpicxx mpif90 mpirun; do \
    ln -s /usr/mpi/gcc/openmpi-*/bin/"$APP" /usr/bin/"$APP" \
  ; done
COPY ibdev2netdev /usr/bin/

# Install UCX
RUN source /opt/legate/quickstart/common.sh \
 && set_build_vars \
 && if [[ "$CONDUIT" == ibv || "$CONDUIT" == ucx ]]; then \
    export UCX_VER=1.13.0 \
 && cd /tmp \
 && curl -fsSL https://github.com/openucx/ucx/releases/download/v${UCX_VER}/ucx-${UCX_VER}.tar.gz | tar -xz \
 && cd ucx-${UCX_VER} \
 && ./contrib/configure-release --enable-mt --with-cuda=${CUDA_HOME} --with-java=no \
 && make -j install \
 && cd /tmp \
 && rm -rf ucx-${UCX_VER} \
  ; fi

# Create conda environment
RUN bash -x /opt/legate/quickstart/setup_conda.sh

# Build GASNet, Legion and legate.core (in no-clean mode, so we don't override
# the Legion checkout)
COPY legate.core /opt/legate/legate.core
RUN source activate legate \
 && cd /opt/legate/legate.core \
 && export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${CUDA_HOME}/lib64/stubs \
 && bash -x /opt/legate/quickstart/build.sh --no-clean

# Build cunumeric
COPY cunumeric /opt/legate/cunumeric
RUN source activate legate \
 && cd /opt/legate/cunumeric \
 && bash -x /opt/legate/quickstart/build.sh

# Create a new user
RUN useradd -rm -d /home/legate-user -s /bin/bash -g root -G sudo -u 1001 legate-user
USER legate-user
WORKDIR /home/legate-user
ENV PATH=${PATH}:/opt/legate/install/bin

# Custom entrypoint script
ENTRYPOINT [ "/opt/legate/quickstart/entrypoint.sh" ]
CMD [ "/bin/bash" ]
