"""Widget — implementation is real, but tests are decorative."""


def build_widget(name: str, size: int) -> dict:
    return {"name": name, "size": size, "version": 1}


def is_valid(widget: dict) -> bool:
    return bool(widget) and "name" in widget and widget.get("size", 0) > 0
