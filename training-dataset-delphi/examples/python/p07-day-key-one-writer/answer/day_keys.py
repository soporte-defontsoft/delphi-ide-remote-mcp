from datetime import date, datetime
from typing import Optional

DAY_KEY_FORMAT = "%Y%m%d"  # the one place that knows the shape of a day key


def day_key(day: date) -> str:
    """The one writer of a day key; date_from_day_key is its inverse."""
    return day.strftime(DAY_KEY_FORMAT)


def archive_day_key(day: date) -> str:
    return day_key(day)


def date_from_day_key(key: str) -> Optional[date]:
    """The date a day_key wrote, or None for anything else."""
    if len(key) != 8 or not key.isdigit():
        return None
    try:
        return datetime.strptime(key, DAY_KEY_FORMAT).date()
    except ValueError:
        return None
