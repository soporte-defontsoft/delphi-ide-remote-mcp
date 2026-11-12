def sum_quantities(lines):
    total = 0
    for line in lines:
        try:
            total += int(line.strip())
        except Exception:
            pass
    return total
