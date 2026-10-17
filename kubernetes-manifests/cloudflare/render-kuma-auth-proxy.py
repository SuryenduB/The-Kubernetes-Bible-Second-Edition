#!/usr/bin/env python3
"""
Render kuma-auth-proxy.yaml from its sources.

Mirror of render-abs-auth-proxy.py for the Uptime-Kuma gate stack; the design
rationale (determinism, rollout-on-code-change via the gate hash annotation)
is documented there and in abs-auth-proxy.tmpl. Read that header before
changing anything here.

  kuma-gate.py           -- application source, edited directly (Python)
  kuma-auth-proxy.tmpl   -- manifest skeleton with a PLACEHOLDER_GATE_CODE marker
  kuma-auth-proxy.yaml   -- GENERATED. Do not edit; edit the two inputs above.

Usage:
    python3 render-kuma-auth-proxy.py          # write kuma-auth-proxy.yaml
    python3 render-kuma-auth-proxy.py --check  # fail if output is stale (CI)

Exit codes: 0 rendered or up to date, 1 stale (--check only), 2 on error.
"""

import argparse
import hashlib
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "kuma-gate.py"
TEMPLATE = HERE / "kuma-auth-proxy.tmpl"
OUTPUT = HERE / "kuma-auth-proxy.yaml"

BLOCK = re.compile(r"^(\s*)kuma-gate\.py: \|$\n", re.MULTILINE)
PLACEHOLDER = "PLACEHOLDER_GATE_CODE"
GATE_HASH_ANNOTATION = "kubernetes-specialist/gate-sha256"


def gate_hash(code: str) -> str:
    """Stable short hash of the gate source, used to force a rollout."""
    return hashlib.sha256(code.encode()).hexdigest()[:12]


def indent_block(text: str, indent: str) -> str:
    """Indent a block scalar body. Blank lines stay blank: YAML forbids
    trailing whitespace there, and some linters reject it."""
    out = []
    for line in text.rstrip("\n").split("\n"):
        out.append(f"{indent}{line}" if line.strip() else "")
    return "\n".join(out)


def build_hash_annotation(code: str) -> str:
    return f"    {GATE_HASH_ANNOTATION}: \"{gate_hash(code)}\""


def render() -> str:
    if not SOURCE.exists():
        sys.exit(f"error: missing source {SOURCE}")
    if not TEMPLATE.exists():
        sys.exit(f"error: missing template {TEMPLATE}")

    code = SOURCE.read_text()
    # A Python file must not carry CRLF: the ConfigMap would carry it too and
    # the digest below would differ from the source file's own digest.
    if "\r\n" in code:
        sys.exit("error: kuma-gate.py has CRLF line endings; convert to LF")

    template = TEMPLATE.read_text()

    if PLACEHOLDER not in template:
        sys.exit(f"error: template has no {PLACEHOLDER} placeholder")

    # The marker sits directly under the ConfigMap's `data:` mapping; the
    # block-scalar body is indented two spaces deeper than the replaced key.
    m = re.search(rf"^([ ]*)# {PLACEHOLDER}$", template, re.MULTILINE)
    if not m:
        sys.exit(f"error: template must contain a '# {PLACEHOLDER}' marker line")
    header_indent = m.group(1)
    body_indent = header_indent + "  "

    rendered = template.replace(
        m.group(0),
        f"{header_indent}kuma-gate.py: |\n" + indent_block(code, body_indent),
    )

    # Force a rollout whenever the gate code changes.
    if GATE_HASH_ANNOTATION not in rendered:
        sys.exit(
            f"error: template has no {GATE_HASH_ANNOTATION} annotation; without it a\n"
            "gate code change would not restart the pods (ConfigMap updates do not\n"
            "trigger a rollout), so the fix would sit inert in the cluster."
        )
    rendered, replaced = re.subn(
        rf'^\s*{re.escape(GATE_HASH_ANNOTATION)}: "[^"]*"$',
        build_hash_annotation(code),
        rendered,
        flags=re.MULTILINE,
    )
    if replaced != 1:
        sys.exit(
            f"error: expected exactly 1 {GATE_HASH_ANNOTATION} annotation to replace, "
            f"found {replaced}"
        )

    return rendered


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="do not write; exit 1 if the committed manifest is stale",
    )
    args = parser.parse_args()

    try:
        rendered = render()
    except SystemExit as exc:
        print(exc, file=sys.stderr)
        return 2

    if args.check:
        if not OUTPUT.exists():
            print(f"error: {OUTPUT.name} does not exist; run without --check", file=sys.stderr)
            return 1
        current = OUTPUT.read_text()
        if current != rendered:
            print(
                f"error: {OUTPUT.name} is stale.\n"
                f"       Run: python3 {Path(__file__).name}\n"
                "       kuma-gate.py or the template changed without re-rendering.",
                file=sys.stderr,
            )
            return 1
        print(f"ok: {OUTPUT.name} is up to date (gate {gate_hash(SOURCE.read_text())})")
        return 0

    OUTPUT.write_text(rendered)
    print(f"wrote {OUTPUT.name} ({len(rendered.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
