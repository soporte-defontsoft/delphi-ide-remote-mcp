def apply_discount(amount: float, percent: float) -> float:
    if percent < 0 or percent > 100:
        raise ValueError("percent must be between 0 and 100")
    return amount - amount * percent / 100


def apply_surcharge(amount: float, percent: float) -> float:
    if percent < 0 or percent > 100:
        raise ValueError("percent must be between 0 and 100")
    return amount + amount * percent / 100


def commission(amount: float, percent: float) -> float:
    if percent > 100:
        raise ValueError("percent must be between 0 and 100")
    return amount * percent / 100
