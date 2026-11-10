FROM ubuntu:22.04

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# ── Base tools ────────────────────────────────────────────────────────────────
# Libraries follow RESPLE2's README; liburdfdom-dev and the Boost filesystem,
# serialization and system libraries are for Pinocchio.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg2 \
    lsb-release \
    software-properties-common \
    build-essential \
    cmake \
    git \
    ca-certificates \
    wget \
    pkg-config \
    libeigen3-dev \
    libpcl-dev \
    libopencv-dev \
    libyaml-cpp-dev \
    libboost-thread-dev \
    libboost-filesystem-dev \
    libboost-serialization-dev \
    libboost-system-dev \
    libsuitesparse-dev \
    libceres-dev \
    liburdfdom-dev \
    nlohmann-json3-dev \
    tmux \
    python3-pip \
    python3-yaml \
    && rm -rf /var/lib/apt/lists/*

# ── ROS 2 Humble ─────────────────────────────────────────────────────────────
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
    http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/ros2.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-desktop \
    ros-humble-pcl-conversions \
    ros-humble-cv-bridge \
    ros-humble-image-transport \
    ros-humble-rosidl-default-generators \
    ros-humble-rosidl-generator-dds-idl \
    ros-humble-ament-lint-auto \
    ros-humble-ament-lint-common \
    ros-humble-rosbag2-cpp \
    ros-humble-rosbag2-storage-default-plugins \
    python3-colcon-common-extensions \
    && rm -rf /var/lib/apt/lists/*

# ── rosbags (used to convert ROS 1 bags to ROS 2, if needed) ─────────────────
RUN pip3 install --no-cache-dir "rosbags==0.9.22"

# ── Pinocchio 3.9.0 ──────────────────────────────────────────────────────────
# The version RESPLE2's README asks for; its CMakeLists requires it and looks
# in /usr/local/lib/cmake/pinocchio.
RUN git clone --branch v3.9.0 --depth 1 --recursive \
    https://github.com/stack-of-tasks/pinocchio.git /tmp/pinocchio && \
    cmake -S /tmp/pinocchio -B /tmp/pinocchio/build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DBUILD_PYTHON_INTERFACE=OFF \
      -DBUILD_TESTING=OFF \
      -DBUILD_BENCHMARK=OFF \
      -DBUILD_UTILS=OFF && \
    cmake --build /tmp/pinocchio/build -j4 && \
    cmake --install /tmp/pinocchio/build && \
    ldconfig && \
    test -f /usr/local/lib/cmake/pinocchio/pinocchioConfig.cmake && \
    rm -rf /tmp/pinocchio

# ── Build colcon workspace (RESPLE2 + its message packages, converter) ───────
WORKDIR /ros2_ws

COPY ./src/RESPLE2               ./src/RESPLE2
COPY ./src/resple2-to-hdmapping  ./src/resple2-to-hdmapping

# Benchmark launch file and RViz view added into the resple2 package; preflight
# check used by the run script.
COPY ./overlay/launch/  ./src/RESPLE2/resple2/launch/
COPY ./overlay/rviz/    ./src/RESPLE2/resple2/config/
COPY ./overlay/scripts/ /ros2_ws/scripts/

# The final guard fails the image build loudly if an executable is missing.
RUN source /opt/ros/humble/setup.bash && \
    colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF && \
    test -f /ros2_ws/install/resple2/lib/resple2/RESPLE2 && \
    test -f /ros2_ws/install/resple2/lib/resple2/Mapping && \
    test -f /ros2_ws/install/resple2/share/resple2/launch/resple2_bench.launch.py && \
    test -f /ros2_ws/install/resple2/share/resple2/config/resple2_bench.rviz && \
    test -f /ros2_ws/install/resple2_to_hdmapping/lib/resple2_to_hdmapping/listener && \
    echo "[build] RESPLE2, Mapping, bench launch, RViz view and converter present"

# ── Non-root user ─────────────────────────────────────────────────────────────
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID ros && \
    useradd -m -u $UID -g $GID -s /bin/bash ros && \
    chown -R $UID:$GID /ros2_ws

RUN echo "source /opt/ros/humble/setup.bash"   >> /root/.bashrc && \
    echo "source /ros2_ws/install/setup.bash"  >> /root/.bashrc && \
    echo "source /opt/ros/humble/setup.bash"   >> /home/ros/.bashrc && \
    echo "source /ros2_ws/install/setup.bash"  >> /home/ros/.bashrc

CMD ["bash"]
