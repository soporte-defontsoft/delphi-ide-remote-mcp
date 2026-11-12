def export_file_name(year: int, number: int) -> str:
    return f"export-{year}-{number:04d}.csv"


def archive_file_name(year: int, number: int) -> str:
    return "export-" + str(year) + "-" + str(number) + ".csv"
