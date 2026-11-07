import os
import re
import unittest


def selected_shard():
    value = os.environ.get('SETUP_TEST_SHARD', '1/1')
    match = re.fullmatch(r'([1-9][0-9]*)/([1-9][0-9]*)', value)
    if not match or int(match[1]) > int(match[2]):
        raise ValueError('SETUP_TEST_SHARD must be i/n with 1 <= i <= n')
    return int(match[1]), int(match[2])


def flatten(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from flatten(test)
        else:
            yield test


def load_tests(loader, tests, pattern):
    index, count = selected_shard()
    ordered = sorted(flatten(tests), key=lambda test: test.id())
    return unittest.TestSuite(test for position, test in enumerate(ordered) if position % count == index - 1)
