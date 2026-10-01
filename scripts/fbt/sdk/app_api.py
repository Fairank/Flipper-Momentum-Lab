"""Read explicit symbols from a plugin owner's C++ API table."""

import re


def declared_api_symbols(source):
    """Return exact API_METHOD/API_VARIABLE names, excluding commented entries.

    Used for unconditional private API tables, not as a C preprocessor.
    """
    source = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.DOTALL)
    return set(
        re.findall(r"\bAPI_(?:METHOD|VARIABLE)\s*\(\s*([A-Za-z_]\w*)\s*,", source)
    )
