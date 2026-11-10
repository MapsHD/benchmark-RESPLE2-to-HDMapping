## Hint

Please change branch to [Bunker-DVI-Dataset-reg-1](https://github.com/MapsHD/benchmark-RESPLE2-to-HDMapping/tree/Bunker-DVI-Dataset-reg-1) for quick experiment.

## Example Dataset:

Download the dataset from [Bunker DVI Dataset](https://charleshamesse.github.io/bunker-dvi-dataset/)

# benchmark-RESPLE2-to-HDMapping

Runs [RESPLE2](https://github.com/ASIG-X/RESPLE2) in its LiDAR-inertial mode on
a rosbag and converts the output to an
[HDMapping](https://github.com/MapsHD/HDMapping) session.

RESPLE2 (Z. Cao et al., "RESPLE2: Inertial-Informed Recursive Non-Uniform Spline
Estimation for Multi-Sensor Odometry with Global Refinement") estimates a
non-uniform B-spline trajectory recursively. It also supports camera and leg
kinematics; the benchmark uses LiDAR and IMU only.

## Prerequisites

- Docker
- A ROS 2 bag directory, or a ROS 1 bag file (its LiDAR and IMU topics are
  converted to ROS 2 automatically), with a LiDAR topic and a
  `sensor_msgs/Imu` topic. The LiDAR message depends on `lidar_type`:

| `lidar_type` | LiDAR message |
|--------------|---------------|
| `HAP360` | `livox_ros_driver2/msg/CustomMsg` |
| `Mid70Avia` | `livox_ros_driver/msg/CustomMsg` |
| `AviaResple` | `livox_interfaces/msg/CustomMsg` |
| `Ouster`, `Hesai`, `Mid360Boxi`, `Odin` | `sensor_msgs/msg/PointCloud2` |

## Step 1 — Clone with submodules

```bash
git clone https://github.com/MapsHD/benchmark-RESPLE2-to-HDMapping.git --recursive
cd benchmark-RESPLE2-to-HDMapping
```

## Step 2 — Build the Docker image

```bash
docker build -t resple2_humble .
```

This installs:
- Ubuntu 22.04 + ROS 2 Humble, PCL, OpenCV, Ceres, SuiteSparse
- Pinocchio 3.9.0, built from source (RESPLE2's build requires it)
- colcon workspace with `resple2`, its message packages and `resple2_to_hdmapping`

## Step 3 — Run the pipeline

```bash
chmod +x docker_session_run-ros2-resple2.sh
./docker_session_run-ros2-resple2.sh /path/to/input /path/to/output/dir
```

The input is a ROS 2 bag directory or a ROS 1 `.bag` file. With no arguments, a
GUI file selector is used (requires `zenity`).

| Variable | Default | Meaning |
|----------|---------|---------|
| `CONFIG_FILE` | `config_hopper_int.yaml` | RESPLE2 parameter file: a file on the host, or the name of one in RESPLE2's [config/](https://github.com/ASIG-X/RESPLE2/tree/main/resple2/config) folder |
| `ODOM_TOPIC` | `/odometry` | Recorded odometry topic |
| `CLOUD_TOPIC` | `/scan_world` | Recorded scan topic |
| `USE_RVIZ` | `1` | RViz live view |
| `PLAY_RATE` | `1.0` | `ros2 bag play` rate |

To use your own sensor, copy a parameter file, set its topics, `lidar_type`,
`acc_ratio` (`true` if the accelerometer is in g) and extrinsics, keep
`if_visual` and `if_kin` at `false`, and pass it:

```bash
CONFIG_FILE=/path/to/my_sensor.yaml \
  ./docker_session_run-ros2-resple2.sh /path/to/input /path/to/output/dir
```

Before anything starts, the script checks that the parameter file's topics are
in the bag with a type RESPLE2 reads for that `lidar_type`, and that the camera
and leg kinematics modes are off.

**What happens:**

The script opens a Docker container with a tmux session containing five panes on
window 0 and a `control` window (window 1, the attach target):

| Pane | Role |
|------|------|
| 0 | `ros2 launch resple2 resple2_bench.launch.py` — the RESPLE2 and Mapping nodes |
| 1 | `ros2 bag record /odometry /scan_world` |
| 2 | `ros2 bag play` — plays the LiDAR and IMU topics of your bag |
| 3 | RViz live view |
| 4 | diagnostics — shows active topics and publishing rates |

When playback finishes, the control window stops the recorder, kills all nodes
and RViz, and exits tmux. A second Docker run then converts the recorded bag
into the HDMapping session format.

## Step 4 — Open in HDMapping

Output files appear in `<output_dir>/output_hdmapping-resple2/`:

```
lio_initial_poses.reg
poses.reg
scan_lio_0.laz
...
session.json
trajectory_lio_0.csv
...
```

Open `session.json` with the
[multi_view_tls_registration_step_2](https://github.com/MapsHD/HDMapping)
application.

## Notes on RESPLE2

The benchmark records:

| Topic | Type | Meaning |
|-------|------|---------|
| `/odometry` | `nav_msgs/Odometry` | the `body` pose in the `world` frame |
| `/scan_world` | `sensor_msgs/PointCloud2` | the points of each estimator update in the `world` frame |

The RViz view is based on RESPLE2's own `config.rviz`, keeping the displays that
get data in LiDAR-inertial mode and adding the Time panel, see
[overlay/rviz/resple2_bench.rviz](overlay/rviz/resple2_bench.rviz).

**Timestamps:** the benchmark does not change RESPLE2's clock (no
`use_sim_time`). `/odometry` is stamped with times taken from the input
messages, i.e. bag time. RESPLE2 publishes `/scan_world` without a timestamp, so
the converter gives each cloud the stamp of the `/odometry` message received
closest to it. That time only groups the clouds and poses into the session's
chunks; the points are already in the `world` frame.

## Contact

januszbedkowski@gmail.com
