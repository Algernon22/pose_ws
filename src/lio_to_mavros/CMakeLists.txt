cmake_minimum_required(VERSION 3.0.2)
project(lio_to_mavros)

add_compile_options(-std=c++14)

find_package(catkin REQUIRED COMPONENTS
  geometry_msgs
  nav_msgs
  roscpp
)

catkin_package()

include_directories(
  ${catkin_INCLUDE_DIRS}
)

add_executable(lio_to_mavros_node src/lio_to_mavros_node.cpp)
target_link_libraries(lio_to_mavros_node ${catkin_LIBRARIES})

install(TARGETS lio_to_mavros_node
  RUNTIME DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(DIRECTORY launch
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
)
