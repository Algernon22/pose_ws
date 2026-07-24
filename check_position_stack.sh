#!/usr/bin/env bash

set -euo pipefail

WS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSE_SETUP="$WS_DIR/devel/setup.bash"
LIVOX_WS="${LIVOX_WS:-/home/orangepi/livox_ws}"
LIVOX_SETUP="$LIVOX_WS/devel/setup.bash"
REFRESH_SEC="${REFRESH_SEC:-15}"
HZ_DURATION_SEC="${HZ_DURATION_SEC:-5}"
TOPIC_TIMEOUT_SEC="${TOPIC_TIMEOUT_SEC:-4}"

if [[ ! -f "$POSE_SETUP" ]]; then
  echo "Missing pose workspace setup: $POSE_SETUP" >&2
  exit 1
fi

if [[ ! -f "$LIVOX_SETUP" ]]; then
  echo "Missing Livox workspace setup: $LIVOX_SETUP" >&2
  exit 1
fi

set +u
source /opt/ros/noetic/setup.bash
source "$POSE_SETUP"
source "$LIVOX_SETUP"
set -u

export ROS_PACKAGE_PATH="$WS_DIR/src:$LIVOX_WS/src:${ROS_PACKAGE_PATH:-}"
export CMAKE_PREFIX_PATH="$WS_DIR/devel:$LIVOX_WS/devel:${CMAKE_PREFIX_PATH:-}"
export LD_LIBRARY_PATH="$WS_DIR/devel/lib:$LIVOX_WS/devel/lib:${LD_LIBRARY_PATH:-}"
if [[ -d "$WS_DIR/devel/lib/python3/dist-packages" ]]; then
  export PYTHONPATH="$WS_DIR/devel/lib/python3/dist-packages:${PYTHONPATH:-}"
fi
if [[ -d "$LIVOX_WS/devel/lib/python3/dist-packages" ]]; then
  export PYTHONPATH="$LIVOX_WS/devel/lib/python3/dist-packages:${PYTHONPATH:-}"
fi

watch_topic_once() {
  local topic="$1"
  local timeout_sec="${2:-$TOPIC_TIMEOUT_SEC}"

  if timeout "$timeout_sec" rostopic echo -n 1 "$topic" >/tmp/position_stack_topic_check 2>/tmp/position_stack_topic_check_err; then
    echo "[OK]   $topic"
  else
    echo "[MISS] $topic"
  fi
}

show_topic_hz() {
  local topic="$1"
  local duration_sec="${2:-$HZ_DURATION_SEC}"

  echo
  echo "---- hz: $topic (${duration_sec}s) ----"
  timeout "$duration_sec" rostopic hz "$topic" || true
}

show_mavros_state_summary() {
  echo
  echo "MAVROS state:"
  timeout "$TOPIC_TIMEOUT_SEC" rostopic echo -n 1 /mavros/state || true
}

show_local_position_summary() {
  echo
  echo "MAVROS local position:"
  timeout "$TOPIC_TIMEOUT_SEC" rostopic echo -n 1 /mavros/local_position/odom || true
}

show_px4_estimator_params_hint() {
  echo
  echo "PX4 estimator checks:"
  echo "  If /Odometry is OK but /mavros/local_position/odom is MISS, check the Odometry -> /mavros/vision_pose/pose bridge."
  echo "  If /mavros/vision_pose/pose is OK but /mavros/local_position/odom is MISS, check PX4 EKF2 external vision fusion params."
  echo "  Typical PX4 params to inspect: EKF2_EV_CTRL, EKF2_HGT_REF, EKF2_AID_MASK on older firmware."
}

while true; do
  clear
  echo "Position stack monitor - $(date '+%F %T')"
  echo
  echo "Topic availability:"
  watch_topic_once /livox/lidar
  watch_topic_once /livox/imu
  watch_topic_once /Odometry
  watch_topic_once /mavros/vision_pose/pose
  watch_topic_once /mavros/local_position/odom
  watch_topic_once /mavros/state

  show_mavros_state_summary
  show_local_position_summary

  show_topic_hz /livox/lidar
  show_topic_hz /livox/imu
  show_topic_hz /Odometry
  show_topic_hz /mavros/vision_pose/pose
  show_topic_hz /mavros/local_position/odom

  show_px4_estimator_params_hint

  echo
  echo "Next refresh in ${REFRESH_SEC}s. Press Ctrl-C to stop this monitor."
  sleep "$REFRESH_SEC"
done
