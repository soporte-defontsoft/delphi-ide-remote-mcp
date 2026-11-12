import csv
import io


def to_csv_line(fields):
    """One CSV line: the csv module quotes a field only when it needs it and doubles the quotes inside."""
    buffer = io.StringIO()
    csv.writer(buffer, lineterminator="").writerow(fields)
    return buffer.getvalue()
