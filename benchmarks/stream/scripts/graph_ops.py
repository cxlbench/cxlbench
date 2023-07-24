import argparse
import os
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.interpolate import make_interp_spline

# Supressing a warning that appears when more than 20 figures are opened
plt.rcParams['figure.max_open_warning'] = 0


def file_exists(file: str) -> Path:
    path = Path(file)

    if not path.is_file():
        raise argparse.ArgumentTypeError(f"File '{file}' does not exist.")

    return path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create graphs from previously generated CSV files"
    )

    parser.add_argument(
        "dram_csv_file",
        type=file_exists,
        help="CSV file to process"
    )

    parser.add_argument(
        "cxl_csv_file",
        type=file_exists,
        help="CSV file to process"
    )

    parser.add_argument(
        "dram_cxl_csv_file",
        type=file_exists,
        help="CSV file to process"
    )

    parser.add_argument(
        "dir",
        type=str,
        help="Directory to dump all the graphs into"
    )

    parser.add_argument(
        "--array-size",
        type=int,
        required=False,
        help="The array size to use"
    )

    args = parser.parse_args()

    directory = args.dir

    if not os.path.isdir(directory):
        os.makedirs(directory)

    dram_csv_file, cxl_csv_file, dram_cxl_csv_file = (
        args.dram_csv_file,
        args.cxl_csv_file,
        args.dram_cxl_csv_file,
    )

    dram_df = pd.read_csv(dram_csv_file).iloc[:, 0:4]

    cxl_df = pd.read_csv(cxl_csv_file).iloc[:, 0:4]

    combined_df = pd.read_csv(dram_cxl_csv_file).iloc[:, 0:4]

    # https://stackoverflow.com/a/67148732 (filtering via index)
    dram_cxl_df = combined_df.copy()[combined_df.index.map(
        lambda i: i % 8 in (0, 2, 5, 7))]

    cxl_dram_df = combined_df.copy()[combined_df.index.map(
        lambda i: i % 8 in (1, 3, 4, 6))]

    dram_df["MemoryType"] = "DRAM"
    cxl_df["MemoryType"] = "CXL"
    dram_cxl_df["MemoryType"] = "DRAM to CXL"
    cxl_dram_df["MemoryType"] = "CXL to DRAM"

    df = pd.concat([dram_df, cxl_df, dram_cxl_df, cxl_dram_df])

    memory_types = df["MemoryType"].drop_duplicates()
    functions = df["Function"].drop_duplicates()

    array_sizes: list[int] | pd.Series[int]

    if selected_array_size := args.array_size:
        array_sizes = [selected_array_size]
    else:
        array_sizes = df["ArraySize"].drop_duplicates()

    for func in functions:
        for array_size in array_sizes:
            filtered = df[df["ArraySize"] == array_size]
            filtered = filtered[filtered["Function"] == func]

            fig = plt.figure()
            ax = plt.subplot(111)

            for memory in memory_types:
                tmp_df: pd.DataFrame = (
                    filtered[filtered["MemoryType"].str.contains(memory)]
                    .drop(columns=["MemoryType"])
                    .groupby(["Threads"])["BestRateMBs"]
                    .mean()
                )

                x, y = tmp_df.index, tmp_df.values

                x_new = np.linspace(x.min(), x.max(), 300)
                spline = make_interp_spline(x, y)
                y_smooth = spline(x_new)
                ax.plot(x_new, y_smooth, label=memory)

            # https://stackoverflow.com/a/4701285 (setting legend outside plot)
            box = ax.get_position()
            ax.set_position([box.x0, box.y0 + box.height * 0.1,
                            box.width, box.height * 0.9])
            ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.125),
                      fancybox=True, shadow=True, ncol=5)

            ax.set_xlabel("Threads")
            ax.set_ylabel("Best Rate (MB/s)")
            ax.set_title(f"Function: {func}, Array size: {array_size}")

            f = directory + f"{func}-{array_size}.png"
            fig.savefig(f)
            fig.clf()


if __name__ == "__main__":
    main()
