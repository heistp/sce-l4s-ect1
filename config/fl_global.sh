#!/bin/bash

# script location
SCRIPT_DIR='~/src/sce-l4s-ect1'

# batch config
BATCH=ect1
BATCH_FILE=${BATCH}.batch

# output file spec
BATCH_OUT_SPEC="$BATCH-????-??-?????????"

# architectures
ARCHS=(sce l4s)

# management config
MGMT_SSH=

# SCE config
SCE_CLI_SSH=
SCE_CLI_RIGHT=
SCE_MID_SSH=
SCE_MID_LEFT=
SCE_MID_RIGHT=
SCE_SRV_SSH=
SCE_SRV_LEFT=

# L4S config
L4S_CLI_SSH=
L4S_CLI_RIGHT=
L4S_MID_SSH=
L4S_MID_LEFT=
L4S_MID_RIGHT=
L4S_SRV_SSH=
L4S_SRV_LEFT=

# netns config
NS_CLI_RIGHT=
NS_MID_LEFT=
NS_MID_RIGHT=
NS_SRV_LEFT=

# all nodes to clear before each netns test
CLEAR_NODES=(cli mid srv)

# all ssh dests for physical hosts to clear before each phys test
CLEAR_SSH_DESTS=(c1 c2 m1 m2 m3 m4 s1 s2)

# push config
ARCHIVE_DIR=""
ARCHIVE_URL=""
PUSH_SSH_DEST=""

# tc config
TC_DIR="/usr/local/bin"

# Pushover config
PUSHOVER_SOUND_SUCCESS=""
PUSHOVER_SOUND_FAILURE=""
PUSHOVER_USER=""
PUSHOVER_TOKEN=""

# plot colors
# bright
#PLOT_COLORS="\
#	'#1AC938',\
#	'#E8080A',\
#	'#8B2BE2',\
#	'#9F4800',\
#	'#F14CC1',\
#	'#A3A3A3',\
#	"
# dark
#PLOT_COLORS="\
#	'#12711C',\
#	'#8C0800',\
#	'#591E71',\
#	'#592F0E',\
#	'#A23582',\
#	'#3C3C3C',\
#	"

# plot size
PLOT_WIDTH=12
PLOT_HEIGHT=9
#PLOT_WIDTH=9
#PLOT_HEIGHT=7.5

# plot format
PLOT_FORMAT=svg

# compression config
COMPRESS=xz

# browser settings
BROWSER= # set to browser command, if not Linux or Mac

# results directories
RESULTS_URL="http://sce.dnsmgr.net/results"
RESULTS_DIR="ect1-2020-04-23-final"

# harness config
DEBUG=0
TMPDIR="/tmp/sce-l4s-ect1"

# namespaces config
NS_OFFLOADS=off
NS_CLI_IP=10.9.9.1/24
NS_SRV_IP=10.9.9.2/24

# data_dir emits the data directory for a node
data_dir() {
	local node=$1
	# end of params

	echo "$TMPDIR/$node/data"
}

# log_dir emits the log directory for a node
log_dir() {
	local node=$1
	# end of params

	echo "$TMPDIR/$node/log"
}

# arch_tc emits the tc executable name for the architecture
arch_tc() {
	local arch=$1
	# end of params

	echo tc-${arch}
}

# node_ssh emits the ssh destination for a node
node_ssh() {
	local arch=$1
	local node=$2
	# end of params

	local v=${arch^^}_${node^^}_SSH
	if [[ ${!v} ]]; then
		echo ${!v}
	else
		echo "not_defined:$v"
	fi
}

# node_devs emits the node's interfaces for a direction
node_devs() {
	local arch=$1
	local net=$2
	local node=$3
	local dir=$4
	# end of params

	echov() {
		[[ ${!1} ]] && echo ${!1}
	}

	# select prefix from network
	local p
	case $net in
		phys)
			p=${arch^^}
			;;
		ns)
			p="NS"
			;;
		*)
			echo "unknown_net:$net"
			return 1
	esac

	# output based on direction
	local ok=false
	if [[ $dir == "left" ]] || [[ $dir == "bidir" ]]; then
			echov ${p}_${node^^}_LEFT
			ok=true
	fi
	if [[ $dir == "right" ]] || [[ $dir == "bidir" ]]; then
			echov ${p}_${node^^}_RIGHT
			ok=true
	fi

	# check dir value
	if [[ $ok == false ]]; then
		echo "unknown_dir:$dir"
		return 1
	fi
}
