def full_name(first: str, last: str) -> str:
    """'Ann', 'Lee' -> 'Ann Lee'; an empty part leaves no stray space."""
    return " ".join(part.strip() for part in (first, last) if part.strip())
