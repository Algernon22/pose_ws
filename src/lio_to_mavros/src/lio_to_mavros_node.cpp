#include <geometry_msgs/PoseStamped.h>
#include <nav_msgs/Odometry.h>
#include <ros/ros.h>

class LioToMavros {
 public:
  LioToMavros() : nh_(), pnh_("~") {
    std::string odom_topic;
    std::string vision_topic;
    std::string odom_out_topic;
    pnh_.param<std::string>("odom_topic", odom_topic, "/Odometry");
    pnh_.param<std::string>("vision_topic", vision_topic, "/mavros/vision_pose/pose");
    pnh_.param<std::string>("odom_out_topic", odom_out_topic, "/mavros/odometry/in");
    pnh_.param<bool>("publish_odom", publish_odom_, false);
    pnh_.param<bool>("use_current_time", use_current_time_, true);

    odom_sub_ = nh_.subscribe(odom_topic, 10, &LioToMavros::odomCallback, this);
    vision_pub_ = nh_.advertise<geometry_msgs::PoseStamped>(vision_topic, 10);

    if (publish_odom_) {
      odom_pub_ = nh_.advertise<nav_msgs::Odometry>(odom_out_topic, 10);
    }

    ROS_INFO_STREAM("lio_to_mavros: " << odom_topic << " -> " << vision_topic
                                      << ", publish_odom=" << std::boolalpha
                                      << publish_odom_);
  }

 private:
  void odomCallback(const nav_msgs::OdometryConstPtr& msg) {
    const ros::Time output_stamp = use_current_time_ ? ros::Time::now() : msg->header.stamp;

    geometry_msgs::PoseStamped vision_pose;
    vision_pose.header = msg->header;
    vision_pose.header.stamp = output_stamp;
    vision_pose.pose = msg->pose.pose;
    vision_pub_.publish(vision_pose);

    if (odom_pub_) {
      nav_msgs::Odometry odom_msg = *msg;
      odom_msg.header.stamp = output_stamp;
      odom_pub_.publish(odom_msg);
    }
  }

  ros::NodeHandle nh_;
  ros::NodeHandle pnh_;
  ros::Subscriber odom_sub_;
  ros::Publisher vision_pub_;
  ros::Publisher odom_pub_;
  bool publish_odom_{false};
  bool use_current_time_{true};
};

int main(int argc, char** argv) {
  ros::init(argc, argv, "lio_to_mavros");
  LioToMavros node;
  ros::spin();
  return 0;
}
