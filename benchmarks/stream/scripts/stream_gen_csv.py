import argparse
import subprocess

ARRAY_SIZES: list[int] = [
    10_000_000,
    # 50_000_000,
    # 100_000_000,
    # 200_000_000,
    # 300_000_000,
    # 400_000_000,
    # 430_0080_000,
]

THREADS: list[int] = [
    4,
    # 8,
    # 16,
    # 32,
    # 64
]


def format_stream_output(s: str) -> str:
    return s.splitlines()


def run_cmd(cmd: str) -> str:
    returned_output = subprocess.check_output(cmd, shell=True)

    return returned_output

# Example (while cd'd into this directory):
# python3 stream_gen_csv.py ../stream_c.exe --numa-nodes 0
def main() -> None:
    parser = argparse.ArgumentParser(description="STREAM benchmarking tool runner")

    parser.add_argument(
        "binary_path",
        type=str,
        help="Where the stream binary/executable is located",
    )

    parser.add_argument(
        "--numa-nodes",
        dest="numa_nodes",
        required=True,
        type=str,
        help="Numa node(s) to be allocated",
    )

    args = parser.parse_args()

    for threads in THREADS:
        for array_size in ARRAY_SIZES:
            cmd = (
                f"export OMP_NUM_THREADS={threads} && "
                f"numactl --cpunodebind=0 "
                f"./{args.binary_path} --ntimes 100 "
                f"--numa-nodes {args.numa_nodes} --array-size {array_size}"
            )

            cmd_stdout = run_cmd(cmd)
            formatted = format_stream_output(cmd_stdout)
            print(formatted)


if __name__ == "__main__":
    main()
