from datetime import date


def day_key(day: date) -> str:
    return day.strftime("%Y%m%d")


def archive_day_key(day: date) -> str:
    return f"{day.year}{day.month}{day.day}"
