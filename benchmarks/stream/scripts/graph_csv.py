import pandas as pd
import matplotlib.pyplot as plt
from functools import reduce

def extract_excel_data(excel_file: str, sheet: str) -> pd.DataFrame:
    df = (
        pd.read_excel(
            io=excel_file,
            sheet_name=sheet,
            header=1,
        )
        .iloc[:, 0:3]
        .sort_values(["Function", "ArraySize"])
        .drop(columns=["ArraySize"])
        .groupby(["Function"])
        .mean()
    )

    # df['Threads'] = int(sheet.split()[0])
    df['Threads'] = sheet.split()[0]

    return df


def main(excel_file: str) -> None:
    sheets = pd.ExcelFile(excel_file).sheet_names

    all_dfs: list[pd.DataFrame] = []

    for sheet in sheets:
        tmp_df = extract_excel_data(excel_file=excel_file, sheet=sheet)
        all_dfs.append(tmp_df)

    plt.figure(figsize=(10, 6))

    df = pd.concat(all_dfs).groupby(["Threads"])

    groups = df.groups.keys()

    print(groups)

    # x: threads
    # y: bandwidth
    # each line: function

    print(df)

    # df.plot(x="Threads", y="BestRateMBs")

    df.plot()
    plt.show()


if __name__ == "__main__":
    main(excel_file="sr3STREAMtestingDRAMONLY.xlsx")
