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
ARG CPU_ARCH
ENV CPU_ARCH=${CPU_ARCH}
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
ARG PYTHON_VER
ENV PYTHON_VER=${PYTHON_VER}
ARG USE_SPY
ENV USE_SPY=${USE_SPY}

# Execute RUN commands in strict mode
SHELL [ "/bin/bash", "-eo", "pipefail", "-c" ]

# Install apt packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      `# build utilities` \
      curl locales \
      `# NUMA support` \
      libnuma1 libnuma-dev numactl \
      `# programming/debugging utilities` \
      gdb vim wget git \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Generate locales for 'en_US.UTF-8', required for 'readline' to work
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
 && locale-gen

# Install extra NVIDIA packages
RUN export LINUX_VER_URL="$(echo "$LINUX_VER" | tr -d '.')" \
 && if [[ "$CPU_ARCH" == "arm" ]]; then export ARCH="arm64"; else export ARCH="amd64"; fi \
 && curl -fsSL https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/${ARCH}/nvidia.pub | apt-key add - \
 && echo "deb https://developer.download.nvidia.com/devtools/repos/${LINUX_VER_URL}/${ARCH}/ /" >> /etc/apt/sources.list.d/nsys.list
RUN apt-get update \
 && apt-get install -y --no-install-recommends nsight-systems-cli \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy quickstart scripts to image (don't copy the entire directory; that would
# include the library repo checkouts, that we want to place elsewhere)
COPY build.sh common.sh /opt/legate/quickstart/

# Install conda
ENV PATH=/opt/conda/bin:${PATH}
RUN cd /tmp \
 && if [[ "$CPU_ARCH" == "arm" ]]; then export ARCH="aarch64"; else export ARCH="x86_64"; fi \
 && curl -fsSLO https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Linux-${ARCH}.sh \
 && /bin/bash Mambaforge-Linux-${ARCH}.sh -b -p /opt/conda \
 && conda update --all --yes \
 && conda clean --all --yes \
 && rm Mambaforge-Linux-${ARCH}.sh

# Create conda environment
COPY legate.core /opt/legate/legate.core
RUN export TMP_DIR="$(mktemp -d)" \
 && export YML_FILE="$TMP_DIR"/environment-test-linux-py${PYTHON_VER}-cuda${CUDA_VER}-openmpi-ucx.yaml \
 && cd "$TMP_DIR" \
 && /opt/legate/legate.core/scripts/generate-conda-envs.py --python ${PYTHON_VER} --ctk ${CUDA_VER} --os linux --ucx --openmpi \
 && mamba env create -n legate -f "$YML_FILE" \
 && rm -rf "$TMP_DIR"

# Copy executables to /usr/bin
# BCP wants mpirun to be in a well-known location at container boot
RUN source activate legate \
 && ln -s "$CONDA_PREFIX"/bin/mpirun /usr/bin/mpirun
# useful scripts
COPY entrypoint.sh ibdev2netdev print_backtraces.sh /usr/bin/

# Make sure libraries can find libmpi at runtime
ENV LD_LIBRARY_PATH="$CONDA_PREFIX/lib:${LD_LIBRARY_PATH}"

# For Linux 64, conda OpenMPI is built with CUDA awareness but
# this support is disabled by default. UCX support is also built
# but disabled by default.
# Set OMPI_MCA_opal_cuda_support=true to enable CUDA awareness.
# Set OMPI_MCA_pml=ucx and OMPI_MCA_osc=ucx to enable UCX.
ENV OMPI_MCA_opal_cuda_support=true
ENV OMPI_MCA_pml=ucx
ENV OMPI_MCA_osc=ucx

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
 && USE_CUDA=1 USE_OPENMP=1 /opt/legate/quickstart/build.sh --editable

# Build Tblis for ARM, needs patching for ARM architecture:
COPY tblis_diff /opt/legate/
RUN if [[ "$CPU_ARCH" == "arm" ]]; then \
      export TMP_DIR="$(mktemp -d)" \
 &&   cd "$TMP_DIR" \
 &&   git clone --recursive --branch master https://github.com/devinamatthews/tblis.git \
 &&   cd tblis \
 &&   git apply /opt/legate/tblis_diff \
 &&   ./configure --enable-thread-model=openmp --with-label-type=int32_t --with-length-type=int64_t --with-stride-type=int64_t --prefix=/opt/legate/tblis_build \
 &&   make -j \
 &&   make install \
 &&   rm -rf "$TMP_DIR" \
  ; fi

# Build cunumeric
COPY cunumeric /opt/legate/cunumeric
RUN source activate legate \
 && export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/legate/tblis_build/lib \
 && export CUDA_PATH=/usr/local/cuda/lib64/stubs `# some conda packages, notably cupy, override CUDA_PATH` \
 && cd /opt/legate/cunumeric \
 && if [[ "$CPU_ARCH" == "arm" ]]; then \
      /opt/legate/quickstart/build.sh --editable --with-tblis /opt/legate/tblis_build \
  ; else \
      /opt/legate/quickstart/build.sh --editable \
  ; fi
ENV LD_LIBRARY_PATH="/opt/legate/tblis_build/lib:${LD_LIBRARY_PATH}"

# Set up run environment
ENTRYPOINT [ "entrypoint.sh" ]
CMD [ "/bin/bash" ]
RUN echo "source /opt/conda/etc/profile.d/conda.sh" >> /root/.bashrc
RUN echo "conda activate legate" >> /root/.bashrc
