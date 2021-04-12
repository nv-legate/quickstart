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

# Parent image
ARG CUDA_VER
ARG LINUX_VER
FROM gpuci/miniconda-cuda:${CUDA_VER}-devel-${LINUX_VER}

# Base build arguments
ARG CUDA_VER
ENV CUDA_VER=${CUDA_VER}
ARG DEBUG
ENV DEBUG=${DEBUG}
ARG LINUX_VER
ENV LINUX_VER=${LINUX_VER}
ARG LINUX_VER_URL
ENV LINUX_VER_URL=${LINUX_VER_URL}
ARG OMPI_VER
ENV OMPI_VER=${OMPI_VER}
ARG OMPI_VER_URL
ENV OMPI_VER_URL=${OMPI_VER_URL}
ARG PLATFORM
ENV PLATFORM=${PLATFORM}
ARG PYTHON_VER
ENV PYTHON_VER=${PYTHON_VER}
ARG INSTALL_ARGS
ENV DOCKER_BUILD=""
ARG GPU_ARCH
ENV GPU_ARCH=${GPU_ARCH}

# Set compile-time & runtime paths
ENV LEGATE_DIR=/opt/legate/install
ENV CUDA_HOME=/usr/local/cuda

# Execute RUN commands in strict mode
SHELL [ "/bin/bash", "-eo", "pipefail", "-c" ]

# Create an alias for the stub libcuda, required when static-linking with UCX libraries
RUN if [[ $PLATFORM != other ]]; then cd ${CUDA_HOME}/lib64/stubs \
 && ln -s libcuda.so libcuda.so.1; fi

# Add third-party apt repos
RUN curl -fsSL https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/amd64/nvidia.pub | apt-key add - \
 && echo "deb https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/amd64/ /" >> /etc/apt/sources.list.d/nsys.list

# Install apt packages
RUN apt-get update \
 && if [[ $PLATFORM != other ]]; then apt-get install -y --no-install-recommends \
    `# requirements for MOFED packages` \
    libnl-3-200 libnl-route-3-200 libnl-3-dev libnl-route-3-dev \
    `# requirements for UCX build` \
    libtool libnuma-dev \
    `# ssh client, required to initialize MPI on single-node NGC runs` \         
    openssh-client; fi \
 && apt-get install -y --no-install-recommends \
    `# useful utilities` \
    nsight-systems-cli numactl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy quickstart to image
COPY quickstart /opt/legate/quickstart

# Install Verbs & RDMA-CM from MOFED
RUN if [[ $PLATFORM != other ]]; then source /opt/legate/quickstart/common.sh \
 && set_mofed_vars \
 && export MOFED_ID=MLNX_OFED_LINUX-${MOFED_VER_LONG}-${LINUX_VER}-x86_64 \
 && cd /tmp \
 && curl -fSsL http://content.mellanox.com/ofed/MLNX_OFED-${MOFED_VER_LONG}/${MOFED_ID}.tgz | tar -xz \
 && cd ${MOFED_ID} \
 && dpkg -i $(echo $(find . -false \
    -or -name ibverbs-providers_${MOFED_DEB_VER}'*.deb' \
    -or -name libibverbs-dev_${MOFED_DEB_VER}'*.deb' \
    -or -name libibverbs1_${MOFED_DEB_VER}'*.deb' \
    -or -name libibverbs1-dbg_${MOFED_DEB_VER}'*.deb' \
    -or -name libmlx5-1_${MOFED_DEB_VER}'*.deb' \
    -or -name libmlx5-1-dbg_${MOFED_DEB_VER}'*.deb' \
    -or -name libmlx5-dev_${MOFED_DEB_VER}'*.deb' \
    -or -name librdmacm-dev_${MOFED_DEB_VER}'*.deb' \
    -or -name librdmacm1_${MOFED_DEB_VER}'*.deb' \
    -or -name librdmacm1-dbg_${MOFED_DEB_VER}'*.deb')) \
 && cd /tmp \
 && rm -rf ${MOFED_ID} \
 && echo ${MOFED_VER} > /opt/mofed-ver \
 && cp /opt/legate/quickstart/ibdev2netdev /usr/bin; fi

# Setup conda environment
RUN export CONDA_ROOT=/opt/conda \
 && /opt/legate/quickstart/setup_conda.sh \
 && source activate legate \
 && conda clean -afy \
 && sed -i 's/conda activate base/conda activate legate/g' ~/.bashrc

# Build UCX with Verbs support
RUN if [[ $PLATFORM != other ]]; then source activate legate \
 && export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${CUDA_HOME}/lib64/stubs \
 && /opt/legate/quickstart/install_ib_ucx.sh; fi

# Build OpenMPI from source, to make sure it matches our version of UCX.
# We also need to make sure MPI binaries and all refeferenced libraries are in
# /usr/local, otherwise the NGC kubernetes launcher won't find them when
# starting the MPI daemon.
RUN if [[ $PLATFORM != other ]]; then source activate legate \
 && export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${CUDA_HOME}/lib64/stubs \
 && cd /tmp \
 && curl -fSsL "https://download.open-mpi.org/release/open-mpi/v${OMPI_VER_URL}/openmpi-${OMPI_VER}.tar.gz" | tar -xz \
 && cd openmpi-${OMPI_VER} \
 && mkdir build \
 && cd build \
 && ../configure \
    --with-verbs \
    --with-cuda=${CUDA_HOME} \
    --with-ucx=${CONDA_PREFIX} \
    --enable-mca-no-build=btl-uct \
    --with-hwloc=internal \
    --with-libevent=internal \
 && make -j install \
 && cd /tmp \
 && rm -rf openmpi-${OMPI_VER} \
 && ldconfig; fi

# Build GASNet, Legion and legate.core
COPY legate.core /opt/legate/legate.core
RUN source activate legate \
 && cd /opt/legate/legate.core \
 && export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${CUDA_HOME}/lib64/stubs \
 && bash -x /opt/legate/quickstart/build.sh ${INSTALL_ARGS}

# Build legate.hello
COPY legate.hello /opt/legate/legate.hello
RUN source activate legate \
 && cd /opt/legate/legate.hello \
 && bash -x /opt/legate/quickstart/build.sh ${INSTALL_ARGS}

# Build legate.pandas
COPY legate.pandas /opt/legate/legate.pandas
RUN source activate legate \
 && cd /opt/legate/legate.pandas \
 && bash -x /opt/legate/quickstart/build.sh ${INSTALL_ARGS}

# Needed for Pandas IO tests
RUN chmod og+w /opt/legate/legate.pandas/tests/io

# Build legate.numpy
COPY legate.numpy /opt/legate/legate.numpy
RUN source activate legate \
 && cd /opt/legate/legate.numpy \
 && /opt/legate/quickstart/build.sh ${INSTALL_ARGS}

RUN useradd -rm -d /home/legate-user -s /bin/bash -g root -G sudo -u 1001 legate-user

USER legate-user

WORKDIR /home/legate-user

ENV PATH=$PATH:/opt/legate/install/bin

# Custom entrypoint script
ENTRYPOINT [ "/opt/legate/quickstart/entrypoint.sh" ]
CMD [ "/bin/bash" ]
