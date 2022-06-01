#!/bin/bash -eux

# runs the builder container, outputting .deb packages at root of this repo.
# package.sh
#   bloom-generate
#   fakeroot debian/rules binary

# (fakeroot wraps debian/rules invocation seeming like it's run as root)

function rosdep_init_update_and_install {
	local mod_dir="$1" # probably /main_ws/src

	## for installing additional non-ROS2 dependencies to debian package generated by bloom
	if [ ! -e /etc/ros/rosdep/sources.list.d/20-default.list ]; then
	        echo "[INFO] Initialize rosdep"
	        sudo rosdep init
	fi

	rosdepYamlPath=/packaging/rosdep.yaml
	if [ -e ${rosdepYamlPath} ]; then
		# assert that we have remembered to update ROS distro in the rosdep.yaml
		# (previously we did this replace dynamically, but this is less magic)
		if ! grep "$ROS_DISTRO" "$rosdepYamlPath" > /dev/null ; then
			echo "[ERROR] $rosdepYamlPath does not mention current ROS distro $ROS_DISTRO"
			exit 1
		fi
		echo "[INFO] Add module specific dependencies"
		cat "$rosdepYamlPath"
		mkdir -p /etc/ros/rosdep/sources.list.d
		echo "yaml file://${rosdepYamlPath}" > /etc/ros/rosdep/sources.list.d/51-fogsw-module.list
	fi

	echo "[INFO] Updating rosdep"
	rosdep update

	apt update
	echo "[INFO] Running rosdep install.."
	# reads package.xml to determine which dependencies to install (with help of apt-get)
	if rosdep install --from-paths "$mod_dir" -r -y --rosdistro ${ROS_DISTRO} 1> /dev/null 2>&1; then
		echo "[INFO] rosdep install finished successfully."
	else
		echo "[ERROR] Some dependencies missing. It will be built using underlay.repos."
	fi
}

function build_underlay_deps {
	local mod_dir="$1" # probably /main_ws/src

	# Extract not satisfied dependencies from output, check if they are exist in ../underlay.repos
	if rosdep check --from-paths "$mod_dir" 1> /dev/null 2>&1; then
		echo "[INFO] Dependencies are satisfied."
		return 0
	fi

	echo "[INFO] Building dependencies using underlay.repos."
	cd "$mod_dir"

    echo "[INFO] Get package dependencies."
    # Dependencies from fog-sw repo
    if [ -e ${mod_dir}/ros2_ws/src ]; then
        echo "[INFO] Use dependencies from fog_sw."
        pushd ${mod_dir}/ros2_ws > /dev/null
        source /opt/ros/${ROS_DISTRO}/setup.bash
    else
        echo "[INFO] Use dependencies from local repository."
        if [ ! -e ${mod_dir}/underlay.repos ]; then
        	echo "[ERROR] assuming ${mod_dir}/underlay.repos is present but it is not."
        	exit 1
        fi
        mkdir -p ${mod_dir}/deps_ws/src
        pushd ${mod_dir}/deps_ws > /dev/null
        vcs import src < ${mod_dir}/underlay.repos
        rosdep install --from-paths src --ignore-src -r -y --rosdistro ${ROS_DISTRO}
        source /opt/ros/${ROS_DISTRO}/setup.bash
    fi

    rosdep_out=$(rosdep check -v --from-paths src 2>&1 | grep "resolving for resources" )
    ALL_PKGS=$(echo $rosdep_out | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | tr -d ' ')
    echo "[INFO] All packages: $(echo $ALL_PKGS|tr '\n' ' ')"
    PKGS_TO_BUILD=""
    pushd src > /dev/null

    for pkg_name in ${ALL_PKGS}; do
        echo "[INFO] Check if package ${pkg_name} is in the list of packages to build."
        pkg_name=$(echo ${pkg_name} | sed 's/\/$//')
        if ! ros2 pkg list | grep ${pkg_name} 1> /dev/null 2>&1; then
            PKGS_TO_BUILD="${PKGS_TO_BUILD} ${pkg_name}"
        fi
    done

    echo "[INFO] Packages to build: $PKGS_TO_BUILD"
    popd > /dev/null

    echo "[INFO] Build package dependencies."
    colcon build --packages-select ${PKGS_TO_BUILD}
    popd > /dev/null
}

# wrapper for invoking another function but outputs log headings about entering
# (and leaving, if in GitHub actions) the said step
function step {
	local fn="$1"

	if [[ -v GITHUB_ACTIONS ]]; then
		# GitHub-specific log magic for grouping log lines
		# https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#grouping-log-lines
		echo "::group::$fn"
	else
		echo "# $fn"
	fi

	# call the actual function, with all given arguments
	"$@"

	if [[ -v GITHUB_ACTIONS ]]; then
		echo "::endgroup::"
	else
		# no output when step ends
		return 0
	fi
}

function build_process {
	step rosdep_init_update_and_install /main_ws/src

	rosdep update

	if [[ ! -v SKIP_BUILD_UNDERLAY_STEPS ]]; then
		step build_underlay_deps /main_ws/src
	fi

	if [[ ! -e package.xml ]]; then
		pushd $(dirname $(find -name package.xml))
		/packaging/package.sh
		popd
	else
		/packaging/package.sh
	fi
}

# not being sourced?
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	build_process
fi
