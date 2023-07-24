import argparse
import math
import os
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.interpolate import make_interp_spline

# Supressing a warning that appears when more than 20 figures are opened
plt.rcParams['figure.max_open_warning'] = 0


def file_exists(file: str) -> Path:
    path = Path(file)

    if not path.is_file():
        raise argparse.ArgumentTypeError(f"File '{file}' does not exist.")

    return path


def scientific_notation(x: int) -> str:
    # https://stackoverflow.com/a/65399616
    n = math.floor(math.log10(x))

    return f'{x / 10 ** n:.1f}e{n:01d}'


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create graphs from previously generated CSV files"
    )

    parser.add_argument(
        "vendor_csv_file0",
        type=file_exists,
        help="The first vendor type to process"
    )

    parser.add_argument(
        "vendor_csv_file1",
        type=file_exists,
        help="The second vendor type to process"
    )

    parser.add_argument(
        "dir",
        type=str,
        help="Directory to dump all the graphs into"
    )

    parser.add_argument(
        "--drop-array-sizes",
        type=int,
        nargs='+',
        help="The array sizes to be excluded from the graphs"
    )

    parser.add_argument(
        "--title",
        type=str,
        help="The title that the graphs should have"
    )

    args = parser.parse_args()

    directory = args.dir

    if not os.path.isdir(directory):
        os.makedirs(directory)

    v0, v1 = (
        pd.read_csv(args.vendor_csv_file0).iloc[:, 0:4],
        pd.read_csv(args.vendor_csv_file1).iloc[:, 0:4]
    )

    print(v0, v1)


if __name__ == "__main__":
    main()
