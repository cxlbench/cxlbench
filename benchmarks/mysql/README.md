# sysbench-tpcc
This benchmark uses the [Sysbench](https://github.com/akopytov/sysbench/) tool with the [Percona TPCC LUA scripts](https://github.com/Percona-Lab/sysbench-tpcc). The sysbench-tpcc.sh script uses Podman to orchastrate a single or multi tennant cloud-like environment.

The script does not require root priviledges to execute as Podman allows us to run everything as a non-root user. However, there are optional OS tuning that does require root. 

## Usage

```bash
sysbench-tpcc.sh: Usage
    sysbench-tpcc.sh [-o output_prefix] [-p] [-r]
      -c                         : Cleanup. Completely remove all containers and the MySQL database
      -C <numa_node>             : [Required] CPU NUMA Node to run the MySQLServer
      -e dram|interleave         : [Required] Type of experiment to run
      -i <number_of_instances>   : The number of container intances to execute: Default 1
      -r                         : Run the Sysbench workload
      -p                         : Prepare the database
      -M <numa_node,..>          : [Required] Memory NUMA Node(s) to run the MySQLServer
      -o <prefix>                : [Required] prefix of the output files: Default 'test'
      -s <scale>                 : Number of warehouses (scale): Default 10
      -S <numa_node>             : [Required] NUMA Node to run the Sysbench workers
      -t <number_of_tables>      : The number of tables per warehouse: Default 10
      -w                         : Warm the database before running tests
      -h                         : Print this message
 
Example 1: Runs a single MySQL server on NUMA 0 and a single SysBench instance on NUMA Node1, 
  prepares the database, runs the benchmark, and removes the database and containers when complete.
 
    $ ./sysbench-tpcc.sh -c -C 0 -e dram -i 1 -r -p -M 0 -o test -S1 -t 10 -w
 
Example 2: Created the MySQL and Sysbench containers, runs the MySQL container on NUMA Node 0, the 
  Sysbench container on NUMA Node 1, then prepares the database and exits. The containers are left running.
 
    $ ./sysbench-tpcc.sh -C 0 -e dram -M0 -o test -S 1  -p
```

## Sysbench Tuning & Configuration
Most of the common options are exposed via the command line arguments. The default environment downloads and compiles the latest sysbench version using a multi-stage `Dockerfile`. The release version of sysbench does not have the `--warmup` option, so we muct compile it to ascertain this feature. Each sysbench container uses 4 vCPUs and 1GiB of memory. To change this, edit the sysbench-tpcc.sh script and modify the `CLIENT_CPU_LIMIT` and `CLIENT_MEMORY_LIMIT` variables. 

Sysbench and the `sysbench-tpcc.sh` script have many more options that can be modified inside the script itself. Edit the `sysbench-tpcc.sh` script and change the parameters shown in the top of the script inside the "Variables" section.

```bash
# ==== Podman Variables ====

# Podman network name
NETWORK_NAME=mysqlsysbench

# Container CPU and memory limits for the MySQL server and the Sysbench client
# Note: The MySQL (server) values should be configured for the size of the test database. The OOM killer will stop the database if too few resources are assigned.
CLIENT_CPU_LIMIT=4  								# Number of vCPUs to give to the Sysbench container
CLIENT_MEMORY_LIMIT=1g  							# Amount of memory (GiB) to give to the Sysbench container
SERVER_CPU_LIMIT=4  								# Number of vCPUs to give to the MySQL container
SERVER_MEMORY_LIMIT=16g  							# Amount of memory (GiB) to give to the Sysbench container

# === MySQL Variables ===
MYSQL_ROOT_PASSWORD=my-secret-pw  					# Root Users Password
MYSQL_START_PORT=3333  								# Host Port number for the first instance. Additional instances will increment by 1 for each instance 3306..3307..3308..
MYSQL_DATA_DIR=/data 								# Base directory for the MySQL Data Directory on the host
MYSQL_CONF=${SCRIPT_DIR}/my.cnf.d/my.cnf  			# Location of the my.cnf file the MySQL server will use
MySQLDockerImgTag="docker.io/library/mysql:latest"  # MySQL Version. Get the Docker Tag ID from https://hub.docker.com/_/mysql

# === Sysbench Variables ===

# Sysbench username and password
SYSBENCH_USER="sbuser"
SYSBENCH_USER_PASSWORD="sbuser-pwd"
SCALE=1  									# Default number of warehouses (scale value)
TABLES=10  									# Default number of tables per warehouse. Use -t to override.
SYSBENCH_CONTAINER_IMG_NAME="sysbenchmysql" # Sysbench container image name
SysbenchDBName="sbtest"  					# Name of the MySQL Database to create and run Sysbench against
```

## MySQL Tuning & Configuration
When the MySQL container starts, it uses the configuration options defined in `my.cnf.d/my.cnf`. You are free to modify this file to add or remove entries as needed. All MySQL containers use the same configuration file.

The default configuration creates a 10GB database running on 4 vCPUs with 16GB RAM. If you change the database size, by altering the SCALE or number of TABLES, you will need to calculate the new CPU and Memory requirements, then modify the SERVER_CPU_LIMIT and SERVER_MEMORY_LIMIT variables inside the script to avoid the Kernel OOM killer stopping the MySQL database instance. 

## OS Tuning & Configuration
Each environment and test requires different tuning. You can tune the host OS as needed. Here are some suggested things to do before running each test.

### Page Cache
We can drop the page cache by issuing a `sync` operation, then writing an appropriate number to the  `/proc/sys/vm/drop_caches` file. 

A value of one (1) will ask the kernel to drop only the page cache:

```bash
$ sync; echo 1 | sudo tee /proc/sys/vm/drop_caches > /dev/null
```

Writing two (2) frees dentries and inodes:

```bash
$ sync; echo 2 | sudo tee /proc/sys/vm/drop_caches > /dev/null
```

Finally, passing three (3) results in emptying everything — page cache, cached dentries, and inodes:

```bash
$ sync; echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
```

### CPU Frequency Govenor 

The majority of modern processors are capable of operating in a number of different clock frequency and voltage configurations. The Linux kernel supports CPU performance scaling by means of the `CPUFreq` (CPU Frequency scaling) subsystem that consists of three layers of code: the core, scaling governors and scaling drivers. For benchmarking, we usually want maximum performance and power. By default, most Linux distributions place the system into a ‘powersave’ mode. The definition for ‘powersave’ and ‘performance’ scaling governors are:

**performance**

When attached to a policy object, this governor causes the highest frequency, within the `scaling_max_freq` policy limit, to be requested for that policy.

The request is made once at that time the governor for the policy is set to `performance` and whenever the `scaling_max_freq` or `scaling_min_freq` policy limits change after that.

**powersave**

When attached to a policy object, this governor causes the lowest frequency, within the `scaling_min_freq` policy limit, to be requested for that policy.

The request is made once at that time the governor for the policy is set to `powersave` and whenever the `scaling_max_freq` or `scaling_min_freq` policy limits change after that.

You can read more details about the  `CPUFreq`  Linux feature and configuration options in the  [Kernel Documentation](https://www.kernel.org/doc/html/latest/admin-guide/pm/cpufreq.html) .

Check the current mode:

```bash
$ sudo cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
powersave
powersave
powersave
powersave
[...snip...]
```

Switch to the ‘performance’ mode:

```bash
$ echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

Ensure the CPU scaling governor is in performance mode by checking the following; here you will see the setting from each processor (vcpu).

```bash
$ sudo cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
performance
performance
performance
performance
[...snip...]
```