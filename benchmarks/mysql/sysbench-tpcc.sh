#!/bin/bash
# set -x
#
# This script uses podman to start N mysql and N sysbench container instances in a 1:1 relationship
# The containers run on a dedicated virtual network to simplify hostname referencing
# Each MySQL container will run on a dedicated host port, starting at 3306 and increasing
# by one for each new instance.
# Each sysbench container will run TPC-C benchmarks against a single MySQL
# database instance.
# The goal of this script is to show multi-instance performance as we start
# more DB instances.

source ../../lib/common     # Provides common functions
source ../../lib/msgfmt     # Provides pretty print messages to STDOUT

SCRIPT_DIR=$( dirname $( readlink -f $0 ))

#################################################################################################
# Variables
#################################################################################################

# ==== Podman Variables ====

# Podman network name
NETWORK_NAME=mysqlsysbench

# Container CPU and memory limits for the MySQL server and the Sysbench client
# Note: The MySQL (server) values should be configured for the size of the test database. The OOM killer will stop the database if too few resources are assigned.
CLIENT_CPU_LIMIT=4              # Number of vCPUs to give to the Sysbench container
CLIENT_MEMORY_LIMIT=1g          # Amount of memory (GiB) to give to the Sysbench container
SERVER_CPU_LIMIT=4              # Number of vCPUs to give to the MySQL container
SERVER_MEMORY_LIMIT=16g         # Amount of memory (GiB) to give to the Sysbench container

# === MySQL Variables ===

MYSQL_ROOT_PASSWORD=my-secret-pw                        # Root Users Password
MYSQL_START_PORT=3333                                   # Host Port number for the first instance. Additional instances will increment by 1 for each instance 3306..3307..3308..    
MYSQL_DATA_DIR=/data                                    # Base directory for the MySQL Data Directory on the host
MYSQL_CONF=${SCRIPT_DIR}/my.cnf.d/my.cnf                # Location of the my.cnf file(s)
MySQLDockerImgTag="docker.io/library/mysql:latest"      # MySQL Version. Get the Docker Tag ID from https://hub.docker.com/_/mysql


# === Sysbench Variables ===

# Sysbench username and password
SYSBENCH_USER="sbuser"
SYSBENCH_USER_PASSWORD="sbuser-pwd" 
SCALE=1                                     # Default number of warehouses (scale value)
TABLES=10                                   # Default number of tables per warehouse. Use -t to override.
SYSBENCH_CONTAINER_IMG_NAME="sysbenchmysql" # Sysbench container image name
SysbenchDBName="sbtest"                     # Name of the MySQL Database to create and run Sysbench against
# Sysbench options
SYSBENCH_OPTS_TEMPLATE="--db-driver=mysql --mysql-db=${SysbenchDBName} --mysql-user=${SYSBENCH_USER} --mysql-password=${SYSBENCH_USER_PASSWORD} --mysql-host=mysqlINSTANCE --mysql-port=3306 --time=RUNTIME  --threads=THREADS --tables=TABLES --scale=SCALE"

#################################################################################################
# Functions
#################################################################################################

# Implementing 'goto' functionality
# Usage: goto end
# Labels/Tags are '# end: #', or '#end:#' or '# end: # This is a comment'
function goto() {
  label=$1
  cmd=$(sed -En "/^[[:space:]]*#[[:space:]]*$label:[[:space:]]*#/{:a;n;p;ba};" "$0")
  eval "$cmd"
  exit
}

function init() {
    # Create the output directory
    init_outputs                    
}

# Verify the required commands and utilities exist on the system
# We use either the defaults or user specified paths
# args: none
# return: 0=success, 1=error
function verify_cmds() {
    local err_state=false

    for CMD in numactl lscpu lspci grep cut sed awk podman; do
        CMD_PATH=($(command -v ${CMD}))
        if [ ! -x "${CMD_PATH}" ]; then
            error_msg "${CMD} command not found! Please install the ${CMD} package."
            err_state=true
        fi
    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Displays the script help information
function print_usage()
{
    echo -e "${SCRIPT_NAME}: Usage"
    echo "    ${SCRIPT_NAME} [-o output_prefix] [-p] [-r]"
    echo "      -c                         : Cleanup. Completely remove all containers and the MySQL database"
    echo "      -C <numa_node>             : [Required] CPU NUMA Node to run the MySQLServer"
    #echo "      -e dram|tier|interleave|mm : [Required] Type of experiment to run"
    echo "      -e dram|interleave         : [Required] Type of experiment to run"
    echo "      -i <number_of_instances>   : The number of container intances to execute: Default 1"
    echo "      -r                         : Run the Sysbench workload"
    echo "      -p                         : Prepare the database"
    echo "      -M <numa_node,..>          : [Required] Memory NUMA Node to run the MySQLServer"
    echo "      -o <prefix>                : [Required] prefix of the output files"
    echo "      -s <scale>                 : Set the database scale value: Default 1"
    echo "      -S <numa_node>             : [Required] NUMA Node to run the Sysbench clients"
    echo "      -t <number_of_tables>      : The number of tables to use: Default 10"
    echo "      -w                         : Warm the database"
    echo "      -h                         : Print this message"
    echo " "
    echo "Example 1: Runs a single MySQL server on NUMA 0 and a single SysBench instance on NUMA Node1, prepares the database, runs the benchmark, and removes the database when complete."
    echo " "
    echo "    $ ./${SCRIPT_NAME} -c -C 0 -e dram -i 1 -r -p -M 0 -o test -S1 -t 10 -w"
    echo " "
}

# Creates a spinner animation to show the script is working in the background
# args: none
# return: none
function spin() {
    local -a marks=( '/' '-' '\' '|' )
    local -a pids=("$@")

    while [[ true ]]; do
        printf '%s\r' "${marks[i++ % ${#marks[@]}]}"
        sleep 0.1
        for pid in "${pids[@]}"; do
            if ! kill -0 "$pid" 2> /dev/null; then
                return
            fi
        done
    done
}

# Use the MySQL data directory to find the underlying phsycial disk(s) or LVM volumes
# dstat will collect information specifically for that device/those devices
# args: none
# return: 0=success, 1=error
function dstat_find_location_of_db()
{
    DATADISK=$( df ${MYSQL_DATA_DIR} | grep -v Filesystem | cut -d ' ' -f 1 | sed -e 's/\/dev\///' )

    if [ -z "${DATADISK}" ]; then
        error_msg "The data disk for '${MYSQL_DATA_DIR}' could not be found."
        return 1
    else 
        return 0
    fi
}   

# From the Experiment (-e) argument, determine what numactl options to use
# args: none
# return: none
function set_numactl_options()
{
    case "$EXPERIMENT" in
        tier|mm|dram)
            NUMACTL_OPTION="--cpunodebind ${MYSQL_CPU_NUMA_NODE} --membind ${MYSQL_MEM_NUMA_NODE}"
        ;;
        interleave)
            NUMACTL_OPTION="--cpunodebind ${MYSQL_CPU_NUMA_NODE} --interleave ${MYSQL_MEM_NUMA_NODE}"
        ;;
    esac
}

# Create the podman network
# args: none
# return: 0=success, 1=error
function create_network()
{
    if ! podman network exists ${NETWORK_NAME}; then
        info_msg echo "Creating a new Podman network called '${NETWORK_NAME}'."
        # podman network create ${NETWORK_NAME}
        if podman network create "${NETWORK_NAME}"; then
            info_msg "Network ${NETWORK_NAME} created successfully"
            return 0
        else
            error_msg "Error creating network ${NETWORK_NAME}"
            return 1
        fi
    else
        info_msg "Network ${NETWORK_NAME} already exists"
        return 0
   fi
}

# Create a custom sysbench + mysql-client container image using a multi stage Dockerfile
# We must compile sysbench from source code to get the '--warmup' option. 
# The release builds do not support the warmup feature.
# args: none
# return: 0=success, 1=error
function create_sysbench_container_image()
{
    local pids
    local spin_pid
    local err_state=false

    info_msg "Start Creating Sysbench Containers"
    if ! podman image exists $SYSBENCH_CONTAINER_IMG_NAME; then
        info_msg "Image '$SYSBENCH_CONTAINER_IMG_NAME' does not exist."
        info_msg "Creating Sysbench Dockerfile..."
        cat > Dockerfile.sysbenchlua <<EOF
# Stage 1: Build Sysbench from source
FROM ubuntu:22.04 AS builder

# Install necessary build dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    make \
    cmake \
    automake \
    libmysqlclient-dev \
    libmysqlclient21 \
    libssl-dev \
    libaio-dev \
    libpq-dev \
    libtool \
    pkg-config

# Clone Sysbench source code
RUN git clone https://github.com/akopytov/sysbench.git

# Build Sysbench
WORKDIR /sysbench
RUN ./autogen.sh && ./configure --prefix=/usr/local && make -j all && make install

# Clone the sysbench-tpcc repository
RUN git clone https://github.com/Percona-Lab/sysbench-tpcc.git

# Copy the *.lua files into /usr/local/share/sysbench
RUN cp sysbench-tpcc/*.lua /usr/local/share/sysbench/

# Make all the */lua files executable
RUN chmod +x /usr/local/share/sysbench/*.lua

# Stage 2: Final image
FROM ubuntu:22.04

# Install necessary packages for Sysbench and Percona Lua scripts
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y \
    mysql-client \
    libmysqlclient21 \
    libc6 \
    libssl3 \
    libaio1 \
    libpq5

# Copy Sysbench binary from the builder stage
COPY --from=builder /usr/local/bin/sysbench /usr/local/bin/sysbench

# Copy Sysbench default LUA scripts from the builder stage
COPY --from=builder /usr/local/share/sysbench/*.lua /usr/local/share/sysbench/

# Make all the */lua files executable
RUN chmod +x /usr/local/share/sysbench/*.lua

# Clean up unnecessary packages
RUN DEBIAN_FRONTEND=noninteractive apt-get autoremove -y && apt-get clean

# Define the entry point or any additional configurations
ENTRYPOINT ["sleep", "infinity"]

# Add label information to the image
LABEL description="This image includes the latest Sysbench and Percona LUA scripts"
EOF

        info_msg "Building container image from Docker file..."
        podman build --rm -t $SYSBENCH_CONTAINER_IMG_NAME --file Dockerfile.sysbenchlua . &> ${OUTPUT_PATH}/podman_build.log &
        pids[${i}]=$!

        spin "${pids[@]}" &
        spin_pid=$!
        wait "${pids[@]}"

        # Check the exit status of the podman build command
        # TODO: Simplify this check since we're only checking a single PID
        for pid in "${pids[@]}"; do
            if [ $? -eq 0 ]; then
                echo "Podman build command succeeded!"
            else
                echo "Podman build command failed! Check the 'podman_build.log' for more information. Exiting"
                err_state=true
                # exit
            fi
        done

        kill $spin_pid 2> /dev/null
    fi
    info_msg "Done Creating the SysBench Container Image."

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Start the containers
# args: none
# return: 0=success, 1=error
function start_mysql_containers()
{
    local err_state=false
    
    MYSQL_PORT=${MYSQL_START_PORT}
    for i in $(seq 1 ${SCALE});
    do

        # ========== MYSQL ==========

        # Create the MySQL data directory if it does not exist
        if [ ! -d "${MYSQL_DATA_DIR}/mysql${i}" ]; then
            if mkdir -p "${MYSQL_DATA_DIR}/mysql${i}"; then
                info_msg "Directory ${MYSQL_DATA_DIR}/mysql${i} created"
            else
                error_msg "Failed to create ${MYSQL_DATA_DIR}/mysql${i}"
                return 1
            fi
        else
            info_msg "Directory ${MYSQL_DATA_DIR}/mysql${i} exists"
        fi

        # Create a new MySQL container if it does not exist
        if ! podman ps -a --format "{{.Names}}" | grep -q mysql${i}; then
            info_msg "Container 'mysql${i}' doesn't exist. Creating it..."
            podman create --name mysql${i}                              \
                        -p ${MYSQL_PORT}:3306                           \
                        -v ${MYSQL_CONF}:/etc/my.cnf                    \
                        -v ${MYSQL_DATA_DIR}/mysql${i}:/var/lib/mysql   \
                        -e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}   \
                        -e MYSQL_DATABASE=${SysbenchDBName}             \
                        --network ${NETWORK_NAME}                       \
                        --cpus=${SERVER_CPU_LIMIT}                      \
                        --memory=${SERVER_MEMORY_LIMIT}                 \
                        ${MySQLDockerImgTag}
            if [ "$?" -ne "0" ];
            then
                echo ""
                failed_msg "[Creation of container mysql${i} failed. Exiting"
                err_state=true
            fi
            echo "Done."
        fi

        # Start the MySQL container on specific NUMA node if it's not already running
        if ! podman ps --format "{{.Names}}" | grep -q mysql${i}; then
            info_msg "Starting MySQL container 'mysql${i}'..."
            if numactl ${NUMACTL_OPTION} podman start mysql${i}
            then
                info_msg "Done"
            else
                error_msg "Container 'mysql${i}' failed to start. Check `podman logs mysq${i}`"
                err_state=true
            fi
        else 
            info_msg "MySQL container 'mysql${i}' is already running."
        fi

        # Wait for the MySQL container to start
        # TODO: Put a limit, otherwise, this could spin forever.
        info_msg "Waiting for container 'mysql${i}' to start..."
        while ! podman inspect -f '{{.State.Running}}' mysql${i}; do
            sleep 1
            echo -n "."
        done

        # Increment the MySQL port for the next MySQL instance
        MYSQL_PORT=$(($MYSQL_PORT + 1))
    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Start the Sysbench container(s) under numactl control
# args: none
# return: 0=success, 1=error
function start_sysbench_containers() 
{
    local err_state=false

    for i in $(seq 1 ${SCALE});
    do
        # ========== SYSBENCH ==========

        info_msg "Starting Sysbench container 'sysbench${i}'..."
    
        # Set the host in the SYSBENCH_OPTS
        # Check and see of we need to pass in SYSBENCH_OPTS to this set up
        SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/10/" | sed "s/THREADS/4/" | sed "s/RUNTIME/60/" )

        # Create a new Sysbench container if it does not exist
        #   or start a new container if it does exist
        if ! podman ps -a --format "{{.Names}}" | grep -q sysbench${i}; then
            info_msg "Container 'sysbench${i}' doesn't exist. Creating it..."
            numactl --cpunodebind=${SYSBENCH_NUMA_NODE} --membind=${SYSBENCH_NUMA_NODE} podman run -d --rm --name sysbench${i} --network ${NETWORK_NAME} --cpus=${CLIENT_CPU_LIMIT} --memory=${CLIENT_MEMORY_LIMIT} -e SYSBENCH_OPTS="$SYSBENCH_OPTS" localhost/$SYSBENCH_CONTAINER_IMG_NAME
            if [ "$?" -ne "0" ];
            then
                echo ""
                failed_msg "Creation of container sysbench${i} failed. Exiting"
                err_state=true
            else
                info_msg "Container 'sysbench${i}' created successfully"
            fi
            echo "Done."
        elif ! podman ps --format "{{.Names}}" | grep -q sysbench${i}; then
            # Container exists, so start it
            info_msg "Starting SysBench container 'sysbench${i}'..."
            if numactl --cpunodebind=${SYSBENCH_NUMA_NODE} --membind=${SYSBENCH_NUMA_NODE} podman start sysbench${i}
            then
                info_msg "Done"
            else
                error_msg "Container 'sysbench${i}' failed to start. Check `podman logs sysbench${i}`"
                err_state=true
            fi
        else
            info_msg "SysBench container 'sysbench${i}' is already running."
        fi  

        # Wait for the container to start
        info_msg "Waiting for container 'sysbench${i}' to start..."
        while ! podman inspect -f '{{.State.Running}}' sysbench${i}; do
            sleep 1
            echo -n "."
        done
        echo "Done"

    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# The MySQL and Sysbench may take a few seconds to completely start, espceially on the first run
# This function adds a simple delay to the script to give the containers time to complete their startup sequence
# args: none
# return: none
function pause_for_stability()
{
    local seconds 

    seconds=30
    total_seconds=$seconds
    while [ $seconds -gt 0 ]; do
        echo -ne "${STR_INFO} Pausing for $total_seconds seconds to ensure the containers and services are up and running... $seconds\033[0K\r"
        sleep 1
        seconds=$((seconds-1))
    done
    echo
}

# Create the test MySQL database inside the MySQL container
# The MySQL container must be running
# args: none
# return: 0=success, 1=error
function create_mysql_databases()
{
    local err_state=false

    # Start the containers
    for i in $(seq 1 ${SCALE});
    do
        # Wait for the mysql container to start
        info_msg "Verifying the container 'mysql${i}' is still running..."
        while ! podman inspect -f '{{.State.Running}}' mysql${i}; do
            sleep 1
            echo -n "."
        done

        # Create the sbtest database
        info_msg "Server: mysql${i}: Creating the '${SysbenchDBName}' database... "
        # Drop the database on the offchance that it has gotten corrupted by a prior run and recreate it
        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "DROP DATABASE IF EXISTS ${SysbenchDBName};"
        then
            info_msg "Successfully dropped the '${SysbenchDBName}' database"
        else
            error_msg "Failed to drop the '${SysbenchDBName}' database"
            err_state=true
            break # Exit the loop on error
        fi

        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "CREATE DATABASE IF NOT EXISTS ${SysbenchDBName};"
        then
            info_msg "Successfully created the '${SysbenchDBName}' database"
        else
            error_msg "Failed to create the '${SysbenchDBName}' database"
            err_state=true
            break # Exit the loop on error
        fi
        echo "Done"

        # Create the ${SYSBENCH_USER} user and grant privileges
        info_msg "Server: mysql${i}: Creating the '${SYSBENCH_USER}'... "
        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "CREATE USER IF NOT EXISTS '${SYSBENCH_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${SYSBENCH_USER_PASSWORD}'; GRANT ALL PRIVILEGES ON ${SysbenchDBName}.* TO '${SYSBENCH_USER}'@'%'; FLUSH PRIVILEGES;"
        then
            info_msg "Successfully added the '${SYSBENCH_USER}' user to the '${SYSBENCH_USER} database"
        else
            error_msg "Failed to add the '${SYSBENCH_USER}' user to the '${SYSBENCH_USER} database"
            err_state=true
            break # Exit the loop on error
        fi
    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Run the 'tpcc.lua prepare' command inside the Sysbench container
# args: none
# return: 0=success, 1=error
function prepare_the_database()
{
    local pids
    local spin_pid
    local err_state=false
    
    if [ -z ${PREPARE_DB} ];
    then
        return 0
    fi

    # Prepare the database
    info_msg "Preparing the database(s). This will take some time. Please be patient..."
    for i in $(seq 1 ${SCALE});
    do
        info_msg " .... Preparing database on mysql${i} ..."
        SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/10/" | sed "s/THREADS/4/" | sed "s/RUNTIME/60/" )

        podman exec -e SYSBENCH_OPTS="$SYSBENCH_OPTS" sysbench${i} /bin/sh -c "/usr/local/share/sysbench/tpcc.lua $SYSBENCH_OPTS prepare" > ${OUTPUT_PATH}/${OUTPUT_PREFIX}_prepare.${i}.log &
        pids[${i}]=$!
    done

    spin "${pids[@]}" &
    spin_pid=$!
    wait "${pids[@]}" 

    # Check the exit status of the tpcc.lua prepare command
    for pid in "${pids[@]}"; do
        if [ $? -eq 0 ]; then
            info_msg "Sysbench Prepare for pid '${pid}' was successful"
        else
            error_msg "Sysbench Prepare for pid '${pid}' failed"
            err_state=true
            # exit
        fi
    done

    kill $spin_pid 

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Run the 'tpcc.lua warmup' command inside the Sysbench container
# Default warmup time is 600seconds
# args: none
# return: 0=success, 1=error
function warm_the_database()
{
    local pids
    local spin_pid
    local err_state=false

    if [ -z ${WARM_DB} ];
    then
        return 0
    fi
    # Warm the database
    info_msg "Warming the database. This will take some time. Please be patient..."
    for i in $(seq 1 ${SCALE});
    do
        info_msg " .... Warming database on mysql${i} ... "
        SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/10/" | sed "s/THREADS/4/" | sed "s/RUNTIME/300/" )
        podman exec -e SYSBENCH_OPTS="$SYSBENCH_OPTS" sysbench${i} /bin/sh -c "/usr/local/share/sysbench/tpcc.lua $SYSBENCH_OPTS run" > ${OUTPUT_PATH}/${OUTPUT_PREFIX}_warmup.${i}.log &
        pids[${i}]=$!
    done

    spin "${pids[@]}" &
    spin_pid=$! 
    wait "${pids[@]}" 

    # Check the exit status of the tpcc.lua run command
    for pid in "${pids[@]}"; do
        if [ $? -eq 0 ]; then
            info_msg "Sysbench Warm operation for pid '${pid}' was successful"
        else
            error_msg "Sysbench Warm operation for pid '${pid}' failed"
            err_state=true
            # exit
        fi
    done

    kill $spin_pid 

    info_msg "Warmup Completed"

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Run the 'tpcc.lua run' command inside the sysbench container
# args: none
# return: 0=success, 1=error
function run_the_benchmark()
{
    local DSTAT_PID
    local DSTATFILE
    local err_state=false

    if [ -z ${RUN_TEST} ];
    then
        return 0
    fi

    # start the TPC-C Benchmark
    RUNTIME=300
    info_msg "Executing the benchmark run..."
    dstat_find_location_of_db

    # Initiate ramp up tests that start ever increasing number of clients
    # Be careful not to exceed the CPU resources of the Sysbench container
    for threads in 1 2 4 8 16 32 64 128 192 250
    do
        info_msg " ... Start run with parameters threads=${threads} runtime=${RUNTIME} tables=${TABLES} ... "
        DSTATFILE=${OUTPUT_PATH}/${OUTPUT_PREFIX}_dstat-${threads}-threads.csv
        # Remove a previous restult file if present
        rm -f ${DSTATFILE}
        dstat -c -m -d -D ${DATADISK} --io --output ${DSTATFILE} > /dev/null &
        DSTAT_PID=$!
        for i in $(seq 1 ${SCALE});
        do
            # Run the benchmark
            SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/10/" | sed "s/THREADS/${threads}/" | sed "s/RUNTIME/${RUNTIME}/" )
            podman exec -e SYSBENCH_OPTS="$SYSBENCH_OPTS" sysbench${i} /bin/sh -c "/usr/local/share/sysbench/tpcc.lua $SYSBENCH_OPTS run" > ${OUTPUT_PATH}/${OUTPUT_PREFIX}_run_${threads}.${i}.log &
            pids[${i}]=$!
        done

        for pid in ${pids[*]}; do
            wait ${pid}

            # Check the exit status of the podman build command
            if [ $? -eq 0 ]; then
                info_msg "Sysbench Run operation for pid '${pid}' was successful"
            else
                error_msg "Sysbench Run operation for pid '${pid}' failed"
                err_state=true
                return 1
            fi
        done
        # kill -9 ${DSTAT_PID} > /dev/null 2>&1
        kill ${DSTAT_PID} > /dev/null 2>&1

        # Replace the ${DATADISK} with the term datadisk make parsing and reporting easier
        sed -i 's%${DATADISK}%datadisk%g' ${DSTATFILE} # Use % to avoid clobbering sed syntax checks when mount points have '/' in them. eg: when DATADISK='mapper/fedora_fedora-root'
        sed -i 's/total usage://g' ${DSTATFILE}
        sed -i 's/dsk\/datadisk:/dsk_/g' ${DSTATFILE}
        sed -i 's/"read"/"iops_reads"/g' ${DSTATFILE}
        sed -i 's/"writ"/"iops_writ"/g' ${DSTATFILE}
    done
    info_msg "Sysbench completed"

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Remove the test database once the Sysbench benchmarks complete
# args: none
# return: 0=success, 1=error
function cleanup_database()
{
    local pids
    local spin_pid
    local err_state=false

    if [ -z ${CLEANUP} ];
    then
        return 0
    fi

    info_msg "Starting cleanup of the MySQL database..."
    for i in $(seq 1 ${SCALE});
    do
        SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/10/" | sed "s/THREADS/4/" | sed "s/RUNTIME/600/" )
        podman exec -e SYSBENCH_OPTS="$SYSBENCH_OPTS" sysbench${i} /bin/sh -c "/usr/local/share/sysbench/tpcc.lua $SYSBENCH_OPTS cleanup" > ${OUTPUT_PATH}/${OUTPUT_PREFIX}_cleanup.${i}.log &
        # Check for failure here, bail out and clean up
        pids[${i}]=$!
    done

    spin "${pids[@]}" &
    spin_pid=$!
    wait "${pids[@]}"

    # Check the exit status of the tpcc.lua cleanup command
    for pid in "${pids[@]}"; do
        if [ $? -eq 0 ]; then
            info_msg "Sysbench Cleanup operation for pid '${pid}' was successful"
        else
            error_msg "Sysbench Cleanup operation for pid '${pid}' failed"
            err_state=true
            # exit
        fi
    done

    kill $spin_pid

    # Remove the MySQL Data Directory
    if ! rm -rf "/${MYSQL_DATA_DIR}/mysql-$i" >/dev/null 2>&1
    then
        error_msg "Failed to remove '/${MYSQL_DATA_DIR}/mysql-$i'"
    fi

    info_msg "MySQL Cleanup completed"

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Get the container logs
# args: none
# return: 0=success, 1=error
function get_container_logs() {
    local err_state=false

    info_msg "Collecting container logs..."

    for i in $(seq 1 ${SCALE});
    do
        if podman logs mysql${i} > ${OUTPUT_PATH}/${OUTPUT_PREFIX}_mysql.${i}.log
        then
            info_msg "... Container 'mysql${i}' logs successfully written to '${OUTPUT_PATH}/${OUTPUT_PREFIX}_mysql.${i}.log'"
        else
            error_msg " ... Failed to collect the container logs for mysql${i}"
        fi

        if podman logs sysbench${i} > ${OUTPUT_PATH}/${OUTPUT_PREFIX}_mysql.${i}.log
        then
            info_msg "... Container 'sysbench${i}' logs successfully written to '${OUTPUT_PATH}/${OUTPUT_PREFIX}_sysbench.${i}.log'"
        else
            error_msg " ... Failed to collect the container logs for sysbench${i}"
        fi
    done
}

# Stop the MySQL and Sysbench containers
# args: none
# return: 0=success, 1=error
function stop_containers()
{
    local err_state=false

    # Stop the container
    info_msg "Stopping the MySQL and SysBench containers..."
    for i in $(seq 1 ${SCALE});
    do
        if podman stop mysql${i}
        then
            info_msg "... Container 'mysql${i}' stopped successfully"
        else
            error_msg "... Container 'mysql${i}' failed to stop successfully. Verify podman killed the container."
            err_state=true
        fi

        if podman kill sysbench${i}
        then
            info_msg "... Container 'sysbench${i}' was killed successfully"
        else
            error_msg "... Container 'sysbench${i}' failed to be killed."
            err_state=true
        fi
    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Remove the MySQL and Sysbench containers from the Podman environment
# args: none
# return: 0=success, 1=error
function remove_containers()
{
    local err_state=false

    if [ -z ${CLEANUP} ];
    then
        return
    fi

    # Remove the containers
    info_msg "Removing the MySQL containers..."
    for i in $(seq 1 ${SCALE});
    do
        # The sysbench containers are created on the fly, and are not retained after 
        # the have been killed
        if podman rm mysql${i}
        then
            info_msg "... Container 'mysql${i}' removed successfully"
        else
            error_msg "... Container 'mysql${i}' removal failed"
            err_state=true
        fi
    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

#################################################################################################
# Main
#################################################################################################

# Display the help information if no arguments were provided
if [ "$#" -eq "0" ];
then
    print_usage
    exit 1
fi

# Process the command line arguments
while getopts 'cC:e:hi:M:o:prs:S:t:w' opt; do
    case "$opt" in
        c)
            CLEANUP=1
            ;;
        C)
            MYSQL_CPU_NUMA_NODE=${OPTARG}
            ;;
        e)
            # Experient values are dram|interleave|tier|mm
            EXPERIMENT=${OPTARG}
            ;;
        i)
            SCALE=${OPTARG}
            ;;
        M)
            MYSQL_MEM_NUMA_NODE=${OPTARG}
            ;;
        o)
            OUTPUT_PREFIX=${OPTARG}
            ;;
        p)
            PREPARE_DB=1
            ;;
        r)
            RUN_TEST=1
            ;;
        t)
            TABLES=${OPTARG}
            ;;
        s)
            SCALE=${OPTARG}
            ;;
        S)
            SYSBENCH_NUMA_NODE=${OPTARG}
            ;;
        w)
            WARM_DB=1
            ;;
        ?|h)
            print_usage
            exit
            ;;
    esac
done

if [[ ( -z ${RUN_TEST} && -z ${PREPARE_DB} && -z ${CLEANUP} && -z ${WARM_DB}) ]];
then
    print_usage
    echo "    One or both of -c or -r or -p options are needed to proceed"
    exit 1
fi  

if [[ ("$EXPERIMENT" != "tier" && "$EXPERIMENT" != "interleave" && "$EXPERIMENT" != "mm" && "$EXPERIMENT" != "dram") ]];
then
    error_msg "-e must be specified"
    print_usage
    exit 1
fi

if [[ ( -z ${MYSQL_CPU_NUMA_NODE} || -z ${MYSQL_MEM_NUMA_NODE}) ]];
then
    error_msg "-C and -M must be specified"
    print_usage
    exit 1
fi

if [ -z ${SYSBENCH_NUMA_NODE} ];
then
    error_msg "-S must be specified"
    print_usage
    exit 1
fi
 

if [[ ( ! -z ${RUN_TEST} && -z ${WARM_DB}) ]];
then
    warn_msg "Warmup (-w) was not specified for this run. Results may not be reproducible if the database was not warmed up before this run"
fi

if [ -z ${OUTPUT_PREFIX} ];
then
    print_usage
    exit 1
fi

# Verify the mandatory commands and utilities are installed. Exit on error.
if ! verify_cmds
then
    exit
fi

# Initialize the environment
init

# Detect Terminal Type
auto_detect_terminal_colors

# Save STDOUT and STDERR logs to the data collection directory
log_stdout_stderr "${OUTPUT_PATH}"

# Display the header information
display_start_info

# Check if the MySQL data directory on host exists and is writable by this user
if [ ! -d ${MYSQL_DATA_DIR} ];
then
    error_msg "${MYSQL_DATA_DIR} is not present. Please create the '${MYSQL_DATA_DIR}' directory and retry. Exiting"
    exit
fi

# MYSQL config file
# Modify this file or create a new config to use
if [ ! -f ${MYSQL_CONF} ];
then
    error_msg " '${MYSQL_CONF}' is not present. Please create the mysql configuration file and retry. Exiting"
    exit
fi

# Define the array of functions to call in the correct order
functions=("create_network" "set_numactl_options" "create_sysbench_container_image" "start_sysbench_containers" "start_mysql_containers" "pause_for_stability" "create_mysql_databases" "prepare_the_database" "warm_the_database" "run_the_benchmark" "cleanup_database" "get_container_logs" "stop_containers" "remove_containers")

# Iterate over the array of functions and call them one by one
# Handle the return value: 0=Success, 1=Failure
for function in "${functions[@]}"; do
    # Call the function and store the return value
    "$function"
    return_value=$?

    # Check if an error occurred
    if [ $return_value -ne 0 ]; then
        echo "An error occurred in $function. Exiting."
        goto out
    fi
done

# Fatal Errors will jump here without further processing
#out:#

# Display the end header information
display_end_info