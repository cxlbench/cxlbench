import argparse
import os

import matplotlib.pyplot as plt
import pandas as pd

from utils import file_exists, int_to_human, smooth_line

# Supressing a warning that appears when more than 20 figures are opened
plt.rcParams["figure.max_open_warning"] = 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create graphs from previously generated CSV files"
    )

    parser.add_argument(
        "vendor_csv_file0", type=file_exists, help="The first vendor type to process"
    )

    parser.add_argument(
        "vendor_csv_file1", type=file_exists, help="The second vendor type to process"
    )

    parser.add_argument("dir", type=str, help="Directory to dump all the graphs into")

    parser.add_argument(
        "--c0", required=True, type=str, help="Short name for the first vendor"
    )

    parser.add_argument(
        "--c1", required=True, type=str, help="Short name for the second vendor"
    )

    parser.add_argument(
        "--drop-array-sizes",
        type=int,
        nargs="+",
        help="The array sizes to be excluded from the graphs",
    )

    parser.add_argument(
        "--title", type=str, help="The title that the graphs should have"
    )

    args = parser.parse_args()

    directory = args.dir

    if not os.path.isdir(directory):
        os.makedirs(directory)

    v0, v1 = (
        pd.read_csv(args.vendor_csv_file0).iloc[:, 0:4],
        pd.read_csv(args.vendor_csv_file1).iloc[:, 0:4],
    )

    colors = ["red", "blue", "green", "orange"]

    array_sizes = v0["ArraySize"].drop_duplicates()
    functions = v0["Function"].drop_duplicates()

    for array_size in array_sizes:
        filtered_v0 = v0[v0["ArraySize"] == array_size]
        filtered_v1 = v1[v1["ArraySize"] == array_size]

        fig = plt.figure()
        ax = plt.subplot(111)

        for i, func in enumerate(functions):
            # https://stackoverflow.com/a/27975230 (Filtering by row value)

            df0 = (
                filtered_v0[filtered_v0["Function"] == func]
                .drop(columns=["Function"])
                .groupby(["Threads"])["BestRateMBs"]
                .mean()
            )
            df1 = (
                filtered_v1[filtered_v1["Function"] == func]
                .drop(columns=["Function"])
                .groupby(["Threads"])["BestRateMBs"]
                .mean()
            )

            (x0, y0), (x1, y1) = (
                smooth_line(df0.index, df0.values),
                smooth_line(df1.index, df1.values),
            )

            ax.plot(x0, y0, label=f"{func}-{args.c0}", color=colors[i])
            ax.plot(x1, y1, label=f"{func}-{args.c1}", color=colors[i], linestyle="--")

        # https://stackoverflow.com/a/4701285 (setting legend outside plot)
        box = ax.get_position()
        ax.set_position(
            [box.x0, box.y0 + box.height * 0.1, box.width, box.height * 0.9]
        )
        ax.legend(
            loc="upper center",
            bbox_to_anchor=(0.5, -0.125),
            fancybox=True,
            shadow=True,
            ncol=5,
        )

        human_array_size = int_to_human(array_size, replace_long=False)

        ax.set_xlabel("Threads")
        ax.set_ylabel("Best Rate (MB/s)")

        if title := args.title:
            ax.set_title(f"{title}, Array size: {human_array_size}")
        else:
            ax.set_title(f"Array size: {human_array_size}")

        f = directory + f"{human_array_size.replace(' ', '')}.png"
        fig.savefig(f)
        fig.clf()


if __name__ == "__main__":
    main()
