# STREAM

This modified version of the STREAM benchmarking tool measures the memory bandwidth of numa nodes. The original source code can be found [here](https://www.cs.virginia.edu/stream/FTP/Code/).

# Setup

This benchmarking tool for measuring memory bandwidth requires  for the `numactl` command along with the `numa.h` header.

The `numactl` command and `numa.h` header are required for this benchmark to run. The Debian verison of the package that provides both is [`libnuma-dev`](https://manpages.debian.org/buster/libnuma-dev/numa.3.en.html).

# Usage

## Compiling

- Debug, sanitizers, no optimization: `make debug_stream_c.exe`
- Optimization level 3: `make stream_c.exe`

## Running

### Command information

```bash
$ ./stream_c.exe --help
STREAM Benchmark
         --ntimes, -t <integer-value>                         : Number of times to run benchmark: Default 10
     --array-size, -a <integer-value>|<integer-value><K|M|G>  : Size of numa node arrays: Default 1000000
         --offset, -o <integer-value>                         : Change relative alignment of arrays: Default 0
     --numa-nodes, -n <integer>,<integer>|<integer>           : [Required] Numa node(s) to do calculations on
--auto-array-size, -s                                         : Array will be socket's L3 cache divided by 2
           --help, -h                                         : Print this message
```

### Memory combinations

Get the indices of your numa nodes via the [`lscpu`](https://www.man7.org/linux/man-pages/man1/lscpu.1.html) command. An example being the following:

```
NUMA:
  NUMA node(s):          3
  NUMA node0 CPU(s):     0-31,64-95
  NUMA node1 CPU(s):     32-63,96-127
  NUMA node2 CPU(s):
```

The nodes with CPUs are DRAM (node0, node1), while the one without any CPUs (node2) is CXL.

#### DRAM Only

```bash
$ numactl --cpunodebind=0 --membind=0,1 ./stream_c.exe --numa-nodes 0,1 --auto-array-size
```

#### CXL Only

```bash
$ numactl --cpunodebind=0 --membind=2 ./stream_c.exe --numa-nodes 2 --auto-array-size
```

#### DRAM + CXL

```bash
$ numactl --cpunodebind=0 --membind=0,2 ./stream_c.exe --numa-nodes 0,2 --auto-array-size
```
