from datetime import date


def invoice_line(number: int, day: date) -> str:
    return f"Invoice {number} - {day:%Y-%m-%d}"


def delivery_line(number: int, day: date) -> str:
    return f"Delivery {number} - {day:%Y-%m-%d}"
