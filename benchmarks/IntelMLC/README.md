# Intel Memory Latency Checker (MLC)

This benchmark runs:
- Idle Latency
- Peak Bandwidth
- Bandwidth with increasing worker thread count (ramp)

## Usage

```
# ./mlc.sh -?
 
Usage: ./mlc.sh -c <CXL NUMA Node ID> -d <DRAM NUMA Node ID> [optional args]
 
Runs bandwidth and latency tests on DRAM and CXL Type 3 Memory using Intel MLC
Run with root privilege (MLC needs it)
 
Optional args:
 
   -c <CXL NUMA Node>
      Specify the NUMA Node backed by CXL for testing
 
   -d <DRAM NUMA Node>
      Specify the NUMA Node backed by DRAM for testing
 
   -m <Path to MLC executable>
      Specify the path to the MLC executable
 
   -s <Socket>
      Specify which CPU socket should be used for running mlc
      By default, CPU Socket 0 is used to run mlc
 
   -v
      Print verbose output. Use -v, -vv, and -vvv to increase verbosity.
```

### Examples

**Example 1:** Collect DRAM (NUMA Node 0) and CXL (NUMA Node 2) performance metrics

```bash
$ sudo ./mlc.sh -d 0 -c 2 -m ./mlc
```

**Example 2:** Collect metrics for DRAM (NUMA Node 0) only 

```bash
$ sudo ./mlc.sh -d 0 -m ./mlc
```

**Example 3:** Collect metrics for CXL (NUMA Node 2) only 

```bash
$ sudo ./mlc.sh -c 2 -m ./mlc
```

## Processing the results

Each test run generates a new directory in the format of "<script name>.<hostname>.<date-time>". Inside this directory are individual result files.
The `mlc.sh.log` is a capture of STDOUT and STDERR.

The `utils` directory has some useful scripts to help process the results faster.

```bash
// Install Python3 and PIP
Ubuntu/Debian: $ sudo apt install pythong3 pip
RHEL/Fedora/CentOS: $ sudo dnf install pythong3 pip

// Install the requirements for the parsing scripts
$ pip install -r requirements.txt

// Generate the Excel Document
// usage: gen_excel.py [-h] Directory ExcelFile
// Inside a data directory, run:
$ python3 ../utils/gen_excel.py . mlc.results.xlsx

// Generate the bandwidth and latency charts
// usage: gen_plot.py [-h] -d DIRECTORY -r {w21,w23,w27} -t {seq,rand}
// Inside a results directory, run:
$ python3 ../utils/gen_plot.py -d . -r w21 -t seq
$ python3 ../utils/gen_plot.py -d . -r w21 -t rand

$ python3 ../utils/gen_plot.py -d . -r w23 -t seq
$ python3 ../utils/gen_plot.py -d . -r w21 -t rand

$ python3 ../utils/gen_plot.py -d . -r w27 -t seq
$ python3 ../utils/gen_plot.py -d . -r w27 -t seq
```