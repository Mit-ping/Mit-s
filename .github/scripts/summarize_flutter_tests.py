"""Render Flutter's machine reporter into the Actions job summary, including failures.

This is diagnostic only: flutter test's exit status still controls the build.
Input may include non-JSON native library output. Never print raw test streams.
"""

import collections
import html
import json
from pathlib import Path
import re
import sys


def safe_text(value):
    text = str(value)
    text = re.sub(r"[a-zA-Z][a-zA-Z0-9+.-]*://[^\s\"'<>]+", "[URL redacted]", text)
    text = re.sub(r"\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b", "[UUID redacted]", text)
    text = re.sub(r"[A-Za-z0-9_+/=-]{40,}", "[long value redacted]", text)
    return html.escape(text[:3000])


def summarize(path):
    print(f"<h3>{html.escape(path.name)}</h3>")
    if not path.exists():
        print("<p>Not run (no report produced).</p>")
        return
    names = {}
    results = collections.Counter()
    errors = []
    completed = False
    for line in path.read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get("type")
        if kind == "testStart":
            test = event["test"]
            names[test["id"]] = test["name"]
        elif kind == "testDone" and not event.get("hidden"):
            results["skipped" if event.get("skipped") else event["result"]] += 1
        elif kind == "error":
            errors.append((event.get("testID"), event.get("error", "Unknown test error")))
        elif kind == "done":
            completed = True
    print(f"<p>Reporter completed: {completed}. Outcomes: {html.escape(str(dict(results)))}</p>")
    for test_id, error in errors[:20]:
        name = names.get(test_id, 'Test loading/runner')
        print(f"<h4>{safe_text(name)}</h4>")
        print(f"<pre>{safe_text(error)}</pre>")
        # Public run annotations remain readable when full job logs/summaries
        # require GitHub login. Escape workflow-command separators as well.
        message = safe_text(f"{name}: {error}")
        message = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print(f"::error title=Flutter test::{message}", file=sys.stderr)
    if len(errors) > 20:
        print(f"<p>{len(errors) - 20} more errors in the authenticated job logs.</p>")


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        summarize(Path(argument))
