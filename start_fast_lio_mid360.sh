#!/usr/bin/env bash

set -euo pipefail

WS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSE_SETUP="$WS_DIR/devel/setup.bash"
LIVOX_WS="${LIVOX_WS:-/home/orangepi/livox_ws}"
LIVOX_SETUP="$LIVOX_WS/devel/setup.bash"
LIVOX_LAUNCH="$LIVOX_WS/src/livox_ros_driver2/launch_ROS1/msg_MID360.launch"
SENSOR_WAIT_TIMEOUT="${SENSOR_WAIT_TIMEOUT:-15}"
ROS_MASTER_WAIT_TIMEOUT="${ROS_MASTER_WAIT_TIMEOUT:-10}"
MAVROS_CONNECT_TIMEOUT="${MAVROS_CONNECT_TIMEOUT:-20}"
START_MAVROS="${START_MAVROS:-true}"
FCU_URL="${FCU_URL:-/dev/ttyACM0:921600}"
TGT_SYSTEM="${TGT_SYSTEM:-1}"
ROSCORE_PID=""
STARTED_ROSCORE="false"
LIVOX_PID=""
FAST_LIO_PID=""
MAVROS_PID=""
LIO_TO_MAVROS_PID=""

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  if [[ -n "$LIO_TO_MAVROS_PID" ]] && kill -0 "$LIO_TO_MAVROS_PID" 2>/dev/null; then
    kill "$LIO_TO_MAVROS_PID" 2>/dev/null || true
    wait "$LIO_TO_MAVROS_PID" 2>/dev/null || true
  fi
  if [[ -n "$FAST_LIO_PID" ]] && kill -0 "$FAST_LIO_PID" 2>/dev/null; then
    kill "$FAST_LIO_PID" 2>/dev/null || true
    wait "$FAST_LIO_PID" 2>/dev/null || true
  fi
  if [[ -n "$LIVOX_PID" ]] && kill -0 "$LIVOX_PID" 2>/dev/null; then
    kill "$LIVOX_PID" 2>/dev/null || true
    wait "$LIVOX_PID" 2>/dev/null || true
  fi
  if [[ -n "$MAVROS_PID" ]] && kill -0 "$MAVROS_PID" 2>/dev/null; then
    kill "$MAVROS_PID" 2>/dev/null || true
    wait "$MAVROS_PID" 2>/dev/null || true
  fi
  if [[ "$STARTED_ROSCORE" == "true" ]] && [[ -n "$ROSCORE_PID" ]] && kill -0 "$ROSCORE_PID" 2>/dev/null; then
    kill "$ROSCORE_PID" 2>/dev/null || true
    wait "$ROSCORE_PID" 2>/dev/null || true
  fi
  exit "$exit_code"
}

wait_for_ros_master() {
  local deadline=$((SECONDS + ROS_MASTER_WAIT_TIMEOUT))
  while (( SECONDS < deadline )); do
    if rostopic list >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_mavros_connection() {
  local deadline=$((SECONDS + MAVROS_CONNECT_TIMEOUT))
  while (( SECONDS < deadline )); do
    if [[ -n "$MAVROS_PID" ]] && ! kill -0 "$MAVROS_PID" 2>/dev/null; then
      return 1
    fi
    if timeout 2 rostopic echo -n 1 /mavros/state 2>/dev/null | grep -q "connected: True"; then
      echo "MAVROS connected to FCU."
      return 0
    fi
    if timeout 2 rostopic echo -n 1 /mavros/state 2>/dev/null | grep -q "connected: true"; then
      echo "MAVROS connected to FCU."
      return 0
    fi
    sleep 1
  done
  return 1
}

topic_has_publisher() {
  local topic="$1"
  rostopic info "$topic" 2>/dev/null | awk '
    /^Publishers:/ { in_publishers = 1; next }
    /^Subscribers:/ { in_publishers = 0 }
    in_publishers && /^[[:space:]]+\*/ { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

wait_for_topic_publisher() {
  local topic="$1"
  local deadline=$((SECONDS + SENSOR_WAIT_TIMEOUT))
  while (( SECONDS < deadline )); do
    if ! kill -0 "$LIVOX_PID" 2>/dev/null; then
      echo "Livox driver exited before publishing $topic." >&2
      return 1
    fi
    if rostopic list "$topic" >/dev/null 2>&1 && topic_has_publisher "$topic"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

if [[ ! -f "$LIVOX_SETUP" ]]; then
  echo "Missing Livox workspace setup: $LIVOX_SETUP" >&2
  exit 1
fi
if [[ ! -f "$POSE_SETUP" ]]; then
  echo "Missing pose workspace setup: $POSE_SETUP" >&2
  echo "Build it first: cd $WS_DIR && source /opt/ros/noetic/setup.bash && catkin_make" >&2
  exit 1
fi
if [[ ! -f "$LIVOX_LAUNCH" ]]; then
  echo "Missing MID360 driver launch file: $LIVOX_LAUNCH" >&2
  exit 1
fi

set +u
source /opt/ros/noetic/setup.bash
source "$POSE_SETUP"
source "$LIVOX_SETUP"
set -u

# The two workspaces were built independently, so sourcing one setup file can
# hide packages from the other. Keep both package trees visible to roslaunch.
export ROS_PACKAGE_PATH="$WS_DIR/src:$LIVOX_WS/src:${ROS_PACKAGE_PATH:-}"
export CMAKE_PREFIX_PATH="$WS_DIR/devel:$LIVOX_WS/devel:${CMAKE_PREFIX_PATH:-}"
export LD_LIBRARY_PATH="$WS_DIR/devel/lib:$LIVOX_WS/devel/lib:${LD_LIBRARY_PATH:-}"
if [[ -d "$WS_DIR/devel/lib/python3/dist-packages" ]]; then
  export PYTHONPATH="$WS_DIR/devel/lib/python3/dist-packages:${PYTHONPATH:-}"
fi
if [[ -d "$LIVOX_WS/devel/lib/python3/dist-packages" ]]; then
  export PYTHONPATH="$LIVOX_WS/devel/lib/python3/dist-packages:${PYTHONPATH:-}"
fi

trap cleanup EXIT INT TERM

if rostopic list >/dev/null 2>&1; then
  echo "Using existing ROS master."
else
  echo "Starting ROS master..."
  roscore >/tmp/pose_ws_roscore.log 2>&1 &
  ROSCORE_PID=$!
  STARTED_ROSCORE="true"
  if ! wait_for_ros_master; then
    echo "ROS master was not available within ${ROS_MASTER_WAIT_TIMEOUT}s." >&2
    echo "roscore log:" >&2
    tail -n 40 /tmp/pose_ws_roscore.log >&2 || true
    exit 1
  fi
fi

if [[ "$START_MAVROS" == "true" ]]; then
  echo "Starting MAVROS..."
  roslaunch mavros px4.launch fcu_url:="$FCU_URL" tgt_system:="$TGT_SYSTEM" &
  MAVROS_PID=$!
  if ! wait_for_mavros_connection; then
    echo "Warning: MAVROS did not report connected within ${MAVROS_CONNECT_TIMEOUT}s." >&2
    echo "Continuing startup, but PX4 will not enter position mode until MAVROS is connected and EKF2 accepts vision." >&2
  fi
fi

echo "Starting Livox MID360 driver..."
roslaunch "$LIVOX_LAUNCH" &
LIVOX_PID=$!

echo "Waiting for /livox/lidar and /livox/imu..."
if ! wait_for_topic_publisher /livox/lidar || ! wait_for_topic_publisher /livox/imu; then
  echo "Livox topics were not available within ${SENSOR_WAIT_TIMEOUT}s." >&2
  echo "Current ROS topics:" >&2
  rostopic list 2>/dev/null >&2 || true
  exit 1
fi

echo "Starting FAST-LIO MID360 mapping..."
roslaunch "$WS_DIR/src/FAST_LIO-main/launch/mapping_mid360.launch" "$@" &
FAST_LIO_PID=$!
sleep 2

echo "Starting LIO to MAVROS vision bridge..."
roslaunch lio_to_mavros lio_to_mavros.launch &
LIO_TO_MAVROS_PID=$!

wait "$FAST_LIO_PID"
