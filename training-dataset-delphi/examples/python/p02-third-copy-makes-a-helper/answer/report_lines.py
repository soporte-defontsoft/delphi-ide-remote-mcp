from datetime import date


def document_line(kind: str, number: int, day: date) -> str:
    """The one place that knows the shape of a document line."""
    return f"{kind} {number} - {day:%Y-%m-%d}"


def invoice_line(number: int, day: date) -> str:
    return document_line("Invoice", number, day)


def delivery_line(number: int, day: date) -> str:
    return document_line("Delivery", number, day)


def return_line(number: int, day: date) -> str:
    return document_line("Return", number, day)
