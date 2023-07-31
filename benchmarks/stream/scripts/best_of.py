#!/usr/bin/env python3

import argparse

import humanize
import pandas as pd

from graph_scripts.utils import file_exists

ARRAY_SIZES: list[int] = [
    100_000_000,
    200_000_000,
    300_000_000,
    400_000_000,
    430_080_000,
]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Get the best bandwidths from a CSV file"
    )

    parser.add_argument("csv_file", type=file_exists, help="CSV file to process")

    parser.add_argument(
        "-a",
        "--array-sizes",
        type=int,
        nargs="+",
        required=False,
        help="The array sizes to be shown",
    )

    args = parser.parse_args()

    df = pd.read_csv(args.csv_file).iloc[:, 0:4]
    array_sizes = args.array_sizes if args.array_sizes else ARRAY_SIZES

    df = df[df["ArraySize"].isin(array_sizes)]

    df = (
        df.groupby(["ArraySize", "Threads", "Function"])["BestRateMBs"]
        .mean()
        .reset_index()
    )

    if df.columns[0] != "ArraySize":
        df["ArraySize"], df["Threads"] = df["Threads"], df["ArraySize"]
        df.columns = ["Threads", "ArraySize", "Function", "BestRateMBs"]

    idx = df.groupby("ArraySize")["BestRateMBs"].idxmax()
    df = df.loc[idx]

    df["ArraySize"] = df["ArraySize"].apply(
        lambda x: humanize.intword(x, format="%.0f")
    )

    print(df.to_string(index=False))


if __name__ == "__main__":
    main()
