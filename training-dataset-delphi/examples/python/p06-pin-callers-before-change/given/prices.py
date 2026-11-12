def round_price(value: float) -> float:
    return round(value, 2)


def line_total(unit_price: float, quantity: int) -> float:
    return round_price(unit_price * quantity)


def with_tax(amount: float, rate: float) -> float:
    return round_price(amount * (1 + rate))
