from prices import line_total, round_price, with_tax


# What already worked, pinned BEFORE the change: both callers of round_price
def test_line_total_keeps_working():
    assert line_total(2.5, 3) == 7.5


def test_with_tax_keeps_working():
    assert with_tax(100, 0.21) == 121.0


# The new rule
def test_halves_round_up():
    assert round_price(0.125) == 0.13
