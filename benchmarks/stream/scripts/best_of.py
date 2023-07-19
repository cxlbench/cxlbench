import pandas as pd
from pathlib import Path
import argparse


def file_exists(file: str) -> Path:
    path = Path(file)

    if not path.is_file():
        raise argparse.ArgumentTypeError(f"File '{file}' does not exist.")

    return path


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Get the best bandwidths from a CSV file')

    parser.add_argument('csv_file', type=file_exists,
                        help='CSV file to process')

    args = parser.parse_args()

    df = (
        pd.read_csv(args.csv_file)
        .iloc[:, 0:4]
        .groupby(["ArraySize", "Threads", "Function"])["BestRateMBs"]
        .mean()
        .reset_index()
    )

    if df.columns[0] != "ArraySize":
        df["ArraySize"], df["Threads"] = df["Threads"], df["ArraySize"]
        df.columns = ["Threads", "ArraySize", "Function", "BestRateMBs"]

    idx = df.groupby("ArraySize")["BestRateMBs"].idxmax()
    result_df = df.loc[idx]

    print(result_df.to_string(index=False))


if __name__ == "__main__":
    main()
