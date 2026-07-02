#!/usr/bin/env python3
"""Initialize report directories for codebase architecture research."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


AGENT_REPORTS = [
    "00-index.md",
    "01-core-architecture.md",
    "02-runtime-lifecycle.md",
    "03-data-state-and-persistence.md",
    "04-integration-and-extension-points.md",
    "05-operational-model.md",
    "90-open-questions.md",
]


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip()).strip("-").lower()
    return slug or "codebase"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create the standard docs/research/codebases/<slug>/ report tree."
    )
    parser.add_argument("codebase_path", help="Path to the codebase being studied, e.g. external/<name>")
    parser.add_argument(
        "--root",
        default="docs/research/codebases",
        help="Report root directory, default: docs/research/codebases",
    )
    parser.add_argument("--slug", help="Override the slug derived from codebase_path")
    args = parser.parse_args()

    codebase_path = Path(args.codebase_path)
    slug = args.slug or slugify(codebase_path.name)
    base = Path(args.root) / slug
    agent_dir = base / "agent"
    html_dir = base / "html"

    agent_dir.mkdir(parents=True, exist_ok=True)
    html_dir.mkdir(parents=True, exist_ok=True)

    print(f"base: {base}")
    print("agent reports:")
    for report in AGENT_REPORTS:
        print(f"  {agent_dir / report}")
    print("html reports:")
    print(f"  {html_dir / 'index.html'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
