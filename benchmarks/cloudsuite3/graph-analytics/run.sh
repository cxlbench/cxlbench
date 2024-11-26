#!/bin/bash

set -e

if [[ -f ./setup_env.sh ]]; then
	source ./setup_env.sh
fi

CPUSETS_CPU_NODE=""
CPUSETS_CPU=""
CPUSETS_MEM=""
DMEM="--driver-memory 64g"
EMEM="--executor-memory 64g"
CONTAINER="cxlbench-graph-analytics"
PRIVILEGED=""
RESULTS="results.txt"
NOTE="Default settings"
MEMMAX=""
MAXSWAP=""

function display_help {
	echo "Usage: $0 [options]"
	echo "Options:"
	echo "  -h             : Display this help message."
	echo "  -p             : Set in-container numactl mempolicy"
	echo "  -c  <integer>  : CPU NUMA node to bind to"
	echo "  -m  <int,...>  : Memory NUMA nodes to allow"
	echo "  -w  <string>   : Container name. Default: cxlbench-graph-analytics"
	echo "  -d  <integer>  : Set the driver memory. Default:64g"
	echo "  -e  <integer>  : Set the executor memory. Default:64g"
	echo "  -o  <string>   : Output file to concatenate results to"
	echo "  -n  <string>   : Optional note placed in second field of result"
	echo "  -a  <0,1,2>    : Enable autonuma mode <1,2>"
	echo "  -z  <0,1>      : Enable autonuma-demotion"
	echo "  -t  <integer>  : Tier up <int>MB of data into Node 0"
	echo "  -x  <int>g     : max memory usage"
	echo "  -s  <int>g     : max memory+swap usage"
	exit 0
}

while getopts "hp:c:m:w:d:e:p:o:n:a:z:t:s:x:" opt; do
	case ${opt} in
		h)
			display_help
			;;
		p)
			PRIVILEGED="--privileged --env NUMA_ARG=$OPTARG"
			;;
		c)
			if [[ $OPTARG =~ ^[0-9]+$ ]]; then
				CPUSETS_CPU_NODE=$OPTARG
				CPUSETS_CPU="--cpuset-cpus="$(lscpu -p=CPU,NODE | awk -F, '$2 == '$OPTARG' && $1 != "#" {print $1}' | paste -sd ",")
			else
				echo "Error: -c option requires an integer argument."
				exit 1
			fi
			;;
		m)
			if [[ $OPTARG =~ ^[0-9]+(,[0-9]+)*$ ]]; then
				CPUSETS_MEM="--cpuset-mems="$OPTARG
			else
				echo "Error: -m option requires integer arguments separated by commas."
				exit 1
			fi
			;;
		w)
			CONTAINER=$OPTARG
			;;
		d)
			if [[ $OPTARG =~ ^[0-9]+$ ]]; then
				DMEM="--driver-memory "$OPTARG"g"
			else
				echo "Error: -c option requires an integer argument."
				exit 1
			fi
			;;
		e)
			if [[ $OPTARG =~ ^[0-9]+$ ]]; then
				EMEM="--executor-memory "$OPTARG"g"
			else
				echo "Error: -c option requires an integer argument."
				exit 1
			fi
			;;
		o)
			RESULTS=$OPTARG
			;;
		n)
			NOTE=$OPTARG
			;;
		a)
			if [[ $OPTARG =~ ^[0-2]$ ]]; then
				AUTONUMA_RESTORE=`cat /proc/sys/kernel/numa_balancing`
				echo $OPTARG | sudo tee /proc/sys/kernel/numa_balancing
			else
				echo "Error: -a requires a 0,1,or 2."
				exit 1
			fi
			;;
		z)
			if [[ $OPTARG =~ ^[0-1]$ ]]; then
				AUTONUMA_DEMOTE_RESTORE=`cat /sys/kernel/mm/numa/demotion_enabled`
				echo $OPTARG | sudo tee /sys/kernel/mm/numa/demotion_enabled
			else
				echo "Error: -z requires a 0 or 1."
				exit 1
			fi
			;;
		t)
			if [[ $OPTARG =~ ^[0-9]+$ ]]; then
				start_tiering $OPTARG
				TIERING_ENABLED="true"
			else
				echo "Error: -c option requires an integer argument."
				exit 1
			fi
			;;
		s)
			MAXSWAP="--memory-swap=$OPTARG"
			;;
		x)
			MAXMEM="--memory=$OPTARG"
			;;
		\?)
			echo "Invalid Option: -$OPTARG" 
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument."
			exit 1
			;;
	esac
done

rm -rf results
mkdir -p results

docker create --name graph-data cloudsuite3/twitter-dataset-graph

start_time=$(date +%s%N)
docker run $PRIVILEGED $MAXMEM $MAXSWAP --ulimit nofile=90000:90000 $CPUSETS_CPU $CPUSETS_MEM --rm --volumes-from graph-data $CONTAINER $DMEM $EMEM > results/raw_results.txt
end_time=$(date +%s%N)
time_taken=$(echo "scale=9; ($end_time - $start_time)/1000000000" | bc)

docker rm graph-data

echo "graph-analytics,\"$NOTE\",$time_taken," `grep "Running time" results/raw_results.txt | sed 's/Running time = //'` >> $RESULTS

if [[ -v TIERING_ENABLED ]]; then
	stop_tiering
fi

if [[ -v AUTONUMA_DEMOTE_RESTORE ]]; then
	echo $AUTONUMA_DEMOTE_RESTORE | sudo tee /sys/kernel/mm/numa/demotion_enabled
fi

if [[ -v AUTONUMA_RESTORE ]]; then
	echo $AUTONUMA_RESTORE | sudo tee /proc/sys/kernel/numa_balancing
fi

echo "completed test"
sleep 1
