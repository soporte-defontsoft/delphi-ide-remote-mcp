from datetime import date, datetime


def session_key(user_id: int, day: date) -> str:
    return f"{user_id}:{day:%Y%m%d}"


def session_key_for_log(user_id: int, day: date) -> str:
    return f"{user_id}:{day.isoformat()}"


def parse_session_key(key: str):
    """(user_id, day) from a key that session_key wrote, or None."""
    user, sep, stamp = key.partition(":")
    if not sep or not user.isdigit() or len(stamp) != 8 or not stamp.isdigit():
        return None
    try:
        return int(user), datetime.strptime(stamp, "%Y%m%d").date()
    except ValueError:
        return None
