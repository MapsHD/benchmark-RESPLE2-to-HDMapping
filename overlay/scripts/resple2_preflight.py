#!/usr/bin/env python3
"""Preflight check for the RESPLE2 benchmark run.

RESPLE2 subscribes to the IMU topic and the LiDAR topics named in its parameter
file (topic_imu; lidars: [...], each with topic_lidar and lidar_type). If one of
them is missing from the bag, or has a type RESPLE2 does not read for that
lidar_type, it processes nothing and the run records no output, so the check
stops the run first (exit code 42, the run script then skips the conversion).

The benchmark plays only the LiDAR and IMU topics, so the camera and leg
kinematics modes (if_visual, if_kin) must be off: with one of them on, RESPLE2
waits forever for messages that are never played.

Usage: resple2_preflight.py <parameter_file.yaml> <ros2_bag_dir>
       resple2_preflight.py --topics <parameter_file.yaml>   (prints the input topics)
"""

import os
import sys

import yaml

POINTCLOUD2 = "sensor_msgs/msg/PointCloud2"
IMU = "sensor_msgs/msg/Imu"

# Message read by RESPLE2 for each lidar_type.
LIDAR_MSG = {
    "HAP360": "livox_ros_driver2/msg/CustomMsg",
    "Mid70Avia": "livox_ros_driver/msg/CustomMsg",
    "AviaResple": "livox_interfaces/msg/CustomMsg",
    "Ouster": POINTCLOUD2,
    "Hesai": POINTCLOUD2,
    "Mid360Boxi": POINTCLOUD2,
    "Odin": POINTCLOUD2,
}


def read_config(config_path):
    """Returns (parameters, imu_topic, {lidar_topic: lidar_type})."""
    with open(config_path) as f:
        config = yaml.safe_load(f)
    for value in config.values():
        if isinstance(value, dict) and "ros__parameters" in value:
            params = value["ros__parameters"]
            break
    else:
        raise KeyError("ros__parameters")
    lidars = {params[name]["topic_lidar"]: str(params[name]["lidar_type"]) for name in params["lidars"]}
    return params, params["topic_imu"], lidars


def main():
    if sys.argv[1] == "--topics":
        _, imu_topic, lidars = read_config(sys.argv[2])
        print(" ".join(list(lidars) + [imu_topic]))
        return
    config_path, bag_dir = sys.argv[1:3]
    try:
        params, imu_topic, lidars = read_config(config_path)
    except (OSError, KeyError, TypeError, AttributeError, yaml.YAMLError) as e:
        print(f"[preflight] ERROR: cannot read topic_imu and the lidars from {config_path}: {e}")
        sys.exit(42)
    print(f"[preflight] parameter file: {config_path}")

    active = [mode for mode in ("if_visual", "if_kin") if params.get(mode)]
    if active:
        print(f"[preflight] ERROR: {', '.join(active)} is on in the parameter file. The benchmark plays "
              "only the LiDAR and IMU topics (LiDAR-inertial mode): set if_visual and if_kin to false.")
        sys.exit(42)

    unknown = sorted(set(lidars.values()) - set(LIDAR_MSG))
    if unknown:
        print(f"[preflight] ERROR: unknown lidar_type {', '.join(unknown)} (known: {', '.join(LIDAR_MSG)}).")
        sys.exit(42)

    try:
        with open(os.path.join(bag_dir, "metadata.yaml")) as f:
            info = yaml.safe_load(f)["rosbag2_bagfile_information"]
        topics = {t["topic_metadata"]["name"]: (t["topic_metadata"]["type"], t["message_count"])
                  for t in info["topics_with_message_count"]}
    except (OSError, KeyError, TypeError, yaml.YAMLError) as e:
        print(f"[preflight] ERROR: cannot read the ROS 2 bag metadata in {bag_dir}: {e}")
        sys.exit(42)

    expected = [(topic, LIDAR_MSG[lidar_type]) for topic, lidar_type in lidars.items()] + [(imu_topic, IMU)]
    ok = True
    for name, msg_type in expected:
        found = topics.get(name)
        if found is None or found[0] != msg_type:
            print(f"[preflight] ERROR: {name} must be {msg_type} ({found[0] if found else 'not in the bag'}).")
            ok = False
        else:
            print(f"[preflight] {name}: {found[1]} msgs ({msg_type})")
    if not ok:
        for msg_type in sorted({m for _, m in expected}):
            names = [t for t, (ty, _) in topics.items() if ty == msg_type]
            print(f"[preflight] {msg_type} topics in this bag: {', '.join(names) or '(none)'}")
        print("[preflight] Choose the parameter file of your sensor (CONFIG_FILE) or set "
              "topic_imu, topic_lidar and lidar_type in it.")
        sys.exit(42)


if __name__ == "__main__":
    main()
