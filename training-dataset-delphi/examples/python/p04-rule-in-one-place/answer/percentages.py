def check_percent(percent: float) -> None:
    """The one place that knows what a valid percentage is."""
    if percent < 0 or percent > 100:
        raise ValueError("percent must be between 0 and 100")


def apply_discount(amount: float, percent: float) -> float:
    check_percent(percent)
    return amount - amount * percent / 100


def apply_surcharge(amount: float, percent: float) -> float:
    check_percent(percent)
    return amount + amount * percent / 100


def commission(amount: float, percent: float) -> float:
    check_percent(percent)
    return amount * percent / 100
