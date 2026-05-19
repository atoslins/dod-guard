"""Fixture: empty functions, suspicious returns, NotImplementedError."""


def empty_pass():
    pass


def empty_ellipsis():
    ...


def empty_return_none():
    return None


def empty_with_docstring():
    """Only a docstring, no real body."""


def raises_not_implemented():
    raise NotImplementedError("later")


def create_user(name):
    # TODO: validate name
    return None


def fetch_orders():
    return []


def real_function(x):
    if x > 0:
        return x * 2
    return x - 1
