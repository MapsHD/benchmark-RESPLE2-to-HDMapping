#!/bin/bash
# Run RESPLE2 in its LiDAR-inertial mode on a rosbag (ROS 2 bag directory or
# ROS 1 .bag), record output topics, then convert the recorded bag to an
# HDMapping session.
#
# RESPLE2 runs as two nodes (RESPLE2 and Mapping) configured by one parameter
# file. The LiDAR and IMU topics come from that file and only those are played.
#
# We record /odometry (world -> body, stamped with the time on the estimated
# spline, i.e. bag time) and /scan_world (the points of each estimator update
# in the world frame). RESPLE2 publishes /scan_world without a timestamp; the
# converter pairs each cloud with the /odometry message received closest to it.
# RESPLE2's clock is left untouched (no use_sim_time).

IMAGE_NAME='resple2_humble'
TMUX_SESSION='ros2_resple2'

DATASET_CONTAINER_PATH='/ros2_ws/dataset/input.bag'
DATASET_ROS2_PATH='/tmp/dataset_ros2'
BAG_OUTPUT_CONTAINER='/ros2_ws/recordings'
CONFIG_MOUNT_CONTAINER='/ros2_ws/config/resple2.yaml'
CONFIG_DIR_CONTAINER='/ros2_ws/install/resple2/share/resple2/config'

RECORDED_BAG_NAME="recorded-resple2"
HDMAPPING_OUT_NAME="output_hdmapping"

# Recorded topics (used by the converter).
ODOM_TOPIC="${ODOM_TOPIC:-/odometry}"
CLOUD_TOPIC="${CLOUD_TOPIC:-/scan_world}"

# RESPLE2 parameter file: a file on the host, or the name of one shipped with
# RESPLE2 in its config/ folder. Default: RESPLE2's own config_hopper_int.yaml
# (LiDAR-inertial, /livox/lidar + /livox/imu).
CONFIG_FILE="${CONFIG_FILE:-config_hopper_int.yaml}"

# RViz on by default — the live view of how RESPLE2 tracks the dataset.
USE_RVIZ="${USE_RVIZ:-1}"

# Force Mesa software rendering by default so RViz renders even when the host
# GPU driver is not exposed to the container (the libGL "nvidia-drm" / amdgpu case).
LIBGL_SW="${LIBGL_SW:-1}"
if [[ "$LIBGL_SW" == "1" ]]; then LIBGL_ENV="1"; else LIBGL_ENV=""; fi

usage() {
  echo "Usage:"
  echo "  $0 <ros2_bag_dir | input.bag> <output_dir>"
  echo
  echo "  ros2_bag_dir : ROS 2 bag directory — played directly, no conversion"
  echo "                 (this is what the HDMapping orchestration passes)"
  echo "  input.bag    : ROS 1 bag file — its LiDAR and IMU topics are converted to ROS 2 first"
  echo
  echo "If no arguments are provided, a GUI file selector will be used."
  echo
  echo "Environment variables:"
  echo "  CONFIG_FILE - RESPLE2 parameter file: a host *.yaml, or the name of one in"
  echo "                RESPLE2's config/ folder     (default: config_hopper_int.yaml)"
  echo "  ODOM_TOPIC  - recorded odometry topic      (default: /odometry)"
  echo "  CLOUD_TOPIC - recorded scan topic          (default: /scan_world)"
  echo "  USE_RVIZ    - 1/0, launch RViz live view   (default: 1)"
  echo "  PLAY_RATE   - ros2 bag play rate           (default: 1.0)"
  exit 1
}

echo "=== RESPLE2 rosbag pipeline ==="

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

if [[ $# -eq 2 ]]; then
  DATASET_HOST_PATH="$1"
  BAG_OUTPUT_HOST="$2"
elif [[ $# -eq 0 ]]; then
  command -v zenity >/dev/null || {
    echo "Error: zenity is not available"
    exit 1
  }
  DATASET_HOST_PATH=$(zenity --file-selection --title="Select BAG file (or ROS 2 bag directory)")
  BAG_OUTPUT_HOST=$(zenity --file-selection --directory --title="Select output directory")
else
  usage
fi

if [[ -z "$DATASET_HOST_PATH" || -z "$BAG_OUTPUT_HOST" ]]; then
  echo "Error: no file or directory selected"
  exit 1
fi

if [[ ! -e "$DATASET_HOST_PATH" ]]; then
  echo "Error: input does not exist: $DATASET_HOST_PATH"
  exit 1
fi

# Parameter file: a host file is mounted into the container; a plain name is
# a file shipped with RESPLE2 (checked inside the container).
CONFIG_MOUNT=()
if [[ -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE=$(realpath "$CONFIG_FILE")
  CONFIG_MOUNT=(-v "$CONFIG_FILE":"$CONFIG_MOUNT_CONTAINER":ro)
  CONFIG_CONTAINER="$CONFIG_MOUNT_CONTAINER"
  CONFIG_DESC="$CONFIG_FILE (host)"
elif [[ "$CONFIG_FILE" != */* ]]; then
  CONFIG_CONTAINER="$CONFIG_DIR_CONTAINER/$CONFIG_FILE"
  CONFIG_DESC="$CONFIG_FILE (RESPLE2 config/)"
else
  echo "Error: CONFIG_FILE does not exist: $CONFIG_FILE"
  exit 1
fi

mkdir -p "$BAG_OUTPUT_HOST"

DATASET_HOST_PATH=$(realpath "$DATASET_HOST_PATH")
BAG_OUTPUT_HOST=$(realpath "$BAG_OUTPUT_HOST")

# Orchestration convention: a directory input is an already-converted ROS 2 bag
# (played directly); a file input is a ROS 1 .bag (converted first).
if [[ -d "$DATASET_HOST_PATH" ]]; then
  INPUT_IS_DIR=1
else
  INPUT_IS_DIR=0
fi

echo "Input           : $DATASET_HOST_PATH ($([[ $INPUT_IS_DIR == 1 ]] && echo 'ROS 2 bag directory' || echo 'ROS 1 bag file, converted to ROS 2'))"
echo "Output dir      : $BAG_OUTPUT_HOST"
echo "Parameter file  : $CONFIG_DESC"
echo "Odom topic      : $ODOM_TOPIC"
echo "Cloud topic     : $CLOUD_TOPIC"

xhost +local:docker >/dev/null

# ── Phase 1: run RESPLE2 + record output topics ──────────────────────────────
docker run -it --rm \
  --network host \
  -e DISPLAY=$DISPLAY \
  -e ROS_HOME=/tmp/.ros \
  -e LIBGL_ALWAYS_SOFTWARE="$LIBGL_ENV" \
  -e USE_RVIZ="$USE_RVIZ" \
  -e CONFIG_CONTAINER="$CONFIG_CONTAINER" \
  -e ODOM_TOPIC="$ODOM_TOPIC" \
  -e CLOUD_TOPIC="$CLOUD_TOPIC" \
  -e INPUT_IS_DIR="$INPUT_IS_DIR" \
  -e PLAY_RATE="${PLAY_RATE:-1.0}" \
  -u 1000:1000 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$DATASET_HOST_PATH":"$DATASET_CONTAINER_PATH":ro \
  -v "$BAG_OUTPUT_HOST":"$BAG_OUTPUT_CONTAINER" \
  "${CONFIG_MOUNT[@]}" \
  "$IMAGE_NAME" \
  /bin/bash -c '

    source /opt/ros/humble/setup.bash
    source /ros2_ws/install/setup.bash

    INPUT_TOPICS=$(python3 /ros2_ws/scripts/resple2_preflight.py --topics "$CONFIG_CONTAINER") || {
      echo "[preflight] ERROR: cannot read the LiDAR and IMU topics from $CONFIG_CONTAINER"; exit 42; }
    export INPUT_TOPICS

    # ── Convert ROS 1 bag to ROS 2 format if needed (LiDAR and IMU only) ─────
    if [[ "$INPUT_IS_DIR" == "1" ]]; then
      echo "[convert] Input is already a ROS 2 bag directory — skipping conversion."
      ROS2_BAG="'"$DATASET_CONTAINER_PATH"'"
    else
      echo "[convert] Converting $INPUT_TOPICS of the ROS 1 bag to ROS 2 format..."
      rm -rf "'"$DATASET_ROS2_PATH"'"
      INCLUDE_ARGS=""
      for t in $INPUT_TOPICS; do INCLUDE_ARGS="$INCLUDE_ARGS --include-topic $t"; done
      rosbags-convert "'"$DATASET_CONTAINER_PATH"'" --dst "'"$DATASET_ROS2_PATH"'" $INCLUDE_ARGS || {
        echo "[convert] ERROR: rosbags-convert failed"; exit 1; }
      ROS2_BAG="'"$DATASET_ROS2_PATH"'"
    fi

    export ROS2_BAG
    echo "[convert] ROS 2 bag ready at: $ROS2_BAG"
    ls -la $ROS2_BAG/

    # ── Preflight: the LiDAR and IMU topics must be in the bag, otherwise ────
    # RESPLE2 processes nothing and the run records no output.
    if ! python3 /ros2_ws/scripts/resple2_preflight.py "$CONFIG_CONTAINER" "$ROS2_BAG"; then
      echo "[preflight] input check failed, nothing is run"
      exit 42
    fi

    # Diagnostic logs, next to the recording. Exported so the shells of the
    # tmux panes inherit it.
    export LOG_DIR='"$BAG_OUTPUT_CONTAINER"'/logs
    mkdir -p "$LOG_DIR"
    rm -f "$LOG_DIR"/*.log
    echo "[setup] diagnostic logs -> $LOG_DIR"

    tmux new-session -d -s '"$TMUX_SESSION"'

    # ---------- PANE 0: RESPLE2 (RESPLE2 + Mapping nodes) ----------
    tmux send-keys -t '"$TMUX_SESSION"' '\''
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
echo "[resple2] launching resple2_bench.launch.py (config=$CONFIG_CONTAINER) ..."
stdbuf -oL -eL ros2 launch resple2 resple2_bench.launch.py config_file:=$CONFIG_CONTAINER 2>&1 | tee "$LOG_DIR"/resple2.log
'\'' C-m

    # ---------- PANE 1: ros2 bag record ----------
    tmux split-window -v -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 2
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
rm -rf '"$BAG_OUTPUT_CONTAINER/$RECORDED_BAG_NAME"'
echo "[record] start"
ros2 bag record $ODOM_TOPIC $CLOUD_TOPIC -o '"$BAG_OUTPUT_CONTAINER/$RECORDED_BAG_NAME"'
echo "[record] exit"
'\'' C-m

    # ---------- PANE 2: ros2 bag play (LiDAR and IMU only) ----------
    tmux split-window -v -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 6
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
echo "[play] start: $INPUT_TOPICS"
ros2 bag play $ROS2_BAG --topics $INPUT_TOPICS --rate ${PLAY_RATE:-1.0}; tmux wait-for -S BAG_DONE;
echo "[play] done"
'\'' C-m

    # ---------- PANE 3: RViz ----------
    # Horizontal from here on: the detached session is 80x24, which has room
    # for at most three vertical splits.
    tmux split-window -h -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 2
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
if [[ "$USE_RVIZ" == "1" ]]; then
  echo "[rviz] launching RViz2..."
  rviz2 -d /ros2_ws/install/resple2/share/resple2/config/resple2_bench.rviz
else
  echo "[rviz] disabled (USE_RVIZ=0)"
fi
'\'' C-m

    # ---------- PANE 4: diagnostics ----------
    tmux split-window -h -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 12
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
(
echo "=== ROS 2 DIAGNOSTICS ==="
echo ""
echo "--- Active topics ---"
ros2 topic list
echo ""
for t in $INPUT_TOPICS $ODOM_TOPIC $CLOUD_TOPIC; do
  echo "--- hz $t ---"
  timeout 5 ros2 topic hz $t 2>&1 | tail -2
done
) 2>&1 | tee "$LOG_DIR"/diag.log
echo ""
echo "[diag] done — you can type ROS 2 commands here, e.g.:"
echo "  ros2 topic echo $ODOM_TOPIC --once"
'\'' C-m

    # ---------- Control window (window 1) ----------
    # This is the window the user attaches to; the noisy panes are on window 0.
    # It waits for the play pane to signal end of playback, then tears the whole
    # session down.
    tmux new-window -t '"$TMUX_SESSION"' -n control '\''
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
echo "[control] waiting for bag playback to finish..."
echo "(logs -> $LOG_DIR/{resple2,diag}.log)"
tmux wait-for BAG_DONE
echo "[control] bag playback finished — shutting down"

# Give RESPLE2 a moment to process remaining queued scans
sleep 3

echo ""
echo "--- resple2.log: last 5 WARN / ERROR lines ---"
grep -E "\[WARN\]|\[ERROR\]" "$LOG_DIR"/resple2.log 2>/dev/null | tail -5
echo ""

# Graceful stop: Ctrl+C to each pane, the recorder first so its bag is closed cleanly
# Pane layout: 0=RESPLE2, 1=recorder, 2=play, 3=rviz, 4=diag
echo "[control] sending Ctrl+C to all panes..."
tmux send-keys -t '"$TMUX_SESSION"':0.1 C-c
sleep 3
tmux send-keys -t '"$TMUX_SESSION"':0.0 C-c
tmux send-keys -t '"$TMUX_SESSION"':0.3 C-c
sleep 3

# Force-kill by process name
echo "[control] force-killing remaining processes..."
pkill -9 RESPLE2          2>/dev/null || true
pkill -9 Mapping          2>/dev/null || true
pkill -9 rviz2            2>/dev/null || true
sleep 1

echo "[control] terminating tmux"
tmux kill-server
'\''

    tmux attach -t '"$TMUX_SESSION"'
  '

# The preflight check failed: nothing was recorded, and converting would pick
# up a stale recording from an earlier run.
if [[ $? -eq 42 ]]; then
  echo "=== ABORTED: input check failed, no conversion ==="
  exit 1
fi

# ── Phase 2: convert recorded bag to HDMapping session ────────────────────────
echo "=== Converting recorded bag to HDMapping session ==="

docker run -it --rm \
  --network host \
  -e ROS_HOME=/tmp/.ros \
  -u 1000:1000 \
  -v "$BAG_OUTPUT_HOST":"$BAG_OUTPUT_CONTAINER" \
  "$IMAGE_NAME" \
  /bin/bash -c "
    set -e
    source /opt/ros/humble/setup.bash
    source /ros2_ws/install/setup.bash
    ros2 run resple2_to_hdmapping listener \
      \"$BAG_OUTPUT_CONTAINER/$RECORDED_BAG_NAME\" \
      \"$BAG_OUTPUT_CONTAINER/$HDMAPPING_OUT_NAME-resple2\" \
      \"$ODOM_TOPIC\" \
      \"$CLOUD_TOPIC\"
  "

echo "=== DONE ==="
