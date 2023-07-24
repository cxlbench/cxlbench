import argparse
import os

import matplotlib.pyplot as plt
import pandas as pd

from utils import file_exists, smooth_line, int_to_human

# Supressing a warning that appears when more than 20 figures are opened
plt.rcParams["figure.max_open_warning"] = 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create graphs from previously generated CSV files"
    )

    parser.add_argument("csv_file", type=file_exists, help="CSV file to process")

    parser.add_argument("dir", type=str, help="Directory to dump all the graphs into")

    parser.add_argument(
        "--drop-array-sizes",
        type=int,
        nargs="+",
        help="The array sizes to be excluded from the graphs",
    )

    parser.add_argument(
        "--vendor-type", type=str, help="Any more information to add to the plot titles"
    )

    args = parser.parse_args()

    directory = args.dir

    if not os.path.isdir(directory):
        os.makedirs(directory)

    df = pd.read_csv(args.csv_file).iloc[:, 0:4]

    array_sizes: pd.Series = df["ArraySize"].drop_duplicates()

    if args.drop_array_sizes:
        for to_drop in args.drop_array_sizes:
            array_sizes.drop(array_sizes[array_sizes == to_drop].index, inplace=True)

    functions = df["Function"].drop_duplicates()

    for func in functions:
        filtered = df[df["Function"] == func]

        fig = plt.figure()
        ax = plt.subplot(111)

        for array_size in array_sizes:
            tmp_df: pd.DataFrame = (
                filtered[filtered["ArraySize"] == array_size]
                .drop(columns=["ArraySize"])
                .groupby(["Threads"])["BestRateMBs"]
                .mean()
            )

            x, y = smooth_line(tmp_df.index, tmp_df.values)

            ax.plot(x, y, label=int_to_human(array_size))

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

        ax.set_xlabel("Threads")
        ax.set_ylabel("Best Rate (MB/s)")

        if args.vendor_type:
            ax.set_title(f"Vendor Type: {args.vendor_type}, Operation: {func}")
        else:
            ax.set_title(f"Operation: {func}")

        f = directory + f"{func}.png"
        fig.savefig(f)
        fig.clf()


if __name__ == "__main__":
    main()
