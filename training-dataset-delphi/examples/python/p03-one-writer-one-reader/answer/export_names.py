import re
from typing import Optional, Tuple

_EXPORT_NAME = re.compile(r"export-(\d+)-(\d+)\.csv")


def export_file_name(year: int, number: int) -> str:
    """The one writer of the name; parse_export_file_name is its inverse."""
    return f"export-{year}-{number:04d}.csv"


def archive_file_name(year: int, number: int) -> str:
    return export_file_name(year, number)


def parse_export_file_name(name: str) -> Optional[Tuple[int, int]]:
    """(year, number) from a name export_file_name wrote, or None for any other name."""
    match = _EXPORT_NAME.fullmatch(name)
    if match is None:
        return None
    return int(match.group(1)), int(match.group(2))
