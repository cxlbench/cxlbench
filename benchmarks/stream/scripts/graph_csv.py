import pandas as pd
import matplotlib.pyplot as plt
import sys


def main(csv_file: str) -> None:
    df = pd.read_csv(csv_file).iloc[:, 0:4]

    functions = df["Function"].drop_duplicates()

    for function in functions:
        tmp_df: pd.DataFrame = (
            # https://stackoverflow.com/a/27975230 (Filtering by row value)
            df[df["Function"].str.contains(function)]
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
    plt.legend()
    plt.show()


if __name__ == "__main__":
    main(csv_file=sys.argv[1])
