# Benchmark launch for RESPLE2: the RESPLE2 and Mapping nodes of the author's
# launch files (e.g. resple_hopper_int.launch.py), with the parameter file as a
# launch argument and without RViz (the benchmark script starts RViz in its
# own pane).
#
# The ROS clock is left as is (use_sim_time false, as upstream): RESPLE2 stamps
# its odometry with times taken from the input messages.

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    default_config_file = os.path.join(
        get_package_share_directory('resple2'), 'config', 'config_hopper_int.yaml')
    config_file = LaunchConfiguration('config_file')

    return LaunchDescription([
        DeclareLaunchArgument('config_file', default_value=default_config_file,
                              description='RESPLE2 parameter file'),
        Node(
            package='resple2',
            executable='RESPLE2',
            name='RESPLE2',
            emulate_tty=True,
            output='screen',
            parameters=[config_file],
            arguments=['--ros-args', '--log-level', 'warn'],
        ),
        Node(
            package='resple2',
            executable='Mapping',
            name='Mapping',
            emulate_tty=True,
            output='both',
            parameters=[config_file],
            arguments=['--ros-args', '--log-level', 'warn'],
        ),
    ])
