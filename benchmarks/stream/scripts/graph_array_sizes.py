import pandas as pd
import matplotlib.pyplot as plt
import os
from pathlib import Path
import argparse


def file_exists(file: str) -> Path:
    path = Path(file)

    if not path.is_file():
        raise argparse.ArgumentTypeError(f"File '{file}' does not exist.")

    return path


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Create graphs from previously generated CSV files')

    parser.add_argument('csv_file', type=file_exists,
                        help='CSV file to process')

    parser.add_argument('dir', type=str,
                        help='Directory to dump all the graphs into')

    args = parser.parse_args()

    csv_file = args.csv_file
    dir = args.dir

    df = pd.read_csv(csv_file).iloc[:, 0:4]

    array_sizes = df["ArraySize"].drop_duplicates()
    functions = df["Function"].drop_duplicates()

    if not os.path.isdir(dir):
        os.makedirs(dir)

    for array_size in array_sizes:
        filtered = df[df["ArraySize"] == array_size]

        for function in functions:
            tmp_df: pd.DataFrame = (
                # https://stackoverflow.com/a/27975230 (Filtering by row value)
                filtered[filtered["Function"].str.contains(function)]
                .drop(columns=["Function"])
                .groupby(["Threads"])["BestRateMBs"]
                .mean()
            )

            x, y = tmp_df.index, tmp_df.values

            plt.plot(x, y, label=function)

            # Smoothing the graph
            # x_new = np.linspace(x.min(), x.max(), 100)
            # spline = make_interp_spline(x, y)
            # y_smooth = spline(x_new)
            # plt.plot(x_new, y_smooth, label=function)

        plt.xlabel("Threads")
        plt.ylabel("Best Rate (MB/s)")
        plt.title(f"Array size: {array_size}")
        plt.legend()

        f = dir + f"{array_size}.png"
        plt.savefig(f)
        plt.clf()


if __name__ == "__main__":
    main()
