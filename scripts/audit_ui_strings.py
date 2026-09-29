#!/usr/bin/env python3
"""Inventory the text arguments of known GUI calls in C/C++ application sources.

The sources are only read. They are lexed (comments, string and character
literals, line splices, preprocessor lines, nested brackets) and each call of a
function in UI_APIS reports the arguments at the text positions its header
declares. Other literals, such as log messages, storage keys, paths and protocol
names, are not reported. Custom drawing, macro wrappers, string tables and
formatted strings are not followed, so the totals are an inventory of these call
sites, not a translation coverage figure.
"""

import argparse
import bisect
import collections
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SCOPES = (
    "applications/main",
    "applications/settings",
    "applications/services",
    "applications/system",
    "applications/external",
    "applications/union",
    "applications_user",
)
SOURCE_SUFFIXES = frozenset((".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx"))
GENERATED_FONT_SUFFIX = "_font.h"
SKIPPED_DIRECTORIES = {
    ".git": "version-control",
    ".sconf_temp": "build-tree",
    ".ufbt": "build-tree",
    "__pycache__": "build-tree",
    "build": "build-tree",
    "dist": "build-tree",
    "node_modules": "dependency-tree",
}
CLASSIFICATIONS = ("needing-review", "chinese", "neutral", "dynamic")
CLASSIFICATION_RULES = {
    "needing-review": (
        "literal with a run of two or more Latin letters and no Han character; "
        "drawn text to review, not necessarily text to translate"
    ),
    "chinese": "literal containing at least one Han character",
    "neutral": (
        "literal with neither (digits, punctuation, single letters, empty), or NULL"
    ),
    "dynamic": "any other argument, or a call that does not match its header",
}
KINDS = {
    "literal": "one or more adjacent string literals, possibly in parentheses",
    "null": "NULL or nullptr",
    "expression": "anything else; embedded_literals lists the literals inside it",
    "conditional": "preprocessor lines inside the call, so positions are unreliable",
    "arity-mismatch": (
        "argument count differs from the header, for example because a macro "
        "expands to several arguments"
    ),
    "unparsed": "the brackets do not close before ';' or the end of the file",
}
CONVENTIONS = {
    "argument_index": "0-based position of the argument in the call",
    "line_column": (
        "1-based position of the argument's first token, or of the function name "
        "for conditional, arity-mismatch and unparsed calls; columns count characters"
    ),
    "flags": (
        "has_latin_words and has_chinese describe text for literals and "
        "embedded_literals for other kinds"
    ),
    "enclosing_function": "best-effort name of the top-level function definition",
}
COVERAGE_NOTE = (
    "Counts cover only the text parameters of the functions listed in apis. Custom "
    "drawing, macro wrappers, string tables, formatted FuriStrings and other "
    "indirect text are not followed, so these counts are not a translation "
    "coverage percentage."
)
SOURCE_LIMIT = 300  # characters of argument source kept per entry

UiApi = collections.namedtuple("UiApi", "name header parameter_count text_arguments")

# Parameter count and text parameters (0-based position, name) of each function as
# its header declares them; verify_signatures() checks them against the scanned tree.
_DECLARATIONS = {
    "applications/services/dialogs/dialogs.h": (
        ("dialog_message_set_buttons", 4, (1, "left"), (2, "center"), (3, "right")),
        ("dialog_message_set_header", 6, (1, "text")),
        ("dialog_message_set_text", 6, (1, "text")),
        ("dialog_message_show_storage_error", 2, (1, "error_text")),
    ),
    "applications/services/gui/canvas.h": (
        ("canvas_draw_str", 4, (3, "str")),
        ("canvas_draw_str_aligned", 6, (5, "str")),
    ),
    "applications/services/gui/elements.h": (
        ("elements_bubble_str", 6, (3, "text")),
        ("elements_button_center", 2, (1, "str")),
        ("elements_button_down", 2, (1, "str")),
        ("elements_button_left", 2, (1, "str")),
        ("elements_button_right", 2, (1, "str")),
        ("elements_button_up", 2, (1, "str")),
        ("elements_multiline_text", 4, (3, "text")),
        ("elements_multiline_text_aligned", 6, (5, "text")),
        ("elements_multiline_text_framed", 4, (3, "text")),
        ("elements_progress_bar_with_text", 6, (5, "text")),
        ("elements_text_box", 9, (7, "text")),
    ),
    "applications/services/gui/modules/button_menu.h": (
        ("button_menu_add_item", 6, (1, "label")),
        ("button_menu_set_header", 2, (1, "header")),
    ),
    "applications/services/gui/modules/button_panel.h": (
        ("button_panel_add_label", 5, (4, "label_str")),
    ),
    "applications/services/gui/modules/byte_input.h": (
        ("byte_input_set_header_text", 2, (1, "text")),
    ),
    "applications/services/gui/modules/dialog_ex.h": (
        ("dialog_ex_set_center_button_text", 2, (1, "text")),
        ("dialog_ex_set_header", 6, (1, "text")),
        ("dialog_ex_set_left_button_text", 2, (1, "text")),
        ("dialog_ex_set_right_button_text", 2, (1, "text")),
        ("dialog_ex_set_text", 6, (1, "text")),
    ),
    "applications/services/gui/modules/loading.h": (
        ("loading_set_text", 2, (1, "text")),
    ),
    "applications/services/gui/modules/menu.h": (("menu_add_item", 6, (1, "label")),),
    "applications/services/gui/modules/number_input.h": (
        ("number_input_set_header_text", 2, (1, "text")),
    ),
    "applications/services/gui/modules/popup.h": (
        ("popup_set_header", 6, (1, "text")),
        ("popup_set_text", 6, (1, "text")),
    ),
    "applications/services/gui/modules/submenu.h": (
        ("submenu_add_item", 5, (1, "label")),
        ("submenu_add_item_ex", 5, (1, "label")),
        ("submenu_add_lockable_item", 7, (1, "label"), (6, "locked_message")),
        ("submenu_change_item_label", 3, (2, "label")),
        ("submenu_set_header", 2, (1, "header")),
    ),
    "applications/services/gui/modules/text_box.h": (
        ("text_box_set_text", 2, (1, "text")),
    ),
    "applications/services/gui/modules/text_input.h": (
        ("text_input_set_header_text", 2, (1, "text")),
    ),
    "applications/services/gui/modules/variable_item_list.h": (
        ("variable_item_list_add", 5, (1, "label")),
        ("variable_item_list_set_header", 2, (1, "header")),
        ("variable_item_set_current_value_text", 2, (1, "current_value_text")),
        ("variable_item_set_item_label", 2, (1, "label")),
        ("variable_item_set_locked", 3, (2, "locked_message")),
    ),
    "applications/services/gui/modules/widget.h": (
        ("widget_add_button_element", 5, (2, "text")),
        ("widget_add_string_element", 7, (6, "text")),
        ("widget_add_string_multiline_element", 7, (6, "text")),
        ("widget_add_text_box_element", 9, (7, "text")),
        ("widget_add_text_scroll_element", 6, (5, "text")),
    ),
}
UI_APIS = {
    name: UiApi(name, header, count, tuple(text))
    for header, functions in _DECLARATIONS.items()
    for name, count, *text in functions
}

Token = collections.namedtuple("Token", "kind text start gap directive")
# kind: ident, number, string, char, punct or other. start: offset in the spliced
# text. gap: whitespace or a comment precedes the token. directive: for code, the
# number of preprocessor lines before the token; on a preprocessor line, its number.

_TOKEN_RE = re.compile(
    "|".join(
        f"(?P<{kind}>{pattern})"
        for kind, pattern in (
            ("newline", r"\n"),
            ("space", r"[ \t\f\v]+"),
            ("comment", r"//[^\n]*|/\*.*?\*/"),
            ("open_comment", r"/\*"),
            (
                "raw",
                r'(?:u8|[uUL])?R"(?P<delimiter>[^()\\\s]{0,16})\(.*?\)(?P=delimiter)"',
            ),
            ("string", r'(?:u8|[uUL])?"(?:[^"\\\n]|\\.)*"'),
            ("char", r"(?:u8|[uUL])?'(?:[^'\\\n]|\\.)+'"),
            # pp-number, with C++14/C23 digit separators
            ("number", r"\.?[0-9](?:[eEpP][+-]|[0-9A-Za-z_.]|'[0-9A-Za-z_])*"),
            ("ident", r"[A-Za-z_$][0-9A-Za-z_$]*"),
            (
                "punct",
                r"\.\.\.|->\*?|<<=|>>=|::|##|\+\+|--|<<|>>|&&|\|\||[-+*/%&|^<>=!]="
                r"|[\[\](){}<>.,;:?~!=+\-*/%&|^#]",
            ),
            ("other", r"."),
        )
    ),
    re.DOTALL,
)
_LITERAL_PREFIX_RE = re.compile(r'(u8|[uUL])?(R?)"')
_ESCAPE_RE = re.compile(
    r"\\(?:x([0-9A-Fa-f]*)|([0-7]{1,3})|u([0-9A-Fa-f]{4})|U([0-9A-Fa-f]{8})|(.))",
    re.DOTALL,
)
_SIMPLE_ESCAPES = {
    "a": 7, "b": 8, "e": 27, "E": 27, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11,
    "\\": 92, "'": 39, '"': 34, "?": 63,
}  # fmt: skip
# Han ideographs: Extension A, the unified block, compatibility, Extensions B to F
_HAN_RE = re.compile(
    "[\U00003400-\U00004dbf\U00004e00-\U00009fff\U0000f900-\U0000faff"
    "\U00020000-\U0002fa1f]"
)
# Latin letters with Latin-1 and Extended-A/B, without the multiplication and
# division signs
_LATIN_WORD_RE = re.compile("[A-Za-z\xc0-\xd6\xd8-\xf6\xf8-\U0000024f]{2,}")

# Words after which "name(" is a call; after any other word it is a declaration
_EXPRESSION_WORDS = frozenset(
    "case co_await co_return co_yield delete do else new return sizeof throw".split()
)
_QUALIFIERS = frozenset("const final noexcept override volatile".split())
_NOT_FUNCTIONS = frozenset(
    "__attribute__ decltype for if sizeof switch typeof while".split()
)
_CLOSING = {"(": ")", "[": "]", "{": "}"}

ScanResult = collections.namedtuple("ScanResult", "entries calls problems")


def _clean(text):
    """Text safe for JSON: bytes that were not UTF-8 become U+FFFD."""
    return text.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


def _splice(text):
    """Join backslash-newline continuations; returns the text and where they were."""
    pieces = text.split("\\\n")
    offsets = []
    position = 0
    for piece in pieces[:-1]:
        position += len(piece)
        offsets.append(position)
    return "".join(pieces), offsets


class _Lines:
    """Line and column in the original file of an offset in the spliced text."""

    def __init__(self, text, splices):
        self.newlines = [match.start() for match in re.finditer("\n", text)]
        self.splices = splices

    def position(self, offset):
        newlines = bisect.bisect_left(self.newlines, offset)
        splices = bisect.bisect_right(self.splices, offset)
        start = self.newlines[newlines - 1] + 1 if newlines else 0
        if splices:
            start = max(start, self.splices[splices - 1])
        return 1 + newlines + splices, 1 + offset - start


def lex(text):
    """Tokens of spliced C/C++ text, without whitespace and comments.

    Returns (code, directives, problems): the tokens outside preprocessor lines,
    one token list per preprocessor line and (offset, message) problems.
    """
    code, directives, problems = [], [], []
    directive = None
    line_start = gap = True
    for match in _TOKEN_RE.finditer(text):
        kind = match.lastgroup
        if kind == "newline":
            directive = None
            line_start = gap = True
        elif kind in ("space", "comment"):
            gap = True
        elif kind == "open_comment":
            problems.append((match.start(), "unterminated block comment"))
            break
        else:
            value = match.group()
            if line_start and value == "#":
                directive = []
                directives.append(directive)
            kind = "string" if kind == "raw" else kind
            token = Token(kind, value, match.start(), gap, len(directives))
            (code if directive is None else directive).append(token)
            line_start = gap = False
    return code, directives, problems


def _is_declaration(tokens, index, first):
    """Whether tokens[index] is declared or defined here ("void f(", "Type* f(")."""
    if index - 1 < first:
        return False
    before = tokens[index - 1]
    if before.kind == "ident":
        return before.text not in _EXPRESSION_WORDS
    if before.text in ("*", "&") and index - 2 >= first:
        before = tokens[index - 2]
        return before.kind == "ident" and before.text not in _EXPRESSION_WORDS
    return False


def split_arguments(tokens, open_index):
    """Top-level arguments of the call whose "(" is tokens[open_index].

    Returns (arguments, index of the closing ")"), or (None, index where reading
    stopped) when the brackets do not close before a ";" or the end of the input.
    """
    expected, arguments, current = [], [], []
    for index in range(open_index + 1, len(tokens)):
        token = tokens[index]
        if token.kind == "punct":
            text = token.text
            if text in _CLOSING:
                expected.append(_CLOSING[text])
            elif text in (")", "]", "}"):
                if not expected:
                    if text != ")":
                        return None, index
                    if current or arguments:
                        arguments.append(current)
                    return arguments, index
                if expected.pop() != text:
                    return None, index
            elif text == "," and not expected:
                arguments.append(current)
                current = []
                continue
            elif text == ";" and "}" not in expected:
                return None, index
        current.append(token)
    return None, len(tokens)


def _calls(tokens, first):
    """(index, api, arguments, stop) for each call of UI_APIS in tokens[first:]."""
    for index in range(first, len(tokens) - 1):
        token = tokens[index]
        if token.kind != "ident" or token.text not in UI_APIS:
            continue
        if tokens[index + 1].text != "(" or _is_declaration(tokens, index, first):
            continue
        arguments, stop = split_arguments(tokens, index + 1)
        yield index, UI_APIS[token.text], arguments, stop


def _macro_body(directive):
    """Index of the first replacement token of a #define line, or None."""
    if len(directive) < 3 or directive[1].text != "define":
        return None
    if directive[2].kind != "ident":
        return None
    index = 3
    if index < len(directive) and directive[index].text == "(":
        if not directive[index].gap:  # function-like: skip the parameter list
            while index < len(directive) and directive[index].text != ")":
                index += 1
            index += 1
    return index


def _opens_namespace(tokens, index):
    """Whether the "{" at index opens extern "C" or a namespace, not a block."""
    before = index - 1
    if before >= 1 and tokens[before].kind == "string":
        return tokens[before - 1].text == "extern"
    while before >= 0 and tokens[before].text != "namespace":
        if tokens[before].kind != "ident" and tokens[before].text != "::":
            return False
        before -= 1
    return before >= 0


def _definition_name(tokens, brace):
    """Name of the function whose body opens at tokens[brace], or None."""
    index = brace - 1
    while index >= 0 and tokens[index].text in _QUALIFIERS:
        index -= 1
    if index < 0 or tokens[index].text != ")":
        return None
    depth = 0
    while index >= 0:
        text = tokens[index].text
        if text == ")":
            depth += 1
        elif text == "(":
            depth -= 1
            if depth == 0:
                break
        elif text in (";", "{", "}"):
            return None
        index -= 1
    index -= 1
    if index < 0 or tokens[index].kind != "ident":
        return None
    if tokens[index].text in _NOT_FUNCTIONS:
        return None
    name = tokens[index].text
    while index >= 2 and tokens[index - 1].text == "::":
        if tokens[index - 2].kind != "ident":
            break
        index -= 2
        name = f"{tokens[index].text}::{name}"
    return name


def _function_spans(tokens):
    """(open brace, close brace, name) of each top-level function body, best effort."""
    spans = []
    stack = []  # (index, name): name None for namespaces, "" for other blocks
    for index, token in enumerate(tokens):
        if token.kind != "punct" or token.text not in ("{", "}"):
            continue
        if token.text == "}":
            if stack:
                start, name = stack.pop()
                if name:
                    spans.append((start, index, name))
        elif any(name is not None for _, name in stack):
            stack.append((index, ""))
        elif _opens_namespace(tokens, index):
            stack.append((index, None))
        else:
            stack.append((index, _definition_name(tokens, index) or ""))
    spans.extend((start, len(tokens), name) for start, name in stack if name)
    return sorted(spans)


def _enclosing(spans, starts, index):
    position = bisect.bisect_right(starts, index) - 1
    if position >= 0 and spans[position][0] < index < spans[position][1]:
        return spans[position][2]
    return None


def _character(code, notes):
    if code > 0x10FFFF or 0xD800 <= code <= 0xDFFF:
        notes.append(f"U+{code:04X} is not a character")
        return "\N{REPLACEMENT CHARACTER}"
    return chr(code)


def _utf8(data, notes):
    try:
        return bytes(data).decode("utf-8")
    except UnicodeDecodeError:
        notes.append("not valid UTF-8")
        return bytes(data).decode("utf-8", "replace")


def _units(body, narrow, raw, notes):
    """Code units of a literal's body: bytes when narrow, else code points."""
    units = []

    def plain(text):
        if narrow:
            units.extend(text.encode("utf-8", "surrogateescape"))
        else:
            units.extend(map(ord, text))

    if raw:
        plain(body)
        return units
    end = 0
    for match in _ESCAPE_RE.finditer(body):
        plain(body[end : match.start()])
        end = match.end()
        hexadecimal, octal, short, long, other = match.groups()
        if short or long:
            code = int(short or long, 16)
            if narrow:
                units.extend(_character(code, notes).encode("utf-8"))
                continue
        elif hexadecimal:
            code = int(hexadecimal, 16)
        elif octal:
            code = int(octal, 8)
        elif other in _SIMPLE_ESCAPES:
            code = _SIMPLE_ESCAPES[other]
        else:
            notes.append(_clean(f"unknown escape {match.group()}"))
            plain(match.group()[1:])
            continue
        if narrow and code > 0xFF:
            notes.append(f"escape {match.group()} does not fit in a char")
            code &= 0xFF
        units.append(code)
    plain(body[end:])
    return units


def decode_literals(tokens):
    r"""Text of adjacent string literal tokens, joined as the compiler joins them.

    Escapes are resolved per literal and narrow literals are decoded as UTF-8
    after joining, so "\xe4" "\xb8\xad" is one character. Returns (text, notes).
    """
    notes, parts, pending = [], [], bytearray()
    for token in tokens:
        match = _LITERAL_PREFIX_RE.match(token.text)
        prefix, raw = match.group(1), match.group(2)
        body = token.text[match.end() : -1]
        if raw:
            delimiter = body[: body.index("(")]
            body = body[len(delimiter) + 1 : len(body) - len(delimiter) - 1]
        if prefix in ("u", "U", "L"):
            notes.append(f"{prefix} prefix: not a char literal")
            parts.append(_utf8(pending, notes))
            pending = bytearray()
            codes = _units(body, False, raw, notes)
            parts.append("".join(_character(code, notes) for code in codes))
        else:
            pending += bytes(_units(body, True, raw, notes))
    parts.append(_utf8(pending, notes))
    return "".join(parts), list(dict.fromkeys(notes))


def _matching(tokens, open_index):
    depth = 0
    for index in range(open_index, len(tokens)):
        text = tokens[index].text
        if text in _CLOSING:
            depth += 1
        elif text in (")", "]", "}"):
            depth -= 1
            if depth == 0:
                return index
    return None


def _strip_parentheses(tokens):
    while (
        len(tokens) >= 2
        and tokens[0].text == "("
        and _matching(tokens, 0) == len(tokens) - 1
    ):
        tokens = tokens[1:-1]
    return tokens


def _describe(tokens):
    """(kind, decoded text, notes) of one argument."""
    inner = _strip_parentheses(tokens)
    if inner and all(token.kind == "string" for token in inner):
        text, notes = decode_literals(inner)
        return "literal", text, notes
    if len(inner) == 1 and inner[0].text in ("NULL", "nullptr"):
        return "null", None, []
    return "expression", None, []


def _literal_runs(tokens):
    """Adjacent string literals, split where a preprocessor line comes between."""
    runs = []
    previous = None
    for token in tokens:
        if token.kind != "string":
            previous = None
            continue
        if previous is not None and previous.directive == token.directive:
            runs[-1].append(token)
        else:
            runs.append([token])
        previous = token
    return runs


def _source(tokens):
    """Tokens as written, each run of whitespace and comments shown as one space."""
    text = _clean(
        "".join(
            (" " if index and token.gap else "") + token.text
            for index, token in enumerate(tokens)
        )
    )
    return text if len(text) <= SOURCE_LIMIT else text[:SOURCE_LIMIT] + " [...]"


def _call_entries(api, tokens, index, arguments, stop, lines, function, macro):
    """((call offset, position), entry) for each text parameter of one call."""
    call = tokens[index]
    problem = None
    if arguments is None:
        problem = "unparsed", KINDS["unparsed"]
    elif tokens[stop].directive != call.directive:
        problem = "conditional", "preprocessor lines inside the call"
    elif len(arguments) != api.parameter_count:
        problem = (
            "arity-mismatch",
            f"{len(arguments)} arguments, the header declares {api.parameter_count}",
        )
    results = []
    for position, parameter in api.text_arguments:
        notes = [f"in #define {macro}"] if macro else []
        text = None
        if problem:
            kind, note = problem
            notes.append(note)
            argument, anchor = tokens[index + 2 : stop], call
        else:
            argument = arguments[position]
            anchor = argument[0] if argument else call
            kind, text, literal_notes = _describe(argument)
            notes += literal_notes
        embedded = []
        if kind not in ("literal", "null"):
            embedded = [decode_literals(run)[0] for run in _literal_runs(argument)]
        texts = embedded if text is None else [text]
        has_latin = any(_LATIN_WORD_RE.search(value) for value in texts)
        has_chinese = any(_HAN_RE.search(value) for value in texts)
        if kind == "literal":
            classification = "neutral"
            if has_chinese:
                classification = "chinese"
            elif has_latin:
                classification = "needing-review"
        else:
            classification = "neutral" if kind == "null" else "dynamic"
        line, column = lines.position(anchor.start)
        entry = {
            "line": line,
            "column": column,
            "enclosing_function": function,
            "function": api.name,
            "argument_index": position,
            "parameter": parameter,
            "kind": kind,
            "classification": classification,
            "has_latin_words": has_latin,
            "has_chinese": has_chinese,
            "text": text,
            "embedded_literals": embedded,
            "source": _source(argument),
            "notes": notes,
        }
        results.append(((call.start, position), entry))
    return results


def scan_text(text):
    """Text arguments of UI_APIS calls in one C/C++ source.

    Returns entries (without file and scope) in source order, the function name
    of each call and (line, message) problems met while lexing.
    """
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    spliced, splices = _splice(text)
    if not any(name in spliced for name in UI_APIS):
        return ScanResult([], [], [])
    lines = _Lines(spliced, splices)
    code, directives, problems = lex(spliced)
    spans = _function_spans(code)
    starts = [span[0] for span in spans]
    streams = [(code, 0, None)]
    for directive in directives:
        body = _macro_body(directive)
        if body is not None:
            streams.append((directive, body, directive[2].text))
    found, calls = [], []
    for tokens, first, macro in streams:
        for index, api, arguments, stop in _calls(tokens, first):
            function = None if macro else _enclosing(spans, starts, index)
            calls.append((tokens[index].start, api.name))
            found += _call_entries(
                api, tokens, index, arguments, stop, lines, function, macro
            )
    found.sort(key=lambda item: item[0])
    calls.sort()
    return ScanResult(
        [entry for _, entry in found],
        [name for _, name in calls],
        [(lines.position(offset)[0], message) for offset, message in problems],
    )


def _relative(root, path):
    return _clean(path.relative_to(root).as_posix())


def _walk(root, scope):
    """(path, full path) of the sources and (path, reason) of what was skipped."""
    base = root / scope
    if base.is_symlink():
        return [], [(scope, "symlink")]
    files, skipped = [], []
    for folder, directories, names in os.walk(base):
        folder = Path(folder)
        kept = []
        for name in sorted(directories):
            path = folder / name
            reason = "symlink" if path.is_symlink() else SKIPPED_DIRECTORIES.get(name)
            if reason:
                skipped.append((_relative(root, path), reason))
            else:
                kept.append(name)
        directories[:] = kept
        for name in sorted(names):
            path = folder / name
            if path.suffix.lower() not in SOURCE_SUFFIXES:
                continue
            if path.is_symlink():
                skipped.append((_relative(root, path), "symlink"))
            elif name.endswith(GENERATED_FONT_SUFFIX):
                skipped.append((_relative(root, path), "generated-font"))
            else:
                files.append((_relative(root, path), path))
    return files, skipped


def _declarations(text):
    """Parameter token lists of the UI_APIS a header declares, first one wins."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    code = lex(_splice(text)[0])[0]
    found = {}
    for index in range(1, len(code) - 1):
        token = code[index]
        if token.kind != "ident" or token.text not in UI_APIS or token.text in found:
            continue
        if code[index + 1].text == "(" and _is_declaration(code, index, 0):
            found[token.text] = split_arguments(code, index + 1)[0]
    return found


def _signature_problem(api, parameters):
    if parameters is None:
        return "the declaration's brackets do not close"
    if len(parameters) != api.parameter_count:
        return (
            f"{len(parameters)} parameters, the mapping expects {api.parameter_count}"
        )
    for position, name in api.text_arguments:
        words = [token.text for token in parameters[position]]
        if words != ["const", "char", "*", name]:
            return (
                f"parameter {position} is '{' '.join(words)}', "
                f"the mapping expects 'const char* {name}'"
            )
    return None


def verify_signatures(root):
    """Compare UI_APIS with the declarations in the headers under root.

    Returns {function: (status, detail)}; status is verified, header-missing,
    declaration-missing or mismatch.
    """
    declared = {}
    for header in sorted({api.header for api in UI_APIS.values()}):
        path = Path(root) / header
        if path.is_file() and not path.is_symlink():
            text = path.read_bytes().decode("utf-8-sig", "surrogateescape")
            declared[header] = _declarations(text)
    results = {}
    for name in sorted(UI_APIS):
        api = UI_APIS[name]
        if api.header not in declared:
            results[name] = ("header-missing", None)
        elif name not in declared[api.header]:
            results[name] = ("declaration-missing", None)
        else:
            problem = _signature_problem(api, declared[api.header][name])
            results[name] = ("mismatch", problem) if problem else ("verified", None)
    return results


def _counts(files=True):
    keys = ("files_scanned", "skipped", "files_with_entries") if files else ()
    keys += ("calls", "entries") + CLASSIFICATIONS + ("chinese_with_latin_words",)
    return dict.fromkeys(keys, 0)


def inventory(root, scopes=SCOPES):
    """The report for the sources under root, as render_json() writes it."""
    root = Path(root)
    by_scope = {scope: _counts() for scope in scopes}
    by_function = {name: _counts(files=False) for name in sorted(UI_APIS)}
    scope_list, sources, skipped, warnings, entries = [], [], [], [], []
    for scope in scopes:
        present = (root / scope).is_dir()
        scope_list.append({"path": scope, "present": present})
        if present:
            found, passed = _walk(root, scope)
            sources += [(path, full, scope) for path, full in found]
            skipped += [(path, reason, scope) for path, reason in passed]
    for path, full, scope in sorted(sources):
        try:
            data = full.read_bytes()
        except OSError as error:
            skipped.append((path, "unreadable", scope))
            reason = error.strerror or type(error).__name__
            warnings.append((path, None, f"cannot read: {reason}"))
            continue
        if b"\0" in data:
            skipped.append((path, "binary", scope))
            continue
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = data.decode("utf-8-sig", "surrogateescape")
            warnings.append((path, None, "not valid UTF-8"))
        result = scan_text(text)
        counts = by_scope[scope]
        counts["files_scanned"] += 1
        counts["files_with_entries"] += bool(result.entries)
        counts["calls"] += len(result.calls)
        for name in result.calls:
            by_function[name]["calls"] += 1
        for entry in result.entries:
            for bucket in (counts, by_function[entry["function"]]):
                bucket["entries"] += 1
                bucket[entry["classification"]] += 1
                if entry["classification"] == "chinese" and entry["has_latin_words"]:
                    bucket["chinese_with_latin_words"] += 1
            entries.append({"scope": scope, "file": path, **entry})
        warnings += [(path, line, message) for line, message in result.problems]
    for _, _, scope in skipped:
        by_scope[scope]["skipped"] += 1
    overall = _counts()
    for counts in by_scope.values():
        for key, value in counts.items():
            overall[key] += value
    checks = verify_signatures(root)
    apis = [
        {
            "function": name,
            "header": api.header,
            "parameter_count": api.parameter_count,
            "text_arguments": [
                {"index": position, "parameter": parameter}
                for position, parameter in api.text_arguments
            ],
            "signature": checks[name][0],
            "signature_detail": checks[name][1],
        }
        for name, api in sorted(UI_APIS.items())
    ]
    warnings.sort(key=lambda warning: (warning[0], warning[1] or 0, warning[2]))
    return {
        "tool": "scripts/audit_ui_strings.py",
        "format_version": 1,
        "coverage_note": COVERAGE_NOTE,
        "classification_rules": CLASSIFICATION_RULES,
        "kinds": KINDS,
        "conventions": CONVENTIONS,
        "scopes": scope_list,
        "totals": {
            "overall": overall,
            "by_scope": by_scope,
            "by_function": by_function,
        },
        "apis": apis,
        "skipped": [
            {"scope": scope, "path": path, "reason": reason}
            for path, reason, scope in sorted(skipped)
        ],
        "warnings": [
            {"file": path, "line": line, "message": message}
            for path, line, message in warnings
        ],
        "entries": entries,
    }


def render_json(report):
    """JSON with one line per scope, API, skipped path, warning and entry."""
    lines = ["{"]
    for number, (key, value) in enumerate(report.items()):
        comma = "," if number + 1 < len(report) else ""
        if isinstance(value, list) and value:
            lines.append(f"  {json.dumps(key)}: [")
            for item_number, item in enumerate(value):
                separator = "," if item_number + 1 < len(value) else ""
                lines.append(f"    {json.dumps(item, ensure_ascii=False)}{separator}")
            lines.append(f"  ]{comma}")
        else:
            text = json.dumps(value, ensure_ascii=False, indent=2).replace("\n", "\n  ")
            lines.append(f"  {json.dumps(key)}: {text}{comma}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_summary(report):
    """Plain-text totals by scope."""
    columns = ("files_scanned", "calls", "entries") + CLASSIFICATIONS
    rows = [("scope", "files", "calls", "entries", "review") + CLASSIFICATIONS[1:]]
    for scope, counts in report["totals"]["by_scope"].items():
        rows.append((scope,) + tuple(counts[column] for column in columns))
    overall = report["totals"]["overall"]
    rows.append(("total",) + tuple(overall[column] for column in columns))
    lines = [
        row[0].ljust(24) + "".join(f"{value:>9}" for value in row[1:]) for row in rows
    ]
    verified = sum(api["signature"] == "verified" for api in report["apis"])
    lines.append(f"Header signatures verified: {verified} of {len(report['apis'])}")
    lines.append(COVERAGE_NOTE)
    return "\n".join(lines)


def _output_problem(root, output):
    """Why the JSON cannot be written to output, or None."""
    if output.is_dir():
        return "is a directory"
    if not output.parent.is_dir():
        return "is in a directory that does not exist"
    target = output.parent.resolve() / output.name
    for scope in SCOPES:
        folder = (root / scope).resolve()
        if target == folder or folder in target.parents:
            return f"is inside the audited sources ({scope})"
    return None


def _write_stdout(data):
    buffer = getattr(sys.stdout, "buffer", None)
    if buffer is None:
        sys.stdout.write(data)
    else:
        sys.stdout.flush()
        buffer.write(data.encode("utf-8"))
        buffer.flush()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--root",
        type=Path,
        default=ROOT,
        help="repository to scan (default: this checkout)",
    )
    parser.add_argument(
        "--output", type=Path, help="JSON file to write (default: standard output)"
    )
    args = parser.parse_args(argv)
    if not args.root.is_dir():
        parser.error(f"--root {args.root} is not a directory")
    root = args.root.resolve()
    if not any((root / scope).is_dir() for scope in SCOPES):
        parser.error(f"--root {args.root} contains none of: {', '.join(SCOPES)}")
    if args.output is not None:
        problem = _output_problem(root, args.output)
        if problem:
            parser.error(f"--output {args.output} {problem}")
    report = inventory(root)
    if report["totals"]["overall"]["files_scanned"] == 0:
        parser.error(f"--root {args.root} has no readable C/C++ sources to audit")
    data = render_json(report)
    if args.output is None:
        _write_stdout(data)
        print(render_summary(report), file=sys.stderr)
    else:
        try:
            args.output.write_bytes(data.encode("utf-8"))
        except OSError as error:
            print(
                f"error: cannot write {args.output}: {error.strerror}", file=sys.stderr
            )
            return 1
        print(render_summary(report))
        print(f"Wrote {args.output}")
    stale = [
        f"{api['function']}: {api['signature']}"
        + (f" ({api['signature_detail']})" if api["signature_detail"] else "")
        for api in report["apis"]
        if api["signature"] in ("declaration-missing", "mismatch")
    ]
    if stale:
        print("error: UI_APIS does not match the headers:", file=sys.stderr)
        for line in stale:
            print(f"  {line}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
