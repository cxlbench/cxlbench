#!/usr/bin/env bash 

# This script will run a series of Intel(R) MLC peak bandwidth tests
# using DRAM and CXL memory expansion. The aim is to show by adding
# CXL devices into a system, we can achieve higher memory bandwidth
# per core than with DRAM alone.

#################################################################################################
# Global Variables
#################################################################################################

VERSION="0.1.0"					# version string

SCRIPT_NAME=${0##*/}				# Name of this script
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null; )"	# Provides the full directory name of the script no matter where it is being called from

OUTPUT_PATH="./${SCRIPT_NAME}.`hostname`.`date +"%m%d-%H%M"`" # output directory created by this script
STDOUT_LOG_FILE="${SCRIPT_NAME}.log"			# Filename to save STDOUT and STDERR

NDCTL=("$(command -v ndctl)")                   # Path to ndctl, use -n option to specify location of the ndctl binary
DAXCTL=("$(command -v daxctl)")                 # Path to daxctl
IPMCTL=("$(command -v ipmctl)")                 # Path to ipmctl, use -i option to specify the location of the ipmctl binary
CXLCLI=("$(command -v cxl)")			# Path to cxl, use -c option to specify the location of the cxl binary
BC=("$(command -v bc)")				# Path to bc
NUMACTL=("$(command -v numactl)")		# Path to numactl
LSCPU=("$(command -v lscpu)")                   # Path to lscpu
AWK=("$(command -v awk)")                       # Path to awk
GREP=("$(command -v grep)")			# Path to grep
EGREP=("$(command -v egrep)")			# Path to egrep
SED=("$(command -v sed)")			# Path to sed
TPUT=("$(command -v tput)")			# Path to tput
CP=("$(command -v cp)")				# Path to cp
FIND=("$(command -v find)")                     # Path to find
TEE=("$(command -v tee)")                       # Path to tee
TAIL=("$(command -v tail)")                     # Path to tail

BUF_SZ=40000					# MLC Buffer Size

#################################################################################################
# Helper Functions
#################################################################################################

# Handle Ctrl-C User Input
trap ctrl_c INT
function ctrl_c() {
  echo "INFO: Received CTRL+C - aborting"
  display_end_info
  popd &> /dev/null
  exit 1
}

# Display test start information
function display_start_info() {
  START_TIME=$(date +%s)
  echo "======================================================================="
  echo "Starting ${SCRIPT_NAME}"
  echo "${SCRIPT_NAME} Version ${VERSION}"
  echo "Started: $(date --date @${START_TIME})"
  echo "======================================================================="
}

# Display test end information
function display_end_info() {
  END_TIME=$(date +%s)
  TEST_DURATION=$((${END_TIME}-${START_TIME}))
  echo "======================================================================="
  echo "${SCRIPT_NAME} Completed"
  echo "Ended: $(date --date @${END_TIME})"
  echo "Duration: ${TEST_DURATION} seconds"
  echo "Results: ${OUTPUT_PATH}"
  echo "Logfile: ${LOG_FILE}"
  echo "======================================================================="
}

# Create output directory
function init_outputs() {
   rm -rf $OUTPUT_PATH 2> /dev/null
   mkdir $OUTPUT_PATH
}

# Save STDOUT and STDERR to a log file
# arg1 = path to log file. If empty, save to current directory
function log_stdout_stderr {
  local LOG_PATH
  if [[ $1 != "" ]]; then
    # Use the specified path
    LOG_PATH=${1}
  else
    # Use current working directory
    LOG_PATH=$(pwd)
  fi
  LOG_FILE="${LOG_PATH}/${STDOUT_LOG_FILE}"
  # Capture STDOUT and STDERR to a log file, and display to the terminal
  if [[ ${TEE} != "" ]]; then
    # Use the tee approach
    exec &> >(${TEE} -a "${LOG_FILE}")
  else
    # Use the tail approach
    exec &> "${LOG_FILE}" && ${TAIL} "${LOG_FILE}"
  fi
}

function peak_bandwidth_sweep(){
  echo ""
  echo -n "Finding the peak memory bandwidth for each core count and read:write pattern. This might take a while, please be patient."
}


#################################################################################################
# Main 
#################################################################################################

# Initialize the data collection directory
init_outputs

# Save STDOUT and STDERR logs to the data collection directory
log_stdout_stderr "${OUTPUT_PATH}"

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Display the header information
display_start_info

# Confirm the system has at least two NUMA nodes. Exit if we find only one(1)
NumOfNUMANodes=$(lscpu | grep "NUMA node(s)" | awk -F: '{print $2}' | xargs)
if [[ "${NumOfNUMANodes}" -lt 2 ]]
then
  echo "Only one NUMA Node found. A minumum of two(2) NUMA Nodes is required. Exiting!"
  exit 1
fi
echo "INFO: Number of NUMA Node(s): ${NumOfNUMANodes}"

# Get the number of CPU Sockets within the platform
NumOfSockets=$(lscpu | grep "Socket(s)" | awk -F: '{print $2}' | xargs)
echo "INFO: Number of Physcial Sockets: ${NumOfSockets}"

# Get the number of cores per CPU Socke within the platform
NumOfCoresPerSocket=$(lscpu | grep "Core(s) per socket:" | awk -F: '{print $2}' | xargs)
echo "INFO: Number of Cores per Socke: ${NumOfCoresPerSocket}"

# Get the first vCPU on each socket
declare -a first_vcpu_on_socket

for ((s=0; s<=$((NumOfSockets-1)); s++))
do
  first_vcpu=$(cat /sys/devices/system/node/node${s}/cpulist | cut -f1 -d"-")
  if [ -z "${first_vcpu}" ]; then
    echo "ERROR: Cannot determine the first vCPU on socket ${s}. Exiting."
    #exit 1
  fi
  first_vcpu_on_socket[${s}]=${first_vcpu}
  echo "First CPU on Socket ${s}: ${first_vcpu}"
done

# Confirm if Hyperthreading is Enabled or Disabled
SMTStatus=$(cat /sys/devices/system/cpu/smt/active)
if [[ ${SMTStatus} -eq 0 ]]
then
  echo "INFO: Hyperthreading is DISABLED"
  IncCPU=1
else
  echo "INFO: Hyperthreading is ENABLED"
  IncCPU=2
fi

# Create the MLC Loaded Latency input file if needed
if [[ ! -f mlc_injection.delay ]]
then
  echo "Creating 'mlc_injection.delay'"
  echo 0 > mlc_injection.delay
fi

# Output CSV file headings
OutputCSVHeadings="Node,DRAM:CXL Ratio,Num of Cores,IO Pattern,Access Pattern,Latency(ns),Bandwidth(MB/s)"

# Collect DRAM only stats for Socket 0 (local memory)
# DRAM:CXL ratio is zero (0)
ratio=0
echo "=== Collecting Local DRAM stats for Socket 0 ==="
for (( c=0; c<=${NumOfCoresPerSocket}-1; c=c+${IncCPU} ))
do
  # Build the input file
  for rdwr in R
  # for rdwr in R W2 W5 
  do
    # Random bandwidth option is supported only for R, W2, W5 and W6 traffic types
    for access in seq rand
      do
        echo "0-${c} ${rdwr} ${access} ${BUF_SZ} dram 0" > mlc_loaded_latency.input
        #numactl --membind=0 mlc/mlc --peak_injection_bandwidth -k1-${c}
        mlc/mlc --loaded_latency -gmlc_injection.delay -omlc_loaded_latency.input
	# Save the results to a CSV file
	# Print headings to the CSV file on first access
	if [[ ${c} -eq 0 ]]
	then
	  echo ${OutputCSVHeadings} > "${OUTPUT_PATH}/results.${rdwr}.${access}.${ratio}.csv"
	fi
	# Extract the Latency and Bandwidth results from the log file
	LatencyResult=$(tail -n 4 "${LOG_FILE}" | grep '00000' | awk '{print $2}')
	BandwidthResult=$(tail -n 4 "${LOG_FILE}" | grep '00000' | awk '{print $3}')
	echo "DRAM-Only,100:0,${c},${rdwr},${access},${LatencyResult},${BandwidthResult}" >> "${OUTPUT_PATH}/results.${rdwr}.${access}.${ratio}.csv"
      done
  done
done

# Collect DRAM + CXL Interleaved workloads
echo "=== Collecting Local DRAM stats for Socket 0 ==="
for (( c=0; c<=${NumOfCoresPerSocket}-1; c=c+${IncCPU} ))
do
  # Build the input file
  # File format:
  # CPU RdWr Access Buf_Sz Node0 Node 1 Ratio
  # 0-2 W21 seq 40000 dram 0 dram 1 25
  #
  # W21 : 100% reads (similar to –R)
  # W23 : 3 reads and 1 write (similar to –W3)
  # W27 : 2 reads and 1 non-temporal write (similar to –W7)
  for rdwr in W21 W23 W27 
  do
    # Random bandwidth option is supported only for R, W2, W5 and W6 traffic types
    for access in seq 
    do
      for ratio in 10 25 50
      do 
        # Ratio 50 is only supported by W21
	if [[ ("${rdwr}" == "W23" || "${rdwr}" == "W27") && ${ratio} -eq 50 ]]
        then
          continue
	fi

	# Print headings to the CSV file on first access
        if [[ ${c} -eq 0 ]]
        then
          echo ${OutputCSVHeadings} > "${OUTPUT_PATH}/results.${rdwr}.${access}.${ratio}.csv"
        fi

	# Generate the input file for MLC
        echo "0-${c} ${rdwr} ${access} ${BUF_SZ} dram 0 dram 1 ${ratio}" > mlc_loaded_latency.input

	# Run MLC
        mlc/mlc --loaded_latency -gmlc_injection.delay -omlc_loaded_latency.input

	# Extract the Latency and Bandwidth results
	LatencyResult=$(tail -n 4 "${LOG_FILE}" | grep '00000' | awk '{print $2}')
        BandwidthResult=$(tail -n 4 "${LOG_FILE}" | grep '00000' | awk '{print $3}')
        echo "DRAM+CXL,${ratio},${c},${rdwr},${access},${LatencyResult},${BandwidthResult}" >> "${OUTPUT_PATH}/results.${rdwr}.${access}.${ratio}.csv"
      done 
    done
  done
done

# Zip the output directory
# TODO

# Display the end header information
display_end_info

