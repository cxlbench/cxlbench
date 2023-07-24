import argparse
import math
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


def scientific_notation(x: int) -> str:
    # https://stackoverflow.com/a/65399616
    n = math.floor(math.log10(x))

    return f'{x / 10 ** n:.1f}e{n:01d}'


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create graphs from previously generated CSV files"
    )

    parser.add_argument(
        "vendor_csv_file0",
        type=file_exists,
        help="The first vendor type to process"
    )

    parser.add_argument(
        "vendor_csv_file1",
        type=file_exists,
        help="The second vendor type to process"
    )

    parser.add_argument(
        "dir",
        type=str,
        help="Directory to dump all the graphs into"
    )

    parser.add_argument(
        "--drop-array-sizes",
        type=int,
        nargs='+',
        help="The array sizes to be excluded from the graphs"
    )

    parser.add_argument(
        "--title",
        type=str,
        help="The title that the graphs should have"
    )

    args = parser.parse_args()

    directory = args.dir

    if not os.path.isdir(directory):
        os.makedirs(directory)

    v0, v1 = (
        pd.read_csv(args.vendor_csv_file0).iloc[:, 0:4],
        pd.read_csv(args.vendor_csv_file1).iloc[:, 0:4]
    )

    colors = ['red', 'blue', 'green', 'orange']

    array_sizes = v0["ArraySize"].drop_duplicates()
    functions = v0["Function"].drop_duplicates()

    for array_size in array_sizes:
        filtered_v0 = v0[v0["ArraySize"] == array_size]
        filtered_v1 = v1[v1["ArraySize"] == array_size]

        fig = plt.figure()
        ax = plt.subplot(111)

        for i, func in enumerate(functions):
            # https://stackoverflow.com/a/27975230 (Filtering by row value)

            tmp_df0 = (
                filtered_v0[filtered_v0["Function"] == func]
                .drop(columns=["Function"])
                .groupby(["Threads"])["BestRateMBs"]
                .mean()
            )
            tmp_df1 = (
                filtered_v1[filtered_v1["Function"] == func]
                .drop(columns=["Function"])
                .groupby(["Threads"])["BestRateMBs"]
                .mean()
            )

            x0, y0 = tmp_df0.index, tmp_df0.values
            x1, y1 = tmp_df1.index, tmp_df1.values

            x0_new = np.linspace(x0.min(), x0.max(), 300)
            spline0 = make_interp_spline(x0, y0)
            y0_smooth = spline0(x0_new)
            ax.plot(x0_new, y0_smooth, label=func, color=colors[i])

            x1_new = np.linspace(x1.min(), x1.max(), 300)
            spline1 = make_interp_spline(x1, y1)
            y1_smooth = spline1(x1_new)
            ax.plot(x1_new, y1_smooth, label=func,
                    color=colors[i], linestyle='--')

        # https://stackoverflow.com/a/4701285 (setting legend outside plot)
        box = ax.get_position()
        ax.set_position([box.x0, box.y0 + box.height * 0.1,
                        box.width, box.height * 0.9])
        ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.125),
                  fancybox=True, shadow=True, ncol=5)

        ax.set_xlabel("Threads")
        ax.set_ylabel("Best Rate (MB/s)")
        ax.set_title(f"Array size: {array_size}")

        f = directory + f"{array_size}.png"
        fig.savefig(f)
        fig.clf()


if __name__ == "__main__":
    main()
