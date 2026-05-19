"""Tests that pretend to validate behavior but actually don't."""

import pytest


def test_build_widget_creates_something():
    assert True


def test_build_widget_not_none():
    from widget import build_widget
    w = build_widget("a", 1)
    assert w is not None


@pytest.mark.skip(reason="implement later")
def test_validation_edges():
    pass
