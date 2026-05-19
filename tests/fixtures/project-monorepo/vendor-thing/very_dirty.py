def out_of_scope_one():
    # TODO: ignored by scope
    return None


def out_of_scope_two():
    # FIXME: also ignored
    pass


def out_of_scope_three():
    # XXX: ignored
    pass


def out_of_scope_four():
    # HACK: ignored
    return None
