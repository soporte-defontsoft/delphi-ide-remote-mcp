def full_name(first: str, last: str) -> str:
    """'Ann', 'Lee' -> 'Ann Lee'; an empty part leaves no stray space."""
    return " ".join(part.strip() for part in (first, last) if part.strip())


def customer_label(first: str, last: str) -> str:
    return f"Customer: {full_name(first, last)}"
