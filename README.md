# pose_ws 使用说明

`pose_ws` 是当前机载定位工作区，负责启动 Livox MID360、FAST-LIO 和 FAST-LIO 到 MAVROS 的外部视觉桥接。它通常给 `ego-planner-swarm` 提供两类输入：

- `/Odometry`：FAST-LIO 输出的位姿/里程计。
- `/cloud_registered`：FAST-LIO 输出的世界系点云。

当前工作区包含：

- `src/FAST_LIO-main`：FAST-LIO 主程序，包名 `fast_lio`。
- `src/lio_to_mavros`：把 FAST-LIO `/Odometry` 转成 MAVROS 外部视觉输入。
- `start_fast_lio_mid360.sh`：一键启动 roscore、MAVROS、Livox driver、FAST-LIO、lio_to_mavros。
- `check_position_stack.sh`：循环检查定位链路 topic 是否正常。

## 1. 系统依赖

推荐环境：

- Ubuntu 20.04
- ROS Noetic
- Livox MID360
- PX4 + MAVROS

安装 ROS 和常用编译依赖：

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake git \
  libeigen3-dev libpcl-dev libopencv-dev libboost-all-dev \
  libomp-dev python3-dev python3-matplotlib \
  ros-noetic-desktop-full \
  ros-noetic-pcl-ros ros-noetic-pcl-conversions \
  ros-noetic-eigen-conversions \
  ros-noetic-mavros ros-noetic-mavros-extras \
  ros-noetic-tf ros-noetic-rviz
```

如果系统里还没有安装 MAVROS，也可以单独执行：

```bash
sudo apt update
sudo apt install ros-noetic-mavros ros-noetic-mavros-extras
```

MAVROS 需要 GeographicLib 数据。网络可用时：

```bash
sudo /opt/ros/noetic/lib/mavros/install_geographiclib_datasets.sh
```

如果官方脚本下载失败，可以使用离线数据仓库：

```bash
cd $HOME
git clone https://gitee.com/Algernon22/geographic-lib.git
sudo mkdir -p /usr/share/GeographicLib
sudo cp -r geographic-lib/GeographicLib/* /usr/share/GeographicLib/
```

校验：

```bash
test -f /usr/share/GeographicLib/geoids/egm96-5.pgm && echo "geoids ok"
test -f /usr/share/GeographicLib/gravity/egm96.egm && echo "gravity ok"
test -f /usr/share/GeographicLib/magnetic/emm2015.wmm && echo "magnetic ok"
```

## 2. 安装 Livox SDK2 和 ROS 驱动

先安装 Livox-SDK2：

```bash
cd $HOME
git clone https://gitee.com/greymaner/Livox-SDK2.git
cd Livox-SDK2
mkdir -p build
cd build
cmake ..
make -j
sudo make install
```

再安装 `livox_ros_driver2` 到独立工作区 `/home/orangepi/livox_ws`：

```bash
cd $HOME
mkdir -p livox_ws/src
cd livox_ws/src
git clone https://gitee.com/greymaner/livox_ros_driver2.git
cd livox_ros_driver2
./build.sh ROS1
```

安装完成后检查：

```bash
source /opt/ros/noetic/setup.bash
source /home/orangepi/livox_ws/devel/setup.bash
rospack find livox_ros_driver2
roslaunch /home/orangepi/livox_ws/src/livox_ros_driver2/launch_ROS1/msg_MID360.launch --ros-args
```

`msg_MID360.launch` 默认发布：

- `/livox/lidar`
- `/livox/imu`

FAST-LIO 的 `mid360.yaml` 默认正是订阅这两个 topic。

## 3. 编译 pose_ws

```bash
cd /home/orangepi/pose_ws
source /opt/ros/noetic/setup.bash
catkin_make -DCMAKE_BUILD_TYPE=Release
source devel/setup.bash
```

检查包：

```bash
rospack find fast_lio
rospack find lio_to_mavros
```

预期可执行文件：

```text
devel/lib/fast_lio/fastlio_mapping
devel/lib/lio_to_mavros/lio_to_mavros_node
```

## 4. 一键启动 MID360 + FAST-LIO + MAVROS

常用启动方式：

```bash
cd /home/orangepi/pose_ws
./start_fast_lio_mid360.sh
```

脚本会执行：

1. 检查 `/home/orangepi/pose_ws/devel/setup.bash`。
2. 检查 `/home/orangepi/livox_ws/devel/setup.bash`。
3. 启动或复用 `roscore`。
4. 默认启动 MAVROS。
5. 启动 Livox MID360 driver。
6. 等待 `/livox/lidar` 和 `/livox/imu`。
7. 启动 FAST-LIO `mapping_mid360.launch`。
8. 启动 `lio_to_mavros`，把 `/Odometry` 发布到 `/mavros/vision_pose/pose`。

常用环境变量：

```bash
FCU_URL=/dev/ttyACM0:921600 TGT_SYSTEM=1 ./start_fast_lio_mid360.sh
```

只测试 Livox + FAST-LIO，不连接飞控：

```bash
START_MAVROS=false ./start_fast_lio_mid360.sh
```

如果 `livox_ws` 不在默认路径：

```bash
LIVOX_WS=/path/to/livox_ws ./start_fast_lio_mid360.sh
```

增加等待传感器时间：

```bash
SENSOR_WAIT_TIMEOUT=30 ./start_fast_lio_mid360.sh
```

## 5. 分步启动

调试时可以分终端启动。

终端 1，启动 Livox：

```bash
source /opt/ros/noetic/setup.bash
source /home/orangepi/livox_ws/devel/setup.bash
roslaunch /home/orangepi/livox_ws/src/livox_ros_driver2/launch_ROS1/msg_MID360.launch
```

终端 2，启动 FAST-LIO：

```bash
source /opt/ros/noetic/setup.bash
source /home/orangepi/pose_ws/devel/setup.bash
roslaunch /home/orangepi/pose_ws/src/FAST_LIO-main/launch/mapping_mid360.launch
```

终端 3，启动 MAVROS：

```bash
source /opt/ros/noetic/setup.bash
roslaunch mavros px4.launch fcu_url:=/dev/ttyACM0:921600 tgt_system:=1
```

终端 4，启动 FAST-LIO 到 MAVROS 桥：

```bash
source /opt/ros/noetic/setup.bash
source /home/orangepi/pose_ws/devel/setup.bash
roslaunch lio_to_mavros lio_to_mavros.launch
```

`lio_to_mavros.launch` 参数：

```text
odom_topic        默认 /Odometry
vision_topic      默认 /mavros/vision_pose/pose
odom_out_topic    默认 /mavros/odometry/in
publish_odom      默认 false
use_current_time  默认 true
```

如果 PX4 固件或配置要求使用 `/mavros/odometry/in`，可以打开：

```bash
roslaunch lio_to_mavros lio_to_mavros.launch publish_odom:=true
```

## 6. 输出 topic

Livox driver：

```text
/livox/lidar
/livox/imu
```

FAST-LIO：

```text
/Odometry
/cloud_registered
/path
/tf
```

MAVROS 外部视觉桥：

```text
/mavros/vision_pose/pose
/mavros/odometry/in   仅 publish_odom:=true 时发布
```

PX4/MAVROS 融合后常看：

```text
/mavros/state
/mavros/local_position/odom
```

## 7. 参数调整

MID360 配置文件：

```text
src/FAST_LIO-main/config/mid360.yaml
```

常用参数：

```yaml
common:
  lid_topic: "/livox/lidar"
  imu_topic: "/livox/imu"
  time_sync_en: true
  time_offset_lidar_to_imu: 0.0

preprocess:
  lidar_type: 1
  scan_line: 4
  blind: 0.5

mapping:
  acc_cov: 0.1
  gyr_cov: 0.1
  b_acc_cov: 0.0001
  b_gyr_cov: 0.0001
  fov_degree: 360
  det_range: 100.0
  extrinsic_est_en: false
  extrinsic_T: [ -0.011, -0.02329, 0.04412 ]
  extrinsic_R: [ 1, 0, 0,
                 0, 1, 0,
                 0, 0, 1]
```

调参建议：

- `lid_topic`、`imu_topic` 必须和 Livox driver 实际输出一致。
- `blind` 是近距离盲区，机体附近噪点多时可适当增大。
- `extrinsic_T`、`extrinsic_R` 是雷达到 IMU 的外参，实机固定安装后应使用标定值。
- 外参不准会导致轨迹漂移、姿态抖动或点云重影。
- `time_sync_en` 只在没有可靠外部时间同步时使用；如果已有硬件时间同步，应按 FAST-LIO 标定结果设置。
- `scan_publish_en` 控制点云发布；后端规划需要 `/cloud_registered` 时不要关闭。
- `dense_publish_en` 开启后点云更密，但 CPU 和带宽压力更大。

FAST-LIO launch 中的常用参数：

```xml
<param name="point_filter_num" value="3"/>
<param name="max_iteration" value="3"/>
<param name="filter_size_surf" value="0.3"/>
<param name="filter_size_map" value="0.3"/>
```

方向：

- CPU 压力大：增大 `point_filter_num`、`filter_size_surf`、`filter_size_map`。
- 点云太稀或定位细节不足：减小滤波尺寸，但要注意 CPU。
- 迭代收敛差：可小幅增加 `max_iteration`，但实时性会下降。

## 8. 检查和排错

一键监控定位链路：

```bash
cd /home/orangepi/pose_ws
./check_position_stack.sh
```

手动检查 topic：

```bash
rostopic hz /livox/lidar
rostopic hz /livox/imu
rostopic hz /Odometry
rostopic hz /cloud_registered
rostopic hz /mavros/vision_pose/pose
rostopic echo -n 1 /mavros/state
rostopic echo -n 1 /mavros/local_position/odom
```

检查 launch 参数：

```bash
roslaunch /home/orangepi/pose_ws/src/FAST_LIO-main/launch/mapping_mid360.launch --ros-args
roslaunch lio_to_mavros lio_to_mavros.launch --ros-args
roslaunch /home/orangepi/livox_ws/src/livox_ros_driver2/launch_ROS1/msg_MID360.launch --ros-args
```

常见问题：

- 找不到 `livox_ros_driver2`：确认已编译 `/home/orangepi/livox_ws`，并 source 了 `devel/setup.bash`。
- `/livox/lidar` 或 `/livox/imu` 没有数据：检查 MID360 供电、网口/IP、防火墙、Livox 配置文件。
- FAST-LIO 没有 `/Odometry`：先确认 `/livox/lidar` 和 `/livox/imu` 均有频率，再看 `mapping_mid360.launch` 输出。
- `/mavros/vision_pose/pose` 没有数据：检查 `/Odometry` 和 `lio_to_mavros` 是否运行。
- `/mavros/vision_pose/pose` 正常但 `/mavros/local_position/odom` 没有：检查 PX4 EKF2 外部视觉融合参数。
- MAVROS 没有连接：检查 `FCU_URL`、串口权限、波特率、飞控是否上电。

PX4 侧常见参数方向：

```text
EKF2_EV_CTRL / EKF2_HGT_REF / EKF2_AID_MASK
```

不同 PX4 固件版本参数名会有差异，以当前飞控固件为准。

## 9. 与 ego-planner-swarm 联动

`ego-planner-swarm` 默认订阅：

```text
/Odometry
/cloud_registered
```

启动顺序建议：

1. 启动本工作区定位链路：

   ```bash
   cd /home/orangepi/pose_ws
   ./start_fast_lio_mid360.sh
   ```

2. 确认 `/Odometry`、`/cloud_registered` 正常。
3. 启动 `ego-planner-swarm`：

   ```bash
   cd /home/orangepi/ego-planner-swarm
   source /opt/ros/noetic/setup.bash
   source devel/setup.bash
   roslaunch ego_planner onboard_ego_px4.launch
   ```

如果只做规划不接飞控，可以在第一步设置：

```bash
START_MAVROS=false ./start_fast_lio_mid360.sh
```

然后在 `ego-planner-swarm` 中使用：

```bash
roslaunch ego_planner single_run_onboard.launch
```
