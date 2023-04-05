#!/usr/bin/env bash

source ../../lib/common
source ../../lib/debug

# Podman Variables
MySQLDockerImgTag="docker.io/library/mysql:8.0.32"    # MySQL Version. Get the Docker Tag ID from https://hub.docker.com/_/mysql
MYSQL_DATA_DIR=/data                # Base directory for the MySQL Data Directory
                                    # Data directories will be created under this directory for each database instance
NumOfPodmanInstances=1              # Change the number of database instances to start     
CPUSet_Mem=0                        # Memory NUMA Nodes to use for the database(s), eg: 0 or 0,1
CPUSet_CPUs=0                       # CPU's or range to use for the database(s), eg: 0-32 or 0,1,2,3
MemoryCapacity=0                    # 0 = No limit. Otherwise a memory limit with unit can be b (bytes), k (kibibytes), m (mebibytes), or g (gibibytes)

# MySQL Variables
MySQLRootPassword="my-secret-pwd"   # Root Users Password
MySQLStartPort=3306                 # Host Port number for the first instance. Additional instances will increment by 1 for each instance 3306..3307..3308..
MySQLDBName="sbtest"                # Sets env variable MYSQL_DATABASE. It should match 'SysbenchDBName'.
MySQLUser="sbuser"                  # Sets env variable MYSQL_USER. 
MySQLUserPassword="sbuser-pwd"      # Sets env variable MYSQL_PASSWORD.
MySQLConfigFile="${MYSQL_DATA_DIR}/my.cnf"  # Path to a 'my.cnf' file that contains 'mysql' and 'mysqld' config options. This will be shared across all database instances read-only

# Sysbench Variables
SysbenchLUAScriptPath="./sysbench-tpcc"    # Path to where the Percona Sysbench Scripts are located
SysbenchDBName=$MySQLDBName         # Test Database Name
SysbenchScale=1                     # Number of Warehouses
SysbenchNumTables=1                 # Number of Table Sets to create      
SysbenchMemNUMANodes=1              # Memory NUMA Nodes to use for sysbench
SysbenchCpuNUMANodes=1              # CPU NUMA Nodes to use for sysbench
SysbenchWarmupDuration=300          # Number of seconds to warm up the DB before starting each benchmark run. This can be a shorter time since the caches and page cache should be warm. Note: The --warm-up option is only available if you build sysbench from source. It is not available in production releases.
SysbenchRunDuration=60              # Number of seconds to run the sysbench workload
#SysBenchNumThreads="1 2 4 8 16 32 64 72 80 88 96 104 112 120 128 136 144" # A list of threads/client connections. Each one will be tested.
SysBenchNumThreads="1 2 4"          # A list of threads/client connections. Each one will be tested.
SysbenchReportPercentile=99         # Report the P99 latency, use 95 to report P95 latencies
SysbenchIterations=3                # Run each benchmark N times so averages and outliers can be removed

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

# Get the system information
function get_sysinfo() {
    get_num_sockets
    get_num_cores_per_socket
    get_first_cpu_on_socket
    check_hyperthreading
    get_memory_per_numa_node
}

# Verify the required commands and utilities exist on the system
# We use either the defaults or user specified paths
function verify_cmds() {
    local err_state=false

    for CMD in numactl lscpu lspci grep cut bc awk nc podman; do
        CMD_PATH=($(command -v ${CMD}))
        if [ ! -x "${CMD_PATH}" ]; then
            echo "ERROR: ${CMD} command not found! Please install the ${CMD} package."
            err_state=true
        fi
    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Create the database data directories
# under the MYSQL_DATA_DIR
function create_db_data_dirs() {
    local err_state=false

    for i in $(seq 1 $NumOfPodmanInstances)
    do
        if mkdir -p "${MYSQL_DATA_DIR}/mysql-${i}"
        then
            echo "create_db_data_dirs: INFO: Created '${MYSQL_DATA_DIR}/mysql-${i}' successfully"
        else
            echo "create_db_data_dirs: ERROR: Error creating '${MYSQL_DATA_DIR}/mysql-${i}'"
            err_state=true
        fi
    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Generate the my.cnf if one doesn't exist
# We try to calculate values based on the host's hardware 
function create_my_cnf() {
    local err_state=false
    if [ ! -f "${MySQLConfigFile}" ]
    then
        touch "${MySQLConfigFile}"
        # TODO: Generate the rest of the file content
    fi

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Check if MySQL, or any other process, is using Ports 3306 through 
function check_mysql_running() {
    local err_state=false
    local max_port_num=$(( (MySQLStartPort - 1) + NumOfPodmanInstances ))

    for port in $(seq $MySQLStartPort $max_port_num)
    do
        if nc -z localhost 3306 >/dev/null 2>&1; then
            echo "WARN: MySQL is running on port $port! You must stop all MySQL instances or select a new port range."
            err_state=true
        fi
    done

    if ${err_state}; then
        return 1
    else
        echo "No running MySQL instances found on ports $MySQLStartPort - $max_port_num"
        return 0
    fi
}

# Start the requested number of database instances under Podman Control
function pm_start_databases() {
    local err_state=false

    echo "pm_start_databases: Starting podman database instances..."
    # Start the database instances
    for i in $(seq 1 $NumOfPodmanInstances)
    do
        port=$(( (MySQLStartPort - 1) + i ))
        
        # Check if the container exists. If not, create it.
        if ! podman inspect "mysql-$i" >/dev/null 2>&1 
        then
            echo "pm_start_databases: INFO: MySQL instance 'mysql-$i' does not exist. Creating it..."
            # Create the container and start it
            # The Database and non-root MySQL user will be created automatically
            echo "pm_start_databases: INFO: Creating & starting MySQL instance $i on host port $port and container port 3306 ..."
            if podman run --detach \
                --name "mysql-$i" \
                --env MYSQL_ROOT_PASSWORD="${MySQLRootPassword}" \
                --env MYSQL_DATABASE="${MySQLDBName}" \
                --env MYSQL_USER="${MySQLUser}" \
                --env MYSQL_PASSWORD="${MySQLUserPassword}" \
                -p $port:3306 \
                --volume "${MYSQL_DATA_DIR}/mysql-${i}":/var/lib/mysql \
                --volume "${MySQLConfigFile}":/etc/mysql/my.cnf:ro \
                --cpuset-cpus="${CPUSet_CPUs}" \
                --cpuset-mems="${CPUSet_Mem}" \
                "${MySQLDockerImgTag}"
            then
                echo "pm_start_databases: INFO: MySQL instance $i started successfully."
            else 
                echo "pm_start_databases: ERROR: Error starting MySQL instance $i:"
                podman logs "mysql-$i"
                err_state=true
            fi 
        else
            # Start the container if it's stopped
            if [[ $(podman inspect --format "{{.State.Running}}" "mysql-$i") == false ]]
            then
                echo "pm_start_databases: INFO: Starting stopped instance 'mysql-$i' ..."
                if podman start "mysql-$i" >/dev/null; then
                    echo "pm_start_databases: INFO: MySQL instance $i started successfully."
                else
                    echo "pm_start_databases: ERROR: Error starting MySQL instance $i:"
                    podman logs "mysql-$i"
                    err_state=true
                fi
            else
                echo "pm_start_databases: INFO: MySQL instance $i is already running."
            fi
        fi           
    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Wait for the MySQL to start within the Podman instance 
function pm_check_mysql_ready() {
    local err_state=false
    local counter=0

    while [[ $counter -lt 10 ]]
    do
        # Dump the Podman logs to a file
        podman logs mysql-1 > "${MYSQL_DATA_DIR}/podman-logs-mysql-1.log" 2>&1 
        if grep --quiet "ready for connections" "${MYSQL_DATA_DIR}/podman-logs-mysql-1.log"
        then
            echo "pm_check_mysql_ready: INFO: MySQL is ready for connections. Sleeping for 10 seconds before proceeding to be safe..."
            sleep 10
            break
        else
            echo "pm_check_mysql_ready: INFO: MySQL is not ready yet. Will try again in 5 seconds."
            sleep 5
            ((counter++))
        fi
    done 

    if [[ $counter -ge 10 ]]
    then
        echo "pm_check_mysql_ready: ERROR: Exceeded maximum number of attempts"
        err_state=true
    fi 

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Stop all database instances
function pm_stop_databases() {
    local err_state=false

    # Stop all 'mysql-*' Podman instances and forcibly kill if not stopped after 120 seconds
    for i in $(seq 1 $NumOfPodmanInstances)
    do
        echo "Stopping MySQL instance $i..."
        if podman stop "mysql-$i" --time 120 >/dev/null
        then
            echo "MySQL instance $i stopped successfully."
        else
            echo "Error stopping MySQL instance $i:"
            podman logs "mysql-$i"
            err_state=true
        fi
    done

    if ${err_state}; then
        return 1
    else
        echo "All MySQL instances stopped."
        return 0
    fi
}

# Duplicate a Podman Instance
function pm_duplicate_instance() {
    local err_state=false
    local pm_source="mysql-1"

    # TODO: When duplicating the instance, make sure we don't fill the filesystem to 100%

    # Stop the source Podman Instance
    if podman stop ${pm_source} --time 120 >/dev/null
    then
        echo "Podman '${pm_source}' stopped successfully."
    else
        echo "Error stopping podman instance '${pm_source}'."
        return 1
    fi

    # Create a new container image (mysql_duplicate) from the existing container (mysql-1), 
    #   with the --pause option to pause the container during the commit process
    if podman commit --pause ${pm_source} mysql_duplicate
    then
        echo "Successfully created the new podman image 'mysql_duplicate'"
    else
        echo "Failed to create the podman image 'mysql_duplicate' from '${pm_source}'"
        return 1
    fi

    # Begin duplication
    for i in $(seq 2 $NumOfPodmanInstances)
    do
        port=$(( (MySQLStartPort - 1) + i ))

        # Create a new container from the new image (mysql_duplicate), with the --volumes option to create a new volume for the MySQL data
        podman create --name "mysql-${i}" \
        --env MYSQL_ROOT_PASSWORD="${MySQLRootPassword}" \
        --env MYSQL_DATABASE="${MySQLDBName}" \
        --env MYSQL_USER="${MySQLUser}" \
        --env MYSQL_PASSWORD="${MySQLUserPassword}" \
        -p $port:3306 \
        --volume "${MYSQL_DATA_DIR}/mysql-${i}":/var/lib/mysql \
        --volume "${MySQLConfigFile}":/etc/mysql/my.cnf:ro \
        --cpuset-cpus="${CPUSet_CPUs}" \
        --cpuset-mems="${CPUSet_Mem}" \
        mysql_duplicate

        # Start all instances
        if podman start "mysql-${i}"
        then
            echo "Podman instance 'mysql-${i}' started successfully"
        else
            echo "Podman instance 'mysql-${i} failed to start successfully"
            podman logs "mysql-${i}"
            err_state=true
        fi
    done

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Cleanup all Podman Instances
function pm_cleanup() {
    local err_state=false

    for i in $(seq 1 $NumOfPodmanInstances)
    do
        if podman rm "mysql-$i"
        then
            echo "Podman instance 'mysql-$i' removed successfully"
        else
            echo "Error removing podman instance 'mysql-$i'. See previous error(s)."
            err_state=true
        fi

        # Remove the MySQL Data Directory
        rm -rf "/data/mysql-$i" >/dev/null 2>&1
    done 

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Create the database content (prepare operation)
function sb_prepare_dbs() {
    local err_state=false

    # If the first database directory does not exist, create it
    if [ ! -d "${MYSQL_DATA_DIR}/mysql-1" ]
    then
        # Directory does not exist, so create it
        create_db_data_dirs
    fi

    # Check to see if the MySQL Data Directory already contains a database (it should have been created when the podman instance started)
    if [ -d "${MYSQL_DATA_DIR}/mysql-1/${MySQLDBName}" ]
    then
        # Database Directory exists
        if [[ $(ls -A "${MYSQL_DATA_DIR}/mysql-1/${MySQLDBName}") ]]
        then
            # Database Directory is not empty
            echo "sb_prepare_dbs: Directory ${MYSQL_DATA_DIR}/mysql-1 appears to contain a '${MySQLDBName}' database. No further action required."
        else
            # Directory exists and is empty. This is good!
            # Prepare the first MySQL Database
            echo "sb_prepare_dbs: Using sysbench to prepare the first database contents. This will take some time. Please be patient."
            
            # Verify the 'tpcc.lua' script can be found
            if [[ -f  "${SysbenchLUAScriptPath}/tpcc.lua" ]]
            then
                # TIP: Don't use 'localhost' as it caused mysql to use the mysql.sock interface. By using '127.0.0.1' we force mysql to connect via TCP.
                # Run the tpcc.lua in a subshell
                (cd "${SysbenchLUAScriptPath}" && ./tpcc.lua \
                    --mysql-db="${MySQLDBName}" \
                    --mysql-user="${MySQLUser}" \
                    --mysql-password="${MySQLUserPassword}" \
                    --mysql-host="127.0.0.1" \
                    --mysql-port="${MySQLStartPort}" \
                    --threads=1 \
                    --tables="${SysbenchNumTables}" \
                    --scale="${SysbenchScale}" \
                    --report-interval=10 \
                    --db-driver=mysql \
                    prepare)
            else
                echo "sb_prepare_dbs: Error! '${SysbenchLUAScriptPath}/tpcc.lua': No such file or directory!"
                err_state=true
            fi
        fi
    else
        echo "Database directory ${MYSQL_DATA_DIR}/mysql-1/${MySQLDBName} does not exist! Something went wrong during the podman initialization. Run 'podman rm mysql-1' and try again."
        err_state=true
    fi

    if ${err_state}; then
        return 1
    else
        return 0
    fi
}

# Run the sysbench tpc-c test against the running databases using the CPU and Mem bindings
function sb_run(){
    for t in ${SysBenchNumThreads}
    do
        echo "Running sysbench..."
        # Run the command in a subshell so we don't lose our directory
        (cd "${SysbenchLUAScriptPath}" && numactl --cpunodebind "${SysbenchCpuNUMANodes}" --membind="${SysbenchMemNUMANodes}" ./tpcc.lua \
            --mysql-db="${MySQLDBName}" \
            --mysql-user="${MySQLUser}" \
            --mysql-password="${MySQLUserPassword}" \
            --mysql-host="127.0.0.1" \
            --mysql-port="${MySQLStartPort}" \
            --threads="${t}" \
            --tables="${SysbenchNumTables}" \
            --scale="${SysbenchScale}" \
            --time="${SysbenchRunDuration}" \
            --db-driver=mysql \
            run > ../"${OUTPUT_PATH}/sysbench_run.${t}-threads.out")
    done
}

# Perform OS Tuning and Optimization
function os_tune() {
    # Clear the OS Page Cache
    clear_page_cache

    # Set the CPU Frequency Governor to 'Performance'
    debug_msg "Setting CPU Frequency Govenor to 'performance'"
    echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
}

#################################################################################################
# Main
#################################################################################################

# Verify this script is executed as the root user
if [ "$EUID" -ne 0 ]
then 
    echo "This script needs to be executed as root"
    exit
fi

# TODO:
# 1. Implement return values in the functions and check them when calling
# 2. Implement command line arguments to allow the user to override some of the options in this script

# Verify the mandatory commands and utilities are installed. Exit on error.
if ! verify_cmds
then
    exit 1
fi

# Initialize the environment
init

# Save STDOUT and STDERR logs to the data collection directory
log_stdout_stderr "${OUTPUT_PATH}"

# Display the header information
display_start_info

# Get the system info
get_sysinfo

# Tune the Operating System
os_tune

# Create the database data directories
if ! create_db_data_dirs
then
    goto out
fi

# Create the MySQL config file
if ! create_my_cnf
then
    goto out
fi

# Check to see if any running MySQL processes are using the por range we need
if ! check_mysql_running
then
    goto out
fi    

# Start the Podman instances/Databases
if ! pm_start_databases 
then
    goto out_cleanup
fi

# Wait for the MySQL Database inside the Podman instance to become ready and accept connections
if ! pm_check_mysql_ready
then
    goto out_cleanup
fi

# Prepare the database content
if ! sb_prepare_dbs
then
    goto out_cleanup
fi

# If we have more than one DB instance, duplicate the first podman instance including the MySQL data
if [[ NumOfPodmanInstances -gt 1 ]]
then
    if ! pm_duplicate_instance
    then
        goto out_cleanup
    fi
fi

# Start performance metrics data collection 

# Run the SysBench TPCC.LUA
# TODO:
# 1. Ramp up the number of clients/threads
# 2. Test DRAM-only, CXL-only, numactl --interleave, numactl --preferred, Kernel TPP, and Memory Machine Tiering
sb_run

# Stop performance metrics data collection 

#out_cleanup:#

# Stop the Podman instances/Databases
# read -rp "Press Enter to continue" </dev/tty
if ! pm_stop_databases
then
    goto out
fi

# Cleanup and remove MySQL Data
pm_cleanup

#out:#

# Zip the output directory
# TODO

# Display the end header information
display_end_info