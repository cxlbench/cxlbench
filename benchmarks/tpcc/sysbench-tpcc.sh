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

SCRIPTDIR=$( dirname $( readlink -f $0 ))
source ${SCRIPTDIR}/../../lib/common     # Provides common functions
source ${SCRIPTDIR}/../../lib/msgfmt     # Provides pretty print messages to STDOUT


#################################################################################################
# Variables
#################################################################################################

# ==== Podman Variables ====

# Podman network name
NETWORK_NAME=mysqlsysbench

# Container CPU and memory limits for the MySQL server and the Sysbench client
# Note: The MySQL (server) values should be configured for the size of the test database. The OOM killer will stop the database if too few resources are assigned.
CLIENT_CPU_LIMIT=4              # Number of vCPUs to give to the Sysbench container: Override by -U
CLIENT_MEMORY_LIMIT=1g          # Amount of memory (GiB) to give to the Sysbench container: Override by -V
SERVER_CPU_LIMIT=4              # Number of vCPUs to give to the MySQL container: Overide by -D
SERVER_MEMORY_LIMIT=16g         # Amount of memory (GiB) to give to the MySQL container: Override by -E
INNODB_BUFFER_POOL_SIZE=10G     # Size of the innodb_buffer_pool: Override by -X
PM_INSTANCES=1                  # Number of podman instances to start: Override by -i

# === MySQL Variables ===

MYSQL_ROOT_PASSWORD=my-secret-pw                        # Root Users Password
MYSQL_START_PORT=3333                                   # Host Port number for the first instance. Additional instances will increment by 1 for each instance 3306..3307..3308..
MYSQL_DATA_DIR=/data                                    # Base directory for the MySQL Data Directory on the host
MYSQL_CONF=${SCRIPTDIR}/my.cnf.d/my.cnf                 # Location of the my.cnf file(s)
MySQLDockerImgTag="docker.io/library/mysql:8.0.39"      # MySQL Version. Get the Docker Tag ID from https://hub.docker.com/_/mysql


# === Sysbench Variables ===

# Sysbench username and password
SYSBENCH_USER="sbuser"
SYSBENCH_USER_PASSWORD="sbuser-pwd"
SCALE=10                                    # Default number of warehouses. Use -s to override
TABLES=10                                   # Default number of tables per warehouse. Use -t to override
SYSBENCH_WARMTIME=300                       # Duration (seconds) to warm the database before running tests
SYSBENCH_RUNTIME=300                        # Duration (seconds) for the 'run' operation. Use -T to override
SYSBENCH_CONTAINER_IMG_NAME="sysbenchmysql" # Sysbench container image name
SysbenchDBName="sbtest"                     # Name of the MySQL Database to create and run Sysbench against
# Sysbench options
SYSBENCH_OPTS_TEMPLATE="--db-driver=mysql --mysql-db=${SysbenchDBName} --mysql-user=${SYSBENCH_USER} --mysql-password=${SYSBENCH_USER_PASSWORD} --mysql-host=mysqlINSTANCE --mysql-port=3306 --time=RUNTIME  --threads=THREADS --tables=TABLES --scale=SCALE"
SYSBENCH_THREADS=1                          # Number of Sysbench workload generator threads. Use -W to override

# === Misc Variables ===

OPT_FUNCS_BEFORE=""                   # Optional functions that get called before the bechmarks start in the main loop
OPT_FUNCS_AFTER=""                    # Optional functions that get called after the bechmarks complete in the main loop

#################################################################################################
# Functions
#################################################################################################

# THis function will be called if a user sends a SIGINT (Ctrl-C)
function ctrl_c()
{
  info_msg "Received CTRL+C - aborting"
  stop_containers
  remove_containers
  display_end_info
  exit 1
}

# Handle Ctrl-C User Input
trap ctrl_c SIGINT

# Implementing 'goto' functionality
# Usage: goto end
# Labels/Tags are '# end: #', or '#end:#' or '# end: # This is a comment'
function goto()
{
  label=$1
  cmd=$(sed -En "/^[[:space:]]*#[[:space:]]*$label:[[:space:]]*#/{:a;n;p;ba};" "$0")
  eval "$cmd"
  exit
}

function init()
{
    # Create the output directory
    init_outputs
    # Configure the innodb buffer pool size
    sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = $INNODB_BUFFER_POOL_SIZE/" ${SCRIPTDIR}/my.cnf.d/my.cnf
}

# Verify the required commands and utilities exist on the system
# We use either the defaults or user specified paths
# args: none
# return: 0=success, 1=error
function verify_cmds()
{
    local err_state=false

    for CMD in numactl lscpu lspci grep cut sed awk podman dstat; do
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
    echo "    ${SCRIPT_NAME} OPTIONS"
    echo " [Experiment options]"
    echo "      -e dram|cxl|numainterleave|numapreferred|   : [Required] Memory environment"
    echo "         kerneltpp"
    echo "      -i <number_of_instances>                    : The number of container intances to execute: Default 1"
    echo "      -o <prefix>                                 : [Required] prefix of the output files: Default 'test'"
    echo "      -s <scale>                                  : Number of warehouses (scale): Default 10"
    echo "      -t <number_of_tables>                       : The number of tables per warehouse: Default 10"
    echo "      -T <run time>                               : Number of seconds to 'run' the benchmark. Default ${SYSBENCH_RUNTIME}"
    echo "      -W <worker threads>                         : Maximum number of Sysbench worker threads. Default 1"

    echo " [Run options]"
    echo "      -c                                          : Cleanup. Completely remove all containers and the MySQL database"
    echo "      -p                                          : Prepare the database"
    echo "      -w                                          : Warm the database. Default False."
    echo "      -r                                          : Run the Sysbench workload"

    echo " [Machine confiuration options]"
    echo "      -C <numa_node>                              : [Required] CPU NUMA Node to run the MySQLServer"
    echo "      -D <server_cpus_for_each_instance>          : [Optional] Number of vCPUs for each server [Default $SERVER_CPU_LIMIT]"
    echo "      -E <server_memory_in_GB_for_each_instance>  : [Optional] Memory in GB for each server [Default $SERVER_MEMORY_LIMIT]"
    echo "      -M <numa_node,..>                           : [Required] Memory NUMA Node to run the MySQLServer"
    echo "      -U <client_cpus_for_each_instance>          : [Optional] Number of vCPUs for each client [Default $CLIENT_CPU_LIMIT]"
    echo "      -V <client_memory_in_GB_for_each_instance>  : [Optional] Memory in GB for each client [Default $CLIENT_MEMORY_LIMIT]"
    echo "      -X <size_of_innodb_pool_in_GB>              : [Optional] Memory in GB for the mysql database [Default $INNODB_BUFFER_POOL_SIZE]"
    echo "      -S <numa_node>                              : [Required] CPU NUMA Node to run the Sysbench workers"

    echo "      -h                                          : Print this message"
    echo " "
    echo "Example 1: Runs a single MySQL server on NUMA 0 and a single SysBench instance on NUMA Node1, "
    echo "  prepares the database, runs the benchmark from 1..1000 threads in powers of two, "
    echo "  and removes the database and containers when complete. "
    echo "  The server and client CPU, Memory sizes are default. " 
    echo " "
    echo "    $ ./${SCRIPT_NAME} -e dram -o test -i 1 -t 10 -W 1000  -C 0 -M 0 -S 1 -p -w -r -c"
    echo " "
    echo "Example 2: Created the MySQL and Sysbench containers, runs the MySQL container on NUMA Node 0, the "
    echo "  Sysbench container on NUMA Node 1, then prepares the database and exits. The containers are left running."
    echo "  The server and client CPU, Memory sizes are default. " 
    echo " "
    echo "    $ ./${SCRIPT_NAME} -e dram -o test -C 0 -M 0 -S 1 -p"
    echo " "
    echo "Example 3: Created the MySQL and Sysbench containers, runs the MySQL container on NUMA Node 0, the "
    echo "  Sysbench container on NUMA Node 1, then prepares the database and exits. The containers are left running."
    echo "  52 cores on socket 0 and 512GB on socket 0 are used to run the MySQL container. "
    echo "  26 cores on socket 1 and 48GB on socket 1 are used to nun the sysbench client container. "
    echo " "
    echo "    $ ./${SCRIPT_NAME} -e dram -o test -C 0 -M 0 -S 1 -p -D 52 -E 512 -U 26 -X 48"
    echo " "
}

# Creates a spinner animation to show the script is working in the background
# args: none
# return: none
function spin()
{
    local -a marks=( '/' '-' '\' '|' )
    local spin_pid=$1

    while [[ true ]]; do
        printf '%s\r' "${marks[i++ % ${#marks[@]}]}"
        sleep 1
        #if ! kill -0 "$spin_pid" &> /dev/null; then
        #    return
        #fi
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

# From the MEM_ENVIRONMENT (-e) argument, determine what numactl options to use
# args: none
# return: none
function set_numactl_options()
{
    case "$MEM_ENVIRONMENT" in
        dram|cxl|mm|kerneltpp)
            NUMACTL_OPTION="--cpunodebind ${MYSQL_CPU_NUMA_NODE} --membind ${MYSQL_MEM_NUMA_NODE}"
            ;;
        numapreferred)
            NUMACTL_OPTION="--cpunodebind ${MYSQL_CPU_NUMA_NODE} --preferred ${MYSQL_MEM_NUMA_NODE}"
            ;;
        numainterleave)
            NUMACTL_OPTION="--cpunodebind ${MYSQL_CPU_NUMA_NODE} --interleave ${MYSQL_MEM_NUMA_NODE}"
            ;;
    esac
}

# Create the podman network
# args: none
# return: 0=success, 1=error
function create_network()
{
    if ! podman network exists ${NETWORK_NAME} &> /dev/null; then
        info_msg "Creating a new Podman network called '${NETWORK_NAME}'."
        # podman network create ${NETWORK_NAME}
        if podman network create "${NETWORK_NAME}" > /dev/null 2> "${OUTPUT_PATH}/podman_exec_create_network.err"; then
            info_msg "Network '${NETWORK_NAME}' created successfully"
            return 0
        else
            error_msg "Error creating network '${NETWORK_NAME}'"
            return 1
        fi
    else
        info_msg "Network '${NETWORK_NAME}' already exists"
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
        pids[0]=$!

        spin "${pids[0]}" &  # Start the spinner with the first process ID
        spin_pid=$!
        wait "${pids[@]}"

        # Check the exit status of the podman build command
        # TODO: Simplify this check since we're only checking a single PID
        for pid in "${pids[@]}"; do
            if [ $? -eq 0 ]; then
                info_msg "Podman build command succeeded!"
            else
                error_msg "Podman build command failed! Check the 'podman_build.log' for more information. Exiting"
                err_state=true
            fi
        done

        kill $spin_pid &> /dev/null
    fi

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Create and Start the MySQL containers
# args: none
# return: 0=success, 1=error
function start_mysql_containers()
{
    local err_state=false
    local timeout_duration=120  # Set the timeout duration
    local start_time

    MYSQL_PORT=${MYSQL_START_PORT}

    info_msg "MySQL Server containers will use memory NUMA Nodes '${MYSQL_MEM_NUMA_NODE}' with the '${MEM_ENVIRONMENT}' numa policy."

    for i in $(seq 1 ${PM_INSTANCES});
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

            # Give all permisions on the data directory
            if ! chmod 777 ${MYSQL_DATA_DIR}/mysql${i}
            then
                error_msg "Failed to 'chmod 777 ${MYSQL_DATA_DIR}/mysql${i}'. The database may not start"
            fi
        else
            info_msg "Directory ${MYSQL_DATA_DIR}/mysql${i} exists"
        fi

        # Create a new MySQL container if it does not exist
        if ! podman ps -a --format "{{.Names}}" | grep -q mysql${i}; then
            info_msg "Container 'mysql${i}' doesn't exist. Creating it..."
            podman create --name mysql${i}                              \
                        -p ${MYSQL_PORT}:3306                           \
                        -v ${MYSQL_CONF}:/etc/my.cnf:rw                 \
                        -v ${MYSQL_DATA_DIR}/mysql${i}:/var/lib/mysql:rw \
                        -e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}   \
                        -e MYSQL_DATABASE=${SysbenchDBName}             \
                        --network ${NETWORK_NAME}                       \
                        --cpus=${SERVER_CPU_LIMIT}                      \
                        --memory=${SERVER_MEMORY_LIMIT}                 \
                        ${MySQLDockerImgTag} > /dev/null 2> ${OUTPUT_PATH}/podman_create_mysql${i}.err
            if [ "$?" -ne "0" ];
            then
                echo ""
                failed_msg "Creation of container mysql${i} failed. Exiting"
                err_state=true
            fi
        fi

        # Start the MySQL container on specific NUMA node if it's not already running
        if ! podman ps --format "{{.Names}}" | grep -q mysql${i} &> /dev/null; then
            info_msg "Starting MySQL container 'mysql${i}'..."
            if numactl ${NUMACTL_OPTION} podman start mysql${i} > /dev/null 2> ${OUTPUT_PATH}/podman_start_mysql${i}.err
            then
                info_msg "Container 'mysql${i}' started successfully."
            else
                error_msg "Container 'mysql${i}' failed to start. Check '${OUTPUT_PATH}/podman_start_mysql${i}.err'"
                err_state=true
            fi
        else
            info_msg "MySQL container 'mysql${i}' is already running."
        fi

        # Get the current time
        start_time=$SECONDS

        # Wait for the container to start
        info_msg "Waiting for container 'mysql${i}' to start..."
        while ! podman inspect -f '{{.State.Running}}' mysql${i} &> /dev/null; do
            # Check if the timeout duration has been exceeded
            current_time=$(($SECONDS - $start_time))
            if [[ $current_time -gt $timeout_duration ]]; then
                error_msg "Timeout: Container 'mysql${i}' did not start within 120 seconds."
                break
            fi

            sleep 5
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
    local timeout_duration=120  # Set the timeout duration
    local start_time

    for i in $(seq 1 ${PM_INSTANCES});
    do
        # ========== SYSBENCH ==========

        info_msg "Starting Sysbench container 'sysbench${i}'..."

        # Set the host in the SYSBENCH_OPTS
        # Check and see of we need to pass in SYSBENCH_OPTS to this set up
        SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/${SCALE}/" | sed "s/THREADS/4/" | sed "s/RUNTIME/60/" )

        # Create a new Sysbench container if it does not exist
        #   or start a new container if it does exist
        if ! podman ps -a --format "{{.Names}}" | grep -q sysbench${i}; then
            info_msg "Container 'sysbench${i}' doesn't exist. Creating it..."
            numactl --cpunodebind=${SYSBENCH_NUMA_NODE} --membind=${SYSBENCH_NUMA_NODE} podman run -d --rm --name sysbench${i} --network ${NETWORK_NAME} --cpus=${CLIENT_CPU_LIMIT} --memory=${CLIENT_MEMORY_LIMIT} -e SYSBENCH_OPTS="$SYSBENCH_OPTS" localhost/$SYSBENCH_CONTAINER_IMG_NAME &> /dev/null
            if [ "$?" -ne "0" ];
            then
                echo ""
                failed_msg "Creation of container sysbench${i} failed. Exiting"
                err_state=true
            else
                info_msg "Container 'sysbench${i}' created successfully"
            fi
        elif ! podman ps --format "{{.Names}}" | grep -q sysbench${i}; then
            # Container exists, so start it
            info_msg "Starting SysBench container 'sysbench${i}'..."
            if numactl --cpunodebind=${SYSBENCH_NUMA_NODE} --membind=${SYSBENCH_NUMA_NODE} podman start sysbench${i} &> /dev/null
            then
                info_msg "Container 'sysbench${i}' started successfully."
            else
                error_msg "Container 'sysbench${i}' failed to start. Check 'podman logs sysbench${i}'"
                err_state=true
            fi
        else
            info_msg "SysBench container 'sysbench${i}' is already running."
        fi

        # Get the current time
        start_time=$SECONDS

        # Wait for the container to start
        info_msg "Waiting for container 'sysbench${i}' to start..."
        while ! podman inspect -f '{{.State.Running}}' sysbench${i} &> /dev/null; do
            # Check if the timeout duration has been exceeded
            current_time=$(($SECONDS - $start_time))
            if [[ $current_time -gt $timeout_duration ]]; then
                error_msg "Timeout: Container 'sysbench${i}' did not start within 120 seconds."
                break
            fi

            sleep 5
            echo -n "."
        done

    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# The MySQL and Sysbench containers may take a few seconds to completely start, especially on the first run.
# This function watches the podman logs for all MySQL containers, to make sure they have all started before returning.
# args: none
# return: 0=success, 1=error
function pause_for_stability() {
    for i in $(seq 1 ${PM_INSTANCES});
    do
        container_name="mysql${i}"
        expected_message="X Plugin ready for connections. Bind-address: '::' port: 33060, socket: /var/run/mysqld/mysqlx.sock"

        info_msg "Waiting for $container_name to be ready..."

        local elapsed_seconds=0
        while true; do
            log_output=$(podman logs "$container_name" 2>&1 | tail -1)

            if [[ "$log_output" == *"$expected_message"* ]]; then
                echo
                info_msg "MySQL is ready."
                break
            else
                echo -ne "${STR_INFO} waiting for containers to initialize. Elapsed: ${elapsed_seconds}s.\033[0K\r"

                sleep 1
                ((elapsed_seconds++))
            fi
        done
    done

    info_msg "Done waiting for MySQL container(s) to start"
}

# Create the test MySQL database inside the MySQL container
# The MySQL container must be running
# args: none
# return: 0=success, 1=error
function create_mysql_databases()
{
    local err_state=false

    # Start the containers
    for i in $(seq 1 ${PM_INSTANCES});
    do
        # Confirm the mysql container is running
        info_msg "Verifying the container 'mysql${i}' is still running..."
        if ! podman inspect -f '{{.State.Running}}' mysql${i} &> /dev/null
        then
            error_msg "... Container 'mysql${i}' is not running. Check 'podman logs mysql${i}' for more information"
            err_state=true
            break # Exit the loop on error
        fi

        # Create the sbtest database
        info_msg "Server: mysql${i}: Creating the '${SysbenchDBName}' database... "
        # Drop the database on the offchance that it has gotten corrupted by a prior run and recreate it
        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "DROP DATABASE IF EXISTS ${SysbenchDBName};" > /dev/null 2> "${OUTPUT_PATH}/podman_exec_drop_database.err"
        then
            info_msg "Successfully dropped the '${SysbenchDBName}' database"
        else
            error_msg "Failed to drop the '${SysbenchDBName}' database. See '${OUTPUT_PATH}/podman_exec_drop_database.err' for more information."
            err_state=true
            break # Exit the loop on error
        fi

        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "CREATE DATABASE IF NOT EXISTS ${SysbenchDBName};" > /dev/null 2> "${OUTPUT_PATH}/podman_exec_create_database.err"
        then
            info_msg "Successfully created the '${SysbenchDBName}' database"
        else
            error_msg "Failed to create the '${SysbenchDBName}' database"
            err_state=true
            break # Exit the loop on error
        fi

        # Create the ${SYSBENCH_USER} user and grant privileges
        info_msg "Server: mysql${i}: Creating the '${SYSBENCH_USER}'... "
        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "CREATE USER IF NOT EXISTS '${SYSBENCH_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${SYSBENCH_USER_PASSWORD}'; GRANT ALL PRIVILEGES ON ${SysbenchDBName}.* TO '${SYSBENCH_USER}'@'%'; FLUSH PRIVILEGES;" > /dev/null 2> "${OUTPUT_PATH}/podman_exec_create_sbtest_user.err"
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

# Reenable REDO logging.  Should be used to speed up the prepare and clean up operations.
# args: none
function enable_redo_logs()
{
    # Enable the REDO LOG
    for i in $(seq 1 ${PM_INSTANCES});
    do
        # Reenable the REDO Log for the prepare to speed up the inserttion of data
        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "ALTER INSTANCE ENABLE INNODB REDO_LOG;" > /dev/null 2>> "${OUTPUT_PATH}/podman_exec_enable_innodb_redo_log.${i}.err"
        then
            info_msg "Successfully enabled the REDO LOG"
        else
            # This is not fatal, but report it.
            warn_msg "Failed to enable the REDO LOG. See '${OUTPUT_PATH}/podman_exec_enable_innodb_redo_log.${i}.err' for more information."
        fi
    done
}

# Temporarily disable REDO logging.  Should be used to speed up the prepare and clean up operations.
# args: none
function disable_redo_log()
{
    for i in $(seq 1 ${PM_INSTANCES});
    do
        # Temporarily disable the REDO Log for the prepare to speed up the inserttion of data
        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "ALTER INSTANCE DISABLE INNODB REDO_LOG;" > /dev/null 2>> "${OUTPUT_PATH}/podman_exec_disable_innodb_redo_log.${i}.err"
        then
            info_msg "Successfully disabled the REDO LOG"
        else
            # This is not fatal, but report it.
            warn_msg "Failed to disable the REDO LOG. See '${OUTPUT_PATH}/podman_exec_disable_innodb_redo_log.${i}.err' for more information."
        fi
    done
}


# Run the 'tpcc.lua prepare' command inside the Sysbench container
# args: none
# return: 0=success, 1=error
function prepare_the_database()
{
    local pids
    local spin_pid
    local err_state=false
    local duration          # Time taken to complete this task
    local start_time        # Start time in epoch seconds

    if [ -z ${PREPARE_DB} ];
    then
        return 0
    fi

    start_time=$(date +%s)

    # Prepare the database
    info_msg "Preparing the database(s). This will take some time. Please be patient..."
    disable_redo_log
    for i in $(seq 1 ${PM_INSTANCES});
    do
        info_msg " ... Preparing database on mysql${i} ..."
        SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/${SCALE}/" | sed "s/THREADS/${CLIENT_CPU_LIMIT}/" | sed "s/RUNTIME/60/" )

        podman exec -e SYSBENCH_OPTS="$SYSBENCH_OPTS" sysbench${i} /bin/sh -c "/usr/local/share/sysbench/tpcc.lua $SYSBENCH_OPTS prepare" &> ${OUTPUT_PATH}/${OUTPUT_PREFIX}prepare.${i}.log &
        pids[${i}-1]=$!
    done

    spin "${pids[0]}" &  # Start the spinner with the first process ID
    spin_pid=$!
    wait "${pids[@]}"

    # Check the exit status of the tpcc.lua prepare command
    for pid in "${pids[@]}"; do
        if [ $? -eq 0 ]; then
            info_msg " ... Sysbench Prepare for pid '${pid}' completed successfully"
        else
            error_msg " ... Sysbench Prepare for pid '${pid}' failed"
            err_state=true
        fi
    done

    kill $spin_pid &> /dev/null

    enable_redo_logs
    # Calculate the time to prepare the database
    duration=$(calc_time_duration ${start_time})
    info_msg "Prepare completed in ${duration}"

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
    local duration          # Time taken to complete this task
    local start_time        # Start time in epoch seconds

    if [ -z ${WARM_DB} ];
    then
        return 0
    fi

    start_time=$(date +%s)    # Start time in epoch seconds

    # Warm the database
    info_msg "Warming the database. This will take approximately ${SYSBENCH_WARMTIME} seconds. Please be patient..."
    for i in $(seq 1 ${PM_INSTANCES});
    do
        info_msg " ... Warming database on mysql${i} ... "
        SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/${SCALE}/" | sed "s/THREADS/${CLIENT_CPU_LIMIT}/" | sed "s/RUNTIME/${SYSBENCH_WARMTIME}/" )
        podman exec -e SYSBENCH_OPTS="$SYSBENCH_OPTS" sysbench${i} /bin/sh -c "/usr/local/share/sysbench/tpcc.lua $SYSBENCH_OPTS run" > ${OUTPUT_PATH}/${OUTPUT_PREFIX}warmup.${i}.log &
        pids[${i}-1]=$!
    done

    spin "${pids[0]}" &  # Start the spinner with the first process ID
    spin_pid=$!
    wait "${pids[@]}"

    # Check the exit status of the tpcc.lua run command
    for pid in "${pids[@]}"; do
        if [ $? -eq 0 ]; then
            info_msg " ... Sysbench Warm operation for pid '${pid}' completed successfully"
        else
            error_msg " ... Sysbench Warm operation for pid '${pid}' failed"
            err_state=true
            # exit
        fi
    done

    kill $spin_pid &> /dev/null

    # Calculate the time to warmup the database
    duration=$(calc_time_duration ${start_time})
    info_msg "Warmup completed in ${duration}"

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Uses the SYSBENCH_THREADS value (-W) to generate a sequence of threads to use
# args: $1 = Maximum value in the sequence
# return: array/list of integer values
# Example:
#     arg1 = 1024
#     Returned sequence = "1 2 4 8 16 32 64 128 256 512 1024"
generate_worker_thread_sequence()
{
    max_value=$1
    seq=""

    if ! [[ $max_value =~ ^[0-9]+$ ]]; then
        seq="1"
    elif [[ $max_value -eq 1 ]]; then
        seq="1"
    else
        for ((i = 0; ; i++)); do
            value=$((2 ** i))
            if ((value > max_value)); then
                if ((value / 2 != max_value)); then
                    seq+=" $max_value"
                fi
                break
            fi
            seq+=" $value"
        done
    fi

    echo "$seq"
}

# Run the 'tpcc.lua run' command inside the sysbench container
# args: none
# return: 0=success, 1=error
function run_the_benchmark()
{
    local DSTAT_PID
    local DSTATFILE
    local PODMAN_STATS_OUTPUT_FILE
    local PODMAN_STATS_PID
    local err_state=false
    local duration          # Time taken to complete this task
    local start_time    # Start time in epoch seconds
    local sequence      # Number of workers from 1 .. SYSBENCH_THREADS
    local threads

    if [ -z ${RUN_TEST} ];
    then
        return 0
    fi

    info_msg "Executing the benchmark run..."
    dstat_find_location_of_db

    start_time=$(date +%s)    # Start time in epoch seconds

    # Initiate ramp up tests that start an increasing number of clients, e.g.:
    # for threads in 1 2 4 8 16 32 64 128 192 256 384 425 500 768 1000
    sequence=$(generate_worker_thread_sequence ${SYSBENCH_THREADS})

    for threads in $sequence
    do
        info_msg " ... Start run with parameters threads=${threads} runtime=${SYSBENCH_RUNTIME} tables=${TABLES} ... "
        DSTATFILE=${OUTPUT_PATH}/${OUTPUT_PREFIX}dstat-${threads}-threads.csv
        PODMAN_STATS_OUTPUT_FILE=${OUTPUT_PATH}/${OUTPUT_PREFIX}podman_stats-${threads}-threads.out

        # Remove a previous restult file if present
        rm -f ${DSTATFILE} &> /dev/null
        rm -f ${PODMAN_STATS_OUTPUT_FILE} &> /dev/null

        # Start the data collection
        dstat -c -m -d -D ${DATADISK} --io --output ${DSTATFILE} &> /dev/null &
        DSTAT_PID=$!

        podman stats --no-reset --format "table {{.Name}},{{.ID}},{{.CPUPerc}},{{.MemUsageBytes}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}},{{.PIDS}}" &> ${PODMAN_STATS_OUTPUT_FILE=} &
        PODMAN_STATS_PID=$!

        for i in $(seq 1 ${PM_INSTANCES});
        do
            # Run the benchmark
            SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/${SCALE}/" | sed "s/THREADS/${threads}/" | sed "s/RUNTIME/${SYSBENCH_RUNTIME}/" )
            podman exec -e SYSBENCH_OPTS="$SYSBENCH_OPTS" sysbench${i} /bin/sh -c "/usr/local/share/sysbench/tpcc.lua $SYSBENCH_OPTS run" &> ${OUTPUT_PATH}/${OUTPUT_PREFIX}run_${threads}.${i}.log &
            pids[${i}-1]=$!
        done

        for pid in ${pids[*]}; do
            wait ${pid}

            # Check the exit status of the podman build command
            if [ $? -eq 0 ]; then
                info_msg " ...... Sysbench Run operation for pid '${pid}' completed succesfuly"
            else
                error_msg " ...... Sysbench Run operation for pid '${pid}' failed"
                err_state=true
                return 1
            fi
        done

        # Stop the data collection
        kill ${DSTAT_PID} > /dev/null 2>&1
        kill ${PODMAN_STATS_PID} > /dev/null 2>&1

        # Replace the ${DATADISK} with the term datadisk make parsing and reporting easier
        sed -i 's%${DATADISK}%datadisk%g' ${DSTATFILE} # Use % to avoid clobbering sed syntax checks when mount points have '/' in them. eg: when DATADISK='mapper/fedora_fedora-root'
        sed -i 's/total usage://g' ${DSTATFILE}
        sed -i 's/dsk\/datadisk:/dsk_/g' ${DSTATFILE}
        sed -i 's/"read"/"iops_reads"/g' ${DSTATFILE}
        sed -i 's/"writ"/"iops_writ"/g' ${DSTATFILE}
    done

    # Calculate the time to warmup the database
    duration=$(calc_time_duration ${start_time})
    info_msg "Sysbench completed in ${duration}"

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
    local start_time        # Start time in epoch seconds
    local err_state=false

    if [ -z ${CLEANUP} ];
    then
        return 0
    fi

    start_time=$(date +%s)

    info_msg "Starting cleanup of the MySQL database..."
    disable_redo_log
    for i in $(seq 1 ${PM_INSTANCES});
    do
        SYSBENCH_OPTS=$(echo ${SYSBENCH_OPTS_TEMPLATE} | sed "s/INSTANCE/${i}/" | sed "s/TABLES/${TABLES}/" | sed "s/SCALE/${SCALE}/" | sed "s/THREADS/${CLIENT_CPU_LIMIT}/" | sed "s/RUNTIME/600/" )
        podman exec -e SYSBENCH_OPTS="$SYSBENCH_OPTS" sysbench${i} /bin/sh -c "/usr/local/share/sysbench/tpcc.lua $SYSBENCH_OPTS cleanup" &> ${OUTPUT_PATH}/${OUTPUT_PREFIX}cleanup.${i}.log &
        # Check for failure here, bail out and clean up
        pids[${i}-1]=$!
    done

    spin "${pids[0]}" &  # Start the spinner with the first process ID
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

    kill $spin_pid &> /dev/null

    enable_redo_log
    # Calculate the time to clean the database
    duration=$(calc_time_duration ${start_time})
    info_msg "MySQL Cleanup completed in ${duration}"

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Get the container logs
# args: none
# return: 0=success
function get_container_logs()
{
    info_msg "Collecting container logs..."

    for i in $(seq 1 ${PM_INSTANCES});
    do
        if podman logs mysql${i} &> ${OUTPUT_PATH}/${OUTPUT_PREFIX}mysql.${i}.log
        then
            info_msg "... Container 'mysql${i}' logs successfully written to '${OUTPUT_PATH}/${OUTPUT_PREFIX}mysql.${i}.log'"
        else
            error_msg " ... Failed to collect the container logs for mysql${i}"
        fi

        if podman logs sysbench${i} &> ${OUTPUT_PATH}/${OUTPUT_PREFIX}sysbench.${i}.log
        then
            info_msg "... Container 'sysbench${i}' logs successfully written to '${OUTPUT_PATH}/${OUTPUT_PREFIX}sysbench.${i}.log'"
        else
            error_msg " ... Failed to collect the container logs for sysbench${i}"
        fi
    done

    return 0 # We don't want to stop further processing on error
}

# Generate a snapshot of the MySQL settings and my.cnf
# args: none
# return: 0=success
function get_mysql_config()
{
    info_msg "Collecting 'my.cnf'"

    # Copy the my.cnf file to the output directory
    if cp ${MYSQL_CONF} ${OUTPUT_PATH}
    then
        info_msg "my.cnf collected successfully"
    else
        error_msg "Failed to copy '${MYSQL_CONF}' to '${OUTPUT_PATH}'"
    fi

    for i in $(seq 1 ${PM_INSTANCES});
    do
        # Dump the MySQL database variables
        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "SHOW GLOBAL VARIABLES;" &> ${OUTPUT_PATH}/mysql_global_variables.out
        then
            info_msg "MySQL Global Variables successfully written to '${OUTPUT_PATH}/mysql_global_variables.mysql${i}.out'"
        else
            error_msg "Failed to acquire the MySQL Global Variables."
        fi

        # Gather the total database size including all the tables
        if podman exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i mysql${i} mysql -uroot -e "SELECT table_schema 'Database Name', sum(data_length + index_length) / (1024 * 1024) 'Database Size in MB' FROM information_schema.TABLES WHERE table_schema = '${SysbenchDBName}' GROUP BY table_schema;" &> ${OUTPUT_PATH}/mysql_dbsize.out
        then
            info_msg "MySQL Database size successfully written to '${OUTPUT_PATH}/mysql_dbsize.mysql${i}.out'"
        else
            error_msg "Failed to acquire the MySQL database size."
        fi
    done

    # Collect the on-disk size of the MYSQL_DATA_DIR subdirectories
    # Chances are high that this du command will return 'permission denied' for some of the directories, so
    #  we don't need to use the typical logic here, otherwise we mis-represent that data is captured, but other
    #  errors existed. Instead, redirect STDOUT to the file and STDERR to the error file.
    du -h --max-depth=1 "${MYSQL_DATA_DIR}" &> "${OUTPUT_PATH}/du_-h.mysql_data_dir.out"

    return 0 # We don't want to stop further processing on error
}

# Stop the MySQL and Sysbench containers
# args: none
# return: 0=success, 1=error
function stop_containers()
{
    local err_state=false

    # Stop the container
    info_msg "Stopping the MySQL and SysBench containers..."
    for i in $(seq 1 ${PM_INSTANCES});
    do
        # Wait 20 seconds to stop the container; Larger databases take a bit of time to cleanup and stop
        if podman stop -t 20 mysql${i} &> /dev/null
        then
            info_msg "... Container 'mysql${i}' stopped successfully"
        else
            error_msg "... Container 'mysql${i}' failed to stop successfully. Verify podman killed the container."
            err_state=true
        fi

        if podman kill sysbench${i} &> /dev/null
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
    for i in $(seq 1 ${PM_INSTANCES});
    do
        # The sysbench containers are created on the fly, and are not retained after
        # the have been killed
        if podman rm mysql${i} &> /dev/null
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

# This function will check the user has the necessary permissions in the cgroups configuration
# args: none
# return: 0=success, 1=error
function check_cgroups()
{
    if [[ ! -f "/etc/systemd/system/user@.service.d/delegate.conf" ]]; then
        error_msg "The file '/etc/systemd/system/user@.service.d/delegate.conf' does not exist. Follow the procedure in the README.md for further instructions. Exiting"
        return 1
    fi

    if ! grep "cpu" /etc/systemd/system/user@.service.d/delegate.conf &> /dev/null; then
        error_msg  "This user does not have CPU cgroup priviledges! Follow the procedure in the README.md for further instructions. Exiting"
        return 1
    fi

    return 0
}

# Check if the MySQL data directory on host exists and is writable by this user
# args: none
# return: 0=success, 1=error
function check_mysql_data_dir()
{
    if [ -d "${MYSQL_DATA_DIR}" ];
    then
        if [ -w "${MYSQL_DATA_DIR}" ]; then
            info_msg "${MYSQL_DATA_DIR} exists and is writable by everyone"
            return 0
        else
            error_msg "${MYSQL_DATA_DIR} exists but is not writable by everyone. Please run 'sudo chmod 777 ${MYSQL_DATA_DIR}' to resolve this issue."
            return 1
        fi
    else
        error_msg "${MYSQL_DATA_DIR} does not exist or is not writable by everyone. Please create the '${MYSQL_DATA_DIR}' directory and retry. Exiting"
        return 1
    fi
}

# Check the MYSQL config directory that hosts the my.cnf exists before starting the container(s)
# args: none
# return: 0=success, 1=error
function check_my_cnf_dir_exists()
{
    if [ ! -f ${MYSQL_CONF} ];
    then
        error_msg " '${MYSQL_CONF}' does not exist. Please create the mysql configuration file and retry. Exiting"
        return 1
    else
        info_msg "'${MYSQL_CONF}' exists."
        return 0
    fi
}

# Calculate the time difference between two datetimes
# arg1: start time in seconds/epoch
# arg2: end time in seconds/epoch. If $2 is not provided, now() is used
# return: String with calculated difference in days, hours, mins, secs
function calc_time_duration()
{
    local STIME=$1      # Start Time
    local ETIME=$2      # End Time. Defaults to now() if not provided
    local DURATION=0    # ETIME-STIME
    local result=""     # Returned result

    if [[ -z "${STIME}" ]]; then
        return 1 # Error. Must supply the start time
    fi

    if [[ -z "${ETIME}" ]]; then
        ETIME=$(date +%s)
    fi

    DURATION=$((${ETIME}-${STIME}))

    # Convert seconds to days, hours, minutes, and seconds.
    # Only return the days, hours, and minutes if they are non-zero

    local days=$((DURATION / 86400))
    local hours=$(( (DURATION % 86400) / 3600 ))
    local minutes=$(( (DURATION % 3600) / 60 ))
    local seconds=$((DURATION % 60))

    if (( days > 0 )); then
        result+="${days} day(s), "
    fi

    if (( hours > 0 )); then
        result+="${hours} hour(s), "
    fi

    if (( minutes > 0 )); then
        result+="${minutes} minute(s), "
    fi

    if (( seconds > 0 )); then
        result+="${seconds} second(s)"
    fi

    echo "$result"
}

# Check if SELinux is installed and 'Enforcing' as this can cause the MySQL
#   initialization script inside the docker container to fail with permission
#   errors. Warn the user and have them temporarily disable it for the purposes
#   of benchmarking.
function check_selinux_enforce()
{
    if command -v getenforce > /dev/null || command -v sestatus > /dev/null; then
        if [ "$(getenforce)" == "Enforcing" ]; then
            error_msg "SELinux is in Enforcing mode. The database may have permission problems."
            error_msg "Run 'sudo setenforce 0' to temporarily disable SELinux to allow the benchmarks to work correctly."
            return 1
        else
            info_msg "SELinux is installed but not enabled"
        fi
    else
        info_msg "SELinux is not installed"
    fi

    return 0
}

# Check if Kernel Transparent Page Placement is Enabled or Disabled
# args: None
# return: True (1) or False (0)
function is_kernel_tpp_enabled()
{
    local numa_balancing=0
    local demotion_enabled=0
    local result=0

    # Check if Kernel Tiering exists and is enabled or disabled
    if [[ -f "/proc/sys/kernel/numa_balancing" ]];
    then
        numa_balancing=$(cat "/proc/sys/kernel/numa_balancing")

        case "${numa_balancing}" in
        0) # NUMA_BALANCING_DISABLED
            #info_msg "Kernel TPP is Disabled (NUMA_BALANCING_DISABLED)"
            result=0
            ;;
        1) # NUMA_BALANCING_NORMAL
            #info_msg "Kernel TPP is Disabled (NUMA_BALANCING_NORMAL)"
            result=0
            ;;
        2) # NUMA_BALANCING_MEMORY_TIERING
            #info_msg "Kernel TPP is Enabled (NUMA_BALANCING_MEMORY_TIERING)"
            result=1
            ;;
        *)
            #info_msg "Kernel TPP is Unknown (${numa_balancing})"
            result=0
            ;;
        esac
    else
        error_msg "'/proc/sys/kernel/numa_balancing' does not exist. Kernel doesn't support TPP"
        result=0
    fi

    # Check if Kernel page demotion exists and is enabled or disabled
    if [[ -f "/sys/kernel/mm/numa/demotion_enabled" ]];
    then
        demotion_enabled=$(cat "/sys/kernel/mm/numa/demotion_enabled")

        case "${demotion_enabled}" in
        0|"false") # Disabled
            #info_msg "Kernel TPP Page Demotion is Disabled"
            result=0
            ;;
        1|"true") # Enabled
            #info_msg "Kernel TPP Page Demotion is Enabled"
            result=1
            ;;
        *)
            #info_msg "Kernel TPP Page Demotion is Unknown (${demotion_enabled})"
            result=0
            ;;
        esac
    else
        error_msg "'/sys/kernel/mm/numa/demotion_enabled' does not exist. Kernel doesn't support TPP Page Demotion."
        result=0
    fi

    # Return True (1) or False (0)
    echo "$result"
}

# Enable the Kernel TPP feature. Must be root to do this!
# args: none
# returns: nothing
function enable_kernel_tpp()
{
    local err_state=false 

    if echo 2 > /proc/sys/kernel/numa_balancing;
    then
        error_msg "Failed to enable Kernel Memory Tiering. This Kernel may not support tiering."
        err_state=true
    else
        info_msg "Successfully enabled Kernel Memory Tiering"
        # Disable Kernel TPP after the benchmarks complete
        OPT_FUNCS_AFTER="disable_kernel_tpp"
    fi

    if echo 1 > /sys/kernel/mm/numa/demotion_enabled;
    then
        error_msg "Failed to enable Kernel Memory Tiering Page Demotion"
        err_state=true
    else
        info_msg "Successfully enabled Kernel Memory Tiering Page Demotion"
        # Disable Kernel TPP after the benchmarks complete
        OPT_FUNCS_AFTER="disable_kernel_tpp"
    fi

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Disable the Kernel TPP feature. Must be root to do this!
# args: none
# returns: nothing
function disable_kernel_tpp()
{
    local err_state=false 

    if echo 1 > /proc/sys/kernel/numa_balancing;
    then
        error_msg "Failed to enable Kernel Memory Tiering"
        err_state=true
    else
        info_msg "Successfully enabled Kernel Memory Tiering"
    fi

    if echo 0 > /sys/kernel/mm/numa/demotion_enabled;
    then
        error_msg "Failed to enable Kernel Memory Tiering Page Demotion"
        err_state=true
    else
        info_msg "Successfully enabled Kernel Memory Tiering Page Demotion"
    fi

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Check if the Kernel TPP feature is required or not.
# The user can explicityly use TPP with (-e kerneltpp)
# Kernel TPP should be disabled for all other tests
function kernel_tpp_feature()
{
    # Linux Kernel Transparent Page Placement (aka Tiering)
    # Debug statements
    if [[ ("$MEM_ENVIRONMENT" == "kerneltpp" || "$MEM_ENVIRONMENT" == "tpp") ]]
    then
        # TPP is disabled. If the user is root, try to auto-enable it. Otherwise tell the user to enable it manually
        if [[ $(is_kernel_tpp_enabled) -eq 0 ]] && [[ $EUID -ne 0 ]]; # User is not root, so we can't auto-enable TPP
        then
            error_msg "Please enable Linux Kernel Transparent Page Placement (TPP), then re-run this test. As root, run:"
            info_msg " $ sudo sh -c \"echo 2 > /proc/sys/kernel/numa_balancing\""
            info_msg " $ sudo sh -c \"echo 1 > /sys/kernel/mm/numa/demotion_enabled\""
            exit 1
        elif [[ $(is_kernel_tpp_enabled) -eq 0 ]] && [[ $EUID -eq 0 ]]; # User is root
        then
            enable_kernel_tpp
        elif [[ $(is_kernel_tpp_enabled) -eq 1 ]]; # TPP is enabled
        then
            info_msg "Kernel Transparent Page Placement is Enabled"
        else # Should not reach
            error_msg "An unknown memory environment setup has been detected that cannot be handled"
            error_msg "is_kernel_tpp_enabled returned '$(is_kernel_tpp_enabled)'"
            error_msg "EUID: $EUID"
        fi
    else # TPP should be disabled for all other memory test environments
        if [[ $(is_kernel_tpp_enabled) -eq 1 ]] && [[ $EUID -ne 0 ]]; # User is not root
        then
            error_msg "Kernel Transparent Page Placement (TPP) is Enabled. Please disable it"
            info_msg " $ sudo echo 1 > /proc/sys/kernel/numa_balancing"
            info_msg " $ sudo echo 0 > /sys/kernel/mm/numa/demotion_enabled"
        elif [[ $(is_kernel_tpp_enabled) -eq 1 ]] && [[ $EUID -eq 0 ]]; # User is root
        then
            disable_kernel_tpp
        elif [[ $(is_kernel_tpp_enabled) -eq 0 ]]; # TPP is disabled
        then
            info_msg "Kernel Transparent Page Placement (TPP) is Disabled"
        else # Should not reach
            error_msg "An unknown memory environment setup has been detected that cannot be handled"
            error_msg "is_kernel_tpp_enabled returned '$(is_kernel_tpp_enabled)'"
            error_msg "EUID: $EUID"
        fi
    fi
}

# Process the TPCC results to CSV files, one per MySQL container
# args: none
# returns: nothing
function process_tpcc_results_to_csv()
{
    cd "${OUTPUT_PATH}"
    for i in $(seq 1 ${PM_INSTANCES});
    do
        if ! ../utils/tpcc_results_to_csv.py *run_*.${i}.*; then
            error_msg "Failed to process the TPCC run results"
        else
            filename=$(basename "${file}")
            mv tpcc_results.csv "tpcc_results.${i}.${filename}.csv"
            info_msg "TPC-C run results for MySQL Instance ${i}: tpcc_results.${i}.csv"
        fi
    done
    cd ..
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

# Detect Terminal Type and setup message formats
auto_detect_terminal_colors

# Process the command line arguments
while getopts 'cC:D:E:e:?hi:M:o:prs:S:t:T:U:V:wW:X:' opt; do
    case "$opt" in
        ## Experiment Options
        e)
            MEM_ENVIRONMENT=${OPTARG}
            ;;
        i)
            PM_INSTANCES=${OPTARG}
            ;;
        o)
            OUTPUT_PREFIX=${OPTARG}
            ;;
        s)
            SCALE=${OPTARG}
            ;;
        t)
            TABLES=${OPTARG}
            ;;
        T)
            SYSBENCH_RUNTIME=${OPTARG}
            ;;
        W)
            SYSBENCH_THREADS=${OPTARG}

            # Validate SYSBENCH_THREADS is a valid integer
            if ! [[ $SYSBENCH_THREADS =~ ^[1-9][0-9]*$ ]]; then
                error_msg "Invalid value for '-W'. Please provide a valid integer value greater than or equal to 1."
                exit 1
            fi
            ;;
        ##  Run Options
        c)
            CLEANUP=1
            ;;
        p)
            PREPARE_DB=1
            ;;
        r)
            RUN_TEST=1
            ;;
        w)
            WARM_DB=1
            ;;
        ## Machine Configuration Options
        C)
            MYSQL_CPU_NUMA_NODE=${OPTARG}
            ;;
        D)
            SERVER_CPU_LIMIT=${OPTARG}
            # Validate SERVER_CPU_LIMIT is a valid integer
            if ! [[ $SERVER_CPU_LIMIT =~ ^[1-9][0-9]*$ ]]; then
                error_msg "Invalid value for '-D'. Please provide a valid integer value greater than or equal to 1."
                exit 1
            fi
            ;;
        E)
            SERVER_MEMORY_LIMIT=${OPTARG}
            # Validate SERVER_MEMORY_LIMIT is a valid integer
            if ! [[ $SERVER_MEMORY_LIMIT =~ ^[1-9][0-9]*$ ]]; then
                error_msg "Invalid value for '-E'. Please provide a valid integer value greater than or equal to 1."
                exit 1
            fi
            ## Convert the server memory limit into GB
            SERVER_MEMORY_LIMIT+=g
            ;;
        M)
            MYSQL_MEM_NUMA_NODE=${OPTARG}
            ;;
        S)
            SYSBENCH_NUMA_NODE=${OPTARG}
            ;;
        U)
            CLIENT_CPU_LIMIT=${OPTARG}
            # Validate SERVER_CPU_LIMIT is a valid integer
            if ! [[ $CLIENT_CPU_LIMIT =~ ^[1-9][0-9]*$ ]]; then
                error_msg "Invalid value for '-U'. Please provide a valid integer value greater than or equal to 1."
                exit 1
            fi
            ;;
        V)
            CLIENT_MEMORY_LIMIT=${OPTARG}
            # Validate SERVER_MEMORY_LIMIT is a valid integer
            if ! [[ $CLIENT_MEMORY_LIMIT =~ ^[1-9][0-9]*$ ]]; then
                error_msg "Invalid value for '-V'. Please provide a valid integer value greater than or equal to 1."
                exit 1
            fi
            ## Convert the server memory limit into GB
            CLIENT_MEMORY_LIMIT+=g
            ;;
        X)
            INNODB_BUFFER_POOL_SIZE=${OPTARG}
            # Validate SERVER_MEMORY_LIMIT is a valid integer
            if ! [[ $INNODB_BUFFER_POOL_SIZE =~ ^[1-9][0-9]*$ ]]; then
                error_msg "Invalid value for '-V'. Please provide a valid integer value greater than or equal to 1."
                exit 1
            fi
            ## Convert the server memory limit into GB
            INNODB_BUFFER_POOL_SIZE+=G
            ;;
        ## Misc Options
        h|\?|*)
            print_usage
            exit
            ;;
    esac
done

if [[ ( -z ${RUN_TEST} && -z ${PREPARE_DB} && -z ${CLEANUP} && -z ${WARM_DB}) ]];
then
    print_usage
    error_msg "One or both of -c or -r or -p options are needed to proceed"
    exit 1
fi

if [[ ("$MEM_ENVIRONMENT" != "numapreferred" && "$MEM_ENVIRONMENT" != "numainterleave" && "$MEM_ENVIRONMENT" != "mm" && "$MEM_ENVIRONMENT" != "dram" && "$MEM_ENVIRONMENT" != "cxl" && "$MEM_ENVIRONMENT" != "kerneltpp" && "$MEM_ENVIRONMENT" != "tpp") ]];
then
    error_msg "Unknown memory environment '${MEM_ENVIRONMENT}'"
    print_usage
    exit 1
else
    # Validate the user provided two or more NUMA nodes in the (-M) option for numactl options
    if [[ "$MEM_ENVIRONMENT" == "numainterleave" ]]
    then
        # Count the number of values separated by commas
        IFS=',' read -ra NUMA_NODES <<< "$MYSQL_MEM_NUMA_NODE"
        NUM_NODE_COUNT=${#NUMA_NODES[@]}

        # Check if the variable has two or more values separated by commas
        if [[ $NUM_NODE_COUNT -lt 2 ]]; then
            error_msg "Two or more NUMA node must be specified with (-M) with the '${MEM_ENVIRONMENT}' (-e) option"
            print_usage
            exit 1
        fi
    elif [[ "$MEM_ENVIRONMENT" == "numapreferred" ]]
    then
        # Check if the value is a single integer
        if ! [[ "$MYSQL_MEM_NUMA_NODE" =~ ^[0-9]+$ ]]; then
	    error_msg "A single NUMA node must be specified with (-M) when using the '${MEM_ENVIRONMENT}' (-e) option"
            print_usage
            exit 1
        fi
    fi
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

# Check if the user provided a prefix/test name, and use it
if [ -z ${OUTPUT_PREFIX} ];
then
    OUTPUT_PREFIX=""
else
    # Set the OUTPUT_PREFIX for files
    OUTPUT_PREFIX+="_"
    # Set the OUTPUT_PATH
    OUTPUT_PATH="./${OUTPUT_PREFIX}${SCRIPT_NAME}.`hostname`.`date +"%m%d-%H%M"`"
fi

# Verify the mandatory commands and utilities are installed. Exit on error.
if ! verify_cmds
then
    exit
fi

# Initialize the environment
init

# Save STDOUT and STDERR logs to the data collection directory
log_stdout_stderr "${OUTPUT_PATH}"

# Display the header information
display_start_info "$*"

# Define the array of functions to call in the correct order
functions=("check_selinux_enforce" "check_mysql_data_dir" "check_cgroups" "create_network" "set_numactl_options" "kernel_tpp_feature")

# Add functions from OPT_FUNCS_BEFORE if it is set
if [ -n "$OPT_FUNCS_BEFORE" ]; then
    functions+=("$OPT_FUNCS_BEFORE")
fi

# Add remaining functions
functions+=("create_sysbench_container_image" "start_sysbench_containers" "check_my_cnf_dir_exists" "start_mysql_containers" "pause_for_stability" "create_mysql_databases" "prepare_the_database" "get_mysql_config" "warm_the_database" "run_the_benchmark" "cleanup_database" "get_container_logs" "stop_containers" "remove_containers" "process_tpcc_results_to_csv")

# Add functions from OPT_FUNCS_AFTER if it is set
if [ -n "$OPT_FUNCS_AFTER" ]; then
    functions+=("$OPT_FUNCS_AFTER")
fi

# Iterate over the array of functions and call them one by one
# Handle the return value: 0=Success, 1=Failure
for function in "${functions[@]}"; do
    # Call the function and store the return value
    "$function"
    return_value=$?

    # Check if an error occurred
    if [ $return_value -ne 0 ]; then
        error_msg "An error occurred in '$function'. Exiting."
        break
    fi
done

# Fatal Errors will jump here without further processing
#out:#

# Get the container logs
# TODO: Get the logs on error. The get_container_logs() will collect this data during a normal run.
# get_container_logs

# Display the end header information
display_end_info
