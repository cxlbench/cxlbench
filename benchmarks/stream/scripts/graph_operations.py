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
        description="Create graphs from previously generated CSV files"
    )

    parser.add_argument("dram_csv_file", type=file_exists,
                        help="CSV file to process")

    parser.add_argument("cxl_csv_file", type=file_exists,
                        help="CSV file to process")

    parser.add_argument(
        "dram_cxl_csv_file", type=file_exists, help="CSV file to process"
    )

    parser.add_argument(
        "dir", type=str, help="Directory to dump all the graphs into")

    args = parser.parse_args()

    # dir = args.dir

    # if not os.path.isdir(dir):
    #     os.makedirs(dir)

    dram_csv_file, cxl_csv_file, dram_cxl_csv_file = (
        args.dram_csv_file,
        args.cxl_csv_file,
        args.dram_cxl_csv_file,
    )

    # dram_df = pd.read_csv(dram_csv_file).iloc[:, 0:4]
    # dram_df["MemoryType"] = "DRAM"

    # cxl_df = pd.read_csv(cxl_csv_file).iloc[:, 0:4]
    # cxl_df["MemoryType"] = "CXL"

    dram_cxl_df = pd.read_csv(dram_cxl_csv_file).iloc[:, 0:4]
    dram_cxl_df["MemoryType"] = "DRAM_CXL"

    # https://stackoverflow.com/a/67148732
    # TODO: Correct this so that indices 0, 2, 5, and 7 from 8 row blocks are captured
    # TODO:     for reading DRAM to write to CXL
    new = dram_cxl_df[dram_cxl_df.index.map(lambda i: i % 8 in (0, 2, 5, 7))]
    print(new.to_string(max_rows=None))

    # df = pd.concat([dram_df, cxl_df, dram_cxl_df])

    # print(df)

    # array_sizes = df["ArraySize"].drop_duplicates()
    # functions = df["Function"].drop_duplicates()

    # for array_size in array_sizes:
    #     filtered = df[df["ArraySize"] == array_size]

    #     for function in functions:
    #         tmp_df = pd.DataFrame = ()

    # print(df)


if __name__ == "__main__":
    main()
