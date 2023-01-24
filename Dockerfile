ARG ROS_DISTRO=humble

FROM ros:${ROS_DISTRO}-ros-core

# Use FastRTPS as ROS pub/sub messaging subsystem ("middleware") implementation.
# https://docs.ros.org/en/foxy/How-To-Guides/Working-with-multiple-RMW-implementations.html#specifying-rmw-implementations
# (an alternative value could be "rmw_cyclonedds_cpp".)
ENV RMW_IMPLEMENTATION=rmw_fastrtps_cpp

# Configuration for FastRTPS. don't put it in root or workdir of an app because if ENV points to it
# and it's in app's workdir, it'll get read twice and errors happen.
COPY DEFAULT_FASTRTPS_PROFILES.xml /etc/
ENV FASTRTPS_DEFAULT_PROFILES_FILE=/etc/DEFAULT_FASTRTPS_PROFILES.xml

# so we can download our own-produced components
# Packages with PKCS#11 features have fog-sw-sros component.
RUN FOG_DEB_REPO="https://ssrc.jfrog.io/artifactory/ssrc-deb-public-local" \
	&& echo "deb [trusted=yes] ${FOG_DEB_REPO} $(lsb_release -cs) fog-sw" > /etc/apt/sources.list.d/fogsw.list \
	&& echo "deb [trusted=yes] ${FOG_DEB_REPO} $(lsb_release -cs) fog-sw-sros" >> /etc/apt/sources.list.d/fogsw-sros.list

# fog-health is used by concrete applications as a container HEALTHCHECK to derive health status from
# Prometheus metrics. currently installing from S3 bucket because I failed to setup download from private repo's releases.
ADD https://s3.amazonaws.com/files.function61.com/random-drops/2023/fog-health_linux-amd64 /usr/bin/fog-health

# be careful about introducing dependencies here that already come from ros-core, because adding
# them again here means updating them to latest version, which might not be what we want?
#
# FastRTPS pinned because our SSRC repo had newer version which was incompatible with our current applications.
# WARNING: the same pinning happens in Dockerfile.builder, please update that if you change this!
# TODO: remove pinning once it's no longer required
RUN chmod +x /usr/bin/fog-health && apt update && apt install -y \
	ros-${ROS_DISTRO}-geodesy \
	ros-${ROS_DISTRO}-tf2-ros \
	# Packages with PKCS#11 feature
	ros-${ROS_DISTRO}-fastcdr=1.0.26-40~git20221212.6184f25 \
	ros-${ROS_DISTRO}-fastrtps=2.9.0-40~git20230110.df2857a \
	ros-${ROS_DISTRO}-fastrtps-cmake-module=2.2.0-40~git20220330.89b19c1 \
	ros-${ROS_DISTRO}-foonathan-memory-vendor=1.2.2-40~git20221212.2ef9fc0 \
	ros-${ROS_DISTRO}-rmw-fastrtps-cpp=6.2.2-40~git20221108.8932659 \
	ros-${ROS_DISTRO}-rmw-fastrtps-dynamic-cpp=6.2.2-40~git20221108.8932659 \
	ros-${ROS_DISTRO}-rmw-fastrtps-shared-cpp=6.2.2-40~git20221108.8932659 \
	ros-${ROS_DISTRO}-rosidl-typesupport-fastrtps-c=2.2.0-40~git20220330.89b19c1 \
	ros-${ROS_DISTRO}-rosidl-typesupport-fastrtps-cpp=2.2.0-40~git20220330.89b19c1 \
	# ros-${ROS_DISTRO}-fog-msgs=0.0.8-42~git20220104.1d2cf3f \
	ros-${ROS_DISTRO}-px4-msgs=4.0.0-40~git20230102.9000489 \
	ros-${ROS_DISTRO}-fognav-msgs=1.0.0-3~git20221229.664b19d \
	&& rm -rf /var/lib/apt/lists/*

# wrapper used to launch ros with proper environment variables
COPY ros-with-env.sh /usr/bin/ros-with-env

# Install pkcs11-proxy client library
RUN apt-get update && \
	apt-get install -y --no-install-recommends \
        libengine-pkcs11-openssl \
        libp11-dev \
        pkcs11-proxy1 && \
	rm -rf /var/lib/apt/lists/*

SHELL [ "/bin/bash", "-c" ]

ENV BASH_ENV="/opt/ros/$ROS_DISTRO/setup.bash"
RUN echo "source /opt/ros/$ROS_DISTRO/setup.bash" >> /etc/bash.bashrc
