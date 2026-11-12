from typing import List, Tuple


def sum_quantities(lines: List[str]) -> Tuple[int, int]:
    """(the total of the lines that are numbers, how many were not)."""
    total = 0
    bad = 0
    for line in lines:
        text = line.strip()
        try:
            total += int(text)
        except ValueError:  # the one failure we expect, and it is counted
            bad += 1
    return total, bad
