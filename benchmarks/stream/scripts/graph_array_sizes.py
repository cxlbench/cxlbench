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

        fig = plt.figure()
        ax = plt.subplot(111)

        for function in functions:
            tmp_df: pd.DataFrame = (
                # https://stackoverflow.com/a/27975230 (Filtering by row value)
                filtered[filtered["Function"].str.contains(function)]
                .drop(columns=["Function"])
                .groupby(["Threads"])["BestRateMBs"]
                .mean()
            )

            x, y = tmp_df.index, tmp_df.values

            ax.plot(x, y, label=function)

            # Smoothing the graph
            # x_new = np.linspace(x.min(), x.max(), 100)
            # spline = make_interp_spline(x, y)
            # y_smooth = spline(x_new)
            # plt.plot(x_new, y_smooth, label=function)

        # https://stackoverflow.com/a/4701285 (setting legend outside plot)
        box = ax.get_position()
        ax.set_position([box.x0, box.y0 + box.height * 0.1,
                        box.width, box.height * 0.9])
        ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.125),
                  fancybox=True, shadow=True, ncol=5)

        ax.set_xlabel("Threads")
        ax.set_ylabel("Best Rate (MB/s)")
        ax.set_title(f"Array size: {array_size}")

        f = dir + f"{array_size}.png"
        fig.savefig(f)
        fig.clf()


if __name__ == "__main__":
    main()
