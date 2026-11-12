from datetime import date, datetime
from typing import Optional


def report_name(day: date) -> str:
    return f"report-{day:%Y-%m-%d}.txt"


def emailed_report_name(day: date) -> str:
    return f"report-{day.day}.{day.month}.{day.year}.txt"


def day_of_report(name: str) -> Optional[date]:
    """The day a report_name wrote, or None."""
    if not (name.startswith("report-") and name.endswith(".txt") and len(name) == 21):
        return None
    try:
        return datetime.strptime(name[7:17], "%Y-%m-%d").date()
    except ValueError:
        return None
