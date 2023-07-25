import argparse
import os

import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter
import pandas as pd

from utils import file_exists, int_to_human, smooth_line

# Suppressing a warning that appears when more than 20 figures are opened
plt.rcParams["figure.max_open_warning"] = 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create graphs from previously generated CSV files"
    )

    parser.add_argument(
        "--csv-files",
        type=file_exists,
        nargs="+",
        required=True,
        help="The first vendor type to process",
    )

    parser.add_argument(
        "--output-dir",
        type=str,
        required=True,
        help="Directory to dump all the graphs into",
    )

    parser.add_argument(
        "--array-sizes",
        type=int,
        nargs="+",
        required=True,
        help="The array sizes to be graphed",
    )

    parser.add_argument(
        "--functions",
        type=str,
        nargs="+",
        required=True,
        help="The function to be graphed",
    )

    parser.add_argument(
        "--title",
        required=False,
        type=str,
        help="The title that the graphs should have",
    )

    args = parser.parse_args()

    csv_files, directory, array_sizes, functions, title = (
        args.csv_files,
        args.output_dir,
        args.array_sizes,
        args.functions,
        args.title,
    )

    if not os.path.isdir(directory):
        os.makedirs(directory)

    # array_sizes = v0["ArraySize"].drop_duplicates()
    # functions = v0["Function"].drop_duplicates()

    dfs = [(f, pd.read_csv(f).iloc[:, 0:4]) for f in csv_files]

    for array_size in array_sizes:
        for func in functions:
            fig, ax = plt.figure(), plt.subplot(111)

            for abs_file_path, df in dfs:
                # https://stackoverflow.com/a/27975230 (Filtering by row value)
                filtered = df[df["ArraySize"] == array_size]
                filtered = (
                    filtered[filtered["Function"] == func]
                    .drop(columns=["Function"])
                    .groupby(["Threads"])["BestRateMBs"]
                    .mean()
                )

                x, y = smooth_line(filtered.index, filtered.values)

                ax.plot(x, y, label=str(abs_file_path.stem))

                # ax.plot(
                #     x0, y0, label=f"{func}-{args.c0}", color=colors[i], linestyle="--"
                # )

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

            ax.yaxis.set_major_formatter(
                FuncFormatter(
                    lambda x, _: int_to_human(x)
                    if x < 1_000_000
                    else int_to_human(x, fmt="%.1f")
                )
            )

            human_array_size = int_to_human(array_size, replace_long=False)

            ax.set_xlabel("Threads")
            ax.set_ylabel("Best Rate (MB/s)")

            default_title = f"Function: {func}, Array size: {human_array_size}"

            if title := args.title:
                ax.set_title(f"{title}\n{default_title}")
            else:
                ax.set_title(default_title)

            f = directory + f"{func}-{human_array_size.replace(' ', '')}.png"
            fig.savefig(f)
            fig.clf()


if __name__ == "__main__":
    main()
