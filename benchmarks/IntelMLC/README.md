# Intel Memory Latency Checker (MLC)

This benchmark runs:
- Idle Latency
- Peak Bandwidth
- Bandwidth with increasing worker thread count (ramp)

```
# ./mlc.sh -?
 
Usage: ./mlc.sh -c <CXL NUMA Node ID> -d <DRAM NUMA Node ID> [optional args]
 
Runs bandwidth and latency tests on DRAM and CXL Type 3 Memory using Intel MLC
Run with root privilege (MLC needs it)
 
Optional args:
 
   -c <CXL NUMA Node>
      Required. Specify the NUMA Node backed by CXL for testing
 
   -d <DRAM NUMA Node>
      Required. Specify the NUMA Node backed by DRAM for testing
 
   -m <Path to MLC executable>
      Specify the path to the MLC executable
 
   -s <Socket>
      Specify which CPU socket should be used for running mlc
      By default, CPU Socket 0 is used to run mlc
 
   -v
      Print verbose output. Use -v, -vv, and -vvv to increase verbosity.
 
   -X
      For bandwidth tests, mlc will use all cpu threads on each Hyperthread enabled core.
      Use this option to use only one thread on the core
 
   -Z <Specify whether to enable or disable the AVX_512 option>
      Values:
        0: AVX_512 Option Disabled
        1: AVX_512 Option Enabled - Default
      By default, the AVX_512 option is enabled. If the non-AVX512
      version of MLC is being used, this option shall be set to 0
```
