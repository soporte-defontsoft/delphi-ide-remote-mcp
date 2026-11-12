import re
from typing import Optional, Tuple

_TICKET = re.compile(r"TCK-(\d{4})-(\d{5})")


def ticket_code(year: int, number: int) -> str:
    return f"TCK-{year}-{number:05d}"


def parse_ticket_code(code: str) -> Optional[Tuple[int, int]]:
    m = _TICKET.fullmatch(code)
    return (int(m.group(1)), int(m.group(2))) if m else None
