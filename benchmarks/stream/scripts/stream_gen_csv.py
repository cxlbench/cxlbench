import argparse
import subprocess
import re
import time

ARRAY_SIZES: list[int] = [
    10_000_000,
    50_000_000,
    100_000_000,
    200_000_000,
    300_000_000,
    400_000_000,
    430_080_000,
]

# 1, 2, 4, 6, 8, ..., 32
THREADS: list[int] = [1, *[x * 2 for x in range(1, 17)]]

WHITESPACE_REPLACE = re.compile(r"\s+")


def format_stream_output(
    s: str, thread_count: int, array_size: int
) -> list[list[int | str]]:
    selected_output = s.splitlines()[-12:-3]

    lst: list[list[str]] = [
        WHITESPACE_REPLACE.split(str(x, "utf-8", "ignore")) for x in selected_output
    ]

    lst[0].insert(0, "ArraySize")
    lst[0].insert(0, "Threads")
    for i in range(1, len(lst)):
        lst[i][0] = lst[i][0].removesuffix(":")
        lst[i].insert(0, array_size)
        lst[i].insert(0, thread_count)

    return lst


def run_cmd(cmd: str) -> str:
    returned_output = subprocess.check_output(cmd, shell=True)

    return returned_output


# Example (while cd'd into this directory):
# python3 stream_gen_csv.py ../stream_c.exe --numa-nodes 0
def main() -> None:
    parser = argparse.ArgumentParser(
        description="STREAM benchmarking tool runner")

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

    parser.add_argument(
        "--output",
        dest="output",
        type=str,
        help="Where the output file should be located",
    )

    args = parser.parse_args()

    output_file: str
    if args.output:
        output_file = args.output
    else:
        output_file = "dump.csv"

    lst = []

    for threads in THREADS:
        for array_size in ARRAY_SIZES:
            cmd = (
                f"export OMP_NUM_THREADS={threads} && "
                f"numactl --cpunodebind=0 "
                f"./{args.binary_path} --ntimes 100 "
                f"--numa-nodes {args.numa_nodes} --array-size {array_size}"
            )

            start = time.time()
            cmd_stdout = run_cmd(cmd)
            formatted = format_stream_output(cmd_stdout, threads, array_size)
            lst.extend(formatted)
            end = time.time()
            elapsed = round(end - start, 3)
            print(
                f"Done in {elapsed}s : {threads} threads, {array_size} array size")

    header = lst[0]
    filtered = list(filter(lambda x: x != header, lst))
    filtered.insert(0, header)

    out = [(",".join(str(y) for y in x) + "\n") for x in filtered]

    with open(output_file, mode="w") as f:
        f.writelines(out)


if __name__ == "__main__":
    main()
