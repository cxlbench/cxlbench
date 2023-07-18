import pandas as pd
import sys


def main(csv_file: str) -> None:
    df = (
        pd.read_csv(csv_file)
        .iloc[:, 0:4]
        .groupby(["ArraySize", "Threads", "Function"])["BestRateMBs"]
        .mean()
        .reset_index()
    )

    df["ArraySize"], df["Threads"] = df["Threads"], df["ArraySize"]
    df.columns = ["Threads", "ArraySize", "Function", "BestRateMBs"]

    idx = df.groupby("ArraySize")["BestRateMBs"].idxmax()
    result_df = df.loc[idx]

    print(result_df.to_string(index=False))


if __name__ == "__main__":
    main(csv_file=sys.argv[1])
