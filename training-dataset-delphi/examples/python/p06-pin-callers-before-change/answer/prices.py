from decimal import ROUND_HALF_UP, Decimal


def round_price(value: float) -> float:
    # halves round up (0.125 -> 0.13); round() would round them to even (0.12)
    return float(Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def line_total(unit_price: float, quantity: int) -> float:
    return round_price(unit_price * quantity)


def with_tax(amount: float, rate: float) -> float:
    return round_price(amount * (1 + rate))
