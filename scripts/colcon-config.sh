#!/bin/bash
set -eo pipefail

# Default build type is Release
ROS_DISTRO="${1:-humble}"
BUILD_TYPE="${2:-Release}"
SIM_MODE="${3:-}"
BUILD_PACKAGES=(unitree_lowlevel)
# Pinocchio compilation is memory intensive; allow an explicit override.
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-2}"
export MAKEFLAGS="${MAKEFLAGS:--j${CMAKE_BUILD_PARALLEL_LEVEL}}"

echo "Building with ROS_DISTRO=$ROS_DISTRO and CMAKE_BUILD_TYPE=$BUILD_TYPE"

# Get project root directory
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../.." &> /dev/null && pwd )"
echo "Project directory: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR/lib" "$PROJECT_DIR/src"

# Clone repos
vcs import "$PROJECT_DIR/lib" < "$PROJECT_DIR/src/unitree_lowlevel/scripts/lib.repos"
vcs import "$PROJECT_DIR/src" < "$PROJECT_DIR/src/unitree_lowlevel/scripts/src.repos"

# Checkout correct ROS distro branches
cd "$PROJECT_DIR/lib/rmw_cyclonedds"
git checkout "$ROS_DISTRO"

# unitree_sdk2
if [ ! -f /opt/unitree_robotics/lib/cmake/unitree_sdk2/unitree_sdk2Config.cmake ]; then
    cd "$PROJECT_DIR/lib/unitree_sdk2"
    cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/unitree_robotics
    cmake --build build --parallel "$CMAKE_BUILD_PARALLEL_LEVEL"
    sudo cmake --install build
fi

if [ "$SIM_MODE" = "sim" ]; then
    vcs import "$PROJECT_DIR/src" < "$PROJECT_DIR/src/unitree_lowlevel/scripts/sim.repos"
    # unitree_mujoco
    echo "=== Downloading Mujoco (Simulation Mode) ==="
    mkdir -p "$HOME/.mujoco"
    cd "$HOME/.mujoco"
    if [ ! -f mujoco-3.3.6/lib/libmujoco.so ]; then
        MUJOCO_ARCHIVE="mujoco-3.3.6-linux-$(uname -m).tar.gz"
        if [ ! -f "$MUJOCO_ARCHIVE" ]; then
            wget "https://github.com/google-deepmind/mujoco/releases/download/3.3.6/$MUJOCO_ARCHIVE"
        fi
        tar -xzf "$MUJOCO_ARCHIVE"
    fi

    echo "=== Building Unitree Mujoco ==="
    cd "$PROJECT_DIR/src/unitree_mujoco/simulate"
    if [ ! -e mujoco ] && [ ! -L mujoco ]; then
        ln -s "$HOME/.mujoco/mujoco-3.3.6" mujoco
    fi
    BUILD_PACKAGES+=(unitree_mujoco)
fi

# Build
cd "$PROJECT_DIR"
source "/opt/ros/$ROS_DISTRO/setup.bash"
colcon build --symlink-install --executor sequential --packages-up-to "${BUILD_PACKAGES[@]}" --cmake-args \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DPython_EXECUTABLE=/usr/bin/python3 \
    -DPython3_EXECUTABLE=/usr/bin/python3
