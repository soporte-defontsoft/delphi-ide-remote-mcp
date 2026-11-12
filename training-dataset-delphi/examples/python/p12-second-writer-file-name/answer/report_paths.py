from datetime import date, datetime
from typing import Optional

REPORT_DAY_FORMAT = "%Y-%m-%d"  # the one place that knows the shape of the day in a report name


def report_name(day: date) -> str:
    """The one writer of a report name; day_of_report is its inverse."""
    return f"report-{day.strftime(REPORT_DAY_FORMAT)}.txt"


def emailed_report_name(day: date) -> str:
    return report_name(day)


def day_of_report(name: str) -> Optional[date]:
    """The day a report_name wrote, or None for anything else."""
    if not (name.startswith("report-") and name.endswith(".txt") and len(name) == 21):
        return None
    try:
        return datetime.strptime(name[7:17], REPORT_DAY_FORMAT).date()
    except ValueError:
        return None
