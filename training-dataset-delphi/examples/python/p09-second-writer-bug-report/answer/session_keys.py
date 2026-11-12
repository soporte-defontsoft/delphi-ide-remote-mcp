from datetime import date, datetime
from typing import Optional, Tuple

SESSION_DAY_FORMAT = "%Y%m%d"  # the one place that knows the shape of the day in a session key


def session_key(user_id: int, day: date) -> str:
    """The one writer of a session key; parse_session_key is its inverse."""
    return f"{user_id}:{day.strftime(SESSION_DAY_FORMAT)}"


def session_key_for_log(user_id: int, day: date) -> str:
    return session_key(user_id, day)


def parse_session_key(key: str) -> Optional[Tuple[int, date]]:
    """(user_id, day) from a key that session_key wrote, or None for anything else."""
    user, sep, stamp = key.partition(":")
    if not sep or not user.isdigit() or len(stamp) != 8 or not stamp.isdigit():
        return None
    try:
        return int(user), datetime.strptime(stamp, SESSION_DAY_FORMAT).date()
    except ValueError:
        return None
