#!/usr/bin/env python3
"""Conservative Claude Code harness to Codex harness migration helper."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


PATH_REPLACEMENTS = (
    (".claude/project", ".codex/project"),
    (".claude/skills", ".codex/skills"),
    (".claude/commands", ".codex/skills"),
    (".claude/agents", ".codex/agents"),
    (".claude/hooks", ".codex/hooks"),
    (".claude/rules", ".codex/rules"),
    (".claude/docs", ".codex/docs"),
    (".claude/", ".codex/"),
)

DEFAULT_RULES = """\
def main(ctx):
    deny = [
        (["git", "reset", "--hard"], "Do not destroy local worktree/history state without explicit approval."),
        (["git", "clean"], "Do not remove untracked files without explicit approval."),
        (["git", "push", "--force"], "Do not force-push without explicit approval."),
        (["git", "push", "-f"], "Do not force-push without explicit approval."),
        (["git", "branch", "-D"], "Do not delete branches without explicit approval."),
        (["git", "checkout", "."], "Do not rewrite the worktree without explicit approval."),
        (["git", "restore", "."], "Do not rewrite the worktree without explicit approval."),
        (["bd", "init", "--force"], "Do not reinitialize the Beads store without explicit approval."),
        (["bd", "init", "--reinit-local"], "Do not reinitialize the Beads store without explicit approval."),
    ]
    for prefix, reason in deny:
        prefix_rule(prefix, "forbidden", reason)
"""


@dataclass
class Report:
    dry_run: bool
    actions: list[str] = field(default_factory=list)
    skips: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def action(self, message: str) -> None:
        self.actions.append(message)

    def skip(self, message: str) -> None:
        self.skips.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def print(self) -> None:
        mode = "DRY RUN" if self.dry_run else "APPLIED"
        print(f"claude-to-codex migration: {mode}")
        print(f"actions: {len(self.actions)}")
        for item in self.actions:
            print(f"  + {item}")
        if self.skips:
            print(f"skips: {len(self.skips)}")
            for item in self.skips:
                print(f"  - {item}")
        if self.warnings:
            print(f"warnings: {len(self.warnings)}")
            for item in self.warnings:
                print(f"  ! {item}")


def normalize_text(text: str) -> str:
    for old, new in PATH_REPLACEMENTS:
        text = text.replace(old, new)
    return text


def title_from_name(name: str) -> str:
    return " ".join(part.capitalize() for part in re.split(r"[-_\s]+", name) if part)


def slug(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "migrated-command"


def split_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    raw = text[4:end]
    body = text[end + 5 :]
    data: dict[str, Any] = {}
    for line in raw.splitlines():
        if not line.strip() or line.lstrip().startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            data[key.strip()] = [
                part.strip().strip("\"'")
                for part in value[1:-1].split(",")
                if part.strip()
            ]
        else:
            data[key.strip()] = value.strip("\"'")
    return data, body.lstrip()


def toml_string(value: str) -> str:
    return json.dumps(value)


def yaml_string(value: str) -> str:
    return json.dumps(value)


def read_text_if_possible(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None


def write_text(path: Path, text: str, *, apply: bool, force: bool, report: Report) -> None:
    if path.exists() and not force:
        report.skip(f"{path} exists; use --force to overwrite")
        return
    report.action(f"write {path}")
    if not apply:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def copy_file(src: Path, dest: Path, *, apply: bool, force: bool, report: Report) -> None:
    if dest.exists() and not force:
        report.skip(f"{dest} exists; use --force to overwrite")
        return
    report.action(f"copy {src} -> {dest}")
    if not apply:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    text = read_text_if_possible(src)
    if text is None:
        shutil.copy2(src, dest)
    else:
        dest.write_text(normalize_text(text), encoding="utf-8")


def copy_tree(src: Path, dest: Path, *, apply: bool, force: bool, report: Report) -> None:
    if not src.exists():
        report.skip(f"{src} not present")
        return
    for path in sorted(src.rglob("*")):
        if path.is_dir():
            continue
        rel = path.relative_to(src)
        rel_parts = list(rel.parts)
        if rel_parts and rel_parts[-1] == "SKILL.MD":
            rel_parts[-1] = "SKILL.md"
        copy_file(path, dest.joinpath(*rel_parts), apply=apply, force=force, report=report)


def command_skill_name(rel: Path) -> str:
    stem_parts = list(rel.with_suffix("").parts)
    return slug("-".join(stem_parts))


def convert_commands(repo: Path, *, apply: bool, force: bool, report: Report) -> None:
    src = repo / ".claude" / "commands"
    if not src.exists():
        report.skip(f"{src} not present")
        return
    for path in sorted(src.rglob("*.md")):
        rel = path.relative_to(src)
        name = command_skill_name(rel)
        text = path.read_text(encoding="utf-8")
        meta, body = split_frontmatter(text)
        original_desc = str(meta.get("description") or "").strip()
        desc = (
            f"Migrated Claude slash-command workflow from .claude/commands/{rel.as_posix()}. "
            f"Use when the user asks for the former /{rel.with_suffix('').as_posix()} command"
            " or wants this workflow executed in Codex."
        )
        if original_desc:
            desc = f"{original_desc} Use this Codex skill as the migrated replacement for /{rel.with_suffix('').as_posix()}."
        skill = f"""\
---
name: {name}
description: {yaml_string(desc)}
---

# {title_from_name(name)}

This skill was migrated from `.claude/commands/{rel.as_posix()}`. Treat provider-specific instructions as historical context and adapt them to Codex before executing.

{normalize_text(body).rstrip()}
"""
        write_text(repo / ".codex" / "skills" / name / "SKILL.md", skill, apply=apply, force=force, report=report)


def infer_sandbox(name: str, meta: dict[str, Any], body: str) -> str:
    tools = meta.get("tools")
    if isinstance(tools, list) and tools and set(tools).issubset({"Read", "Grep", "Glob"}):
        return "read-only"
    text = f"{name}\n{meta.get('description', '')}\n{body}".lower()
    if any(word in text for word in ("read-only", "review", "research", "planner", "planning")):
        return "read-only"
    return "workspace-write"


def convert_agents(repo: Path, *, apply: bool, force: bool, report: Report) -> None:
    src = repo / ".claude" / "agents"
    if not src.exists():
        report.skip(f"{src} not present")
        return
    for path in sorted(src.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        meta, body = split_frontmatter(text)
        name = slug(str(meta.get("name") or path.stem))
        desc = str(meta.get("description") or f"Migrated agent from {path}").strip()
        instructions = (
            "Migrated from a Claude Code agent. Review provider-specific assumptions before use.\n\n"
            + normalize_text(body).strip()
        )
        sandbox = infer_sandbox(name, meta, body)
        toml = "\n".join(
            [
                f"name = {toml_string(name)}",
                f"description = {toml_string(desc)}",
                f"sandbox_mode = {toml_string(sandbox)}",
                f"developer_instructions = {toml_string(instructions)}",
                "",
            ]
        )
        if "model" in meta:
            report.warn(f"did not carry Claude model id from {path}; review Codex model selection manually")
        write_text(repo / ".codex" / "agents" / f"{name}.toml", toml, apply=apply, force=force, report=report)


def convert_hook_command(command: str) -> str:
    command = command.replace('"$CLAUDE_PROJECT_DIR"/.claude/', ".codex/")
    command = command.replace("$CLAUDE_PROJECT_DIR/.claude/", ".codex/")
    command = command.replace(".claude/hooks/", ".codex/hooks/")
    return command


def convert_hooks_json(repo: Path, *, apply: bool, force: bool, report: Report) -> None:
    settings = repo / ".claude" / "settings.json"
    dest = repo / ".codex" / "hooks.json"
    if not settings.exists():
        report.skip(f"{settings} not present")
        return
    try:
        data = json.loads(settings.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        report.warn(f"cannot parse {settings}: {exc}")
        return
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        report.skip(f"{settings} has no hooks object")
        return
    for entries in hooks.values():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            for hook in entry.get("hooks", []):
                if isinstance(hook, dict) and isinstance(hook.get("command"), str):
                    hook["command"] = convert_hook_command(hook["command"])
    write_text(dest, json.dumps({"hooks": hooks}, indent=2) + "\n", apply=apply, force=force, report=report)
    report.warn("review migrated hooks against Codex hook payload schemas before relying on enforcement")


def write_defaults(repo: Path, *, apply: bool, force: bool, report: Report) -> None:
    config = """\
[features]
hooks = true

[agents]
max_depth = 1
max_threads = 6
"""
    write_text(repo / ".codex" / "config.toml", config, apply=apply, force=force, report=report)
    write_text(repo / ".codex" / "rules" / "default.rules", DEFAULT_RULES, apply=apply, force=force, report=report)
    notes = """\
# Codex Migration Notes

This file was generated by `$migrate-claude-to-codex`.

Review the migrated assets before treating them as semantically equivalent to the Claude Code harness.

## Mechanical Mapping

- `.claude/skills/` -> `.codex/skills/`
- `.claude/commands/` -> `.codex/skills/`
- `.claude/agents/` -> `.codex/agents/`
- `.claude/project/` -> `.codex/project/`
- `.claude/docs/` -> `.codex/docs/`
- `.claude/rules/` -> `.codex/rules/`
- `.claude/hooks/` and `.claude/settings.json` -> `.codex/hooks/` and `.codex/hooks.json`

## Required Manual Review

- Remove or adapt Claude-only model IDs and tool names.
- Validate Codex hook payload handling with fixtures.
- Update `AGENTS.md` or repo entrypoints to point at `.codex/project`.
- Run Codex discovery with `codex debug prompt-input` when available.
"""
    write_text(repo / ".codex" / "docs" / "codex-migration-notes.md", notes, apply=apply, force=force, report=report)


def migrate(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve()
    if not (repo / ".claude").exists():
        print(f"error: {repo}/.claude does not exist", file=sys.stderr)
        return 2
    report = Report(dry_run=not args.apply)
    copy_tree(repo / ".claude" / "skills", repo / ".codex" / "skills", apply=args.apply, force=args.force, report=report)
    convert_commands(repo, apply=args.apply, force=args.force, report=report)
    convert_agents(repo, apply=args.apply, force=args.force, report=report)
    copy_tree(repo / ".claude" / "project", repo / ".codex" / "project", apply=args.apply, force=args.force, report=report)
    copy_tree(repo / ".claude" / "docs", repo / ".codex" / "docs", apply=args.apply, force=args.force, report=report)
    copy_tree(repo / ".claude" / "rules", repo / ".codex" / "rules", apply=args.apply, force=args.force, report=report)
    copy_tree(repo / ".claude" / "hooks", repo / ".codex" / "hooks", apply=args.apply, force=args.force, report=report)
    convert_hooks_json(repo, apply=args.apply, force=args.force, report=report)
    write_defaults(repo, apply=args.apply, force=args.force, report=report)
    if (repo / "AGENTS.md").exists():
        report.warn("review AGENTS.md manually so it points at .codex/project and Codex skills")
    else:
        report.warn("add AGENTS.md or another Codex entrypoint for repo-specific instructions")
    report.print()
    return 0


def validate_skill_frontmatter(skill: Path) -> list[str]:
    errors: list[str] = []
    text = skill.read_text(encoding="utf-8")
    meta, _ = split_frontmatter(text)
    if not meta.get("name"):
        errors.append(f"{skill}: missing name")
    if not meta.get("description"):
        errors.append(f"{skill}: missing description")
    expected = skill.parent.name
    if meta.get("name") != expected:
        errors.append(f"{skill}: name {meta.get('name')!r} does not match folder {expected!r}")
    return errors


def run_codex_discovery(repo: Path) -> tuple[bool, str]:
    codex = shutil.which("codex")
    if not codex:
        return False, "codex executable not found"
    env = os.environ.copy()
    codex_home = Path(env.get("CODEX_HOME") or "/tmp/codex-harness-verify")
    codex_home.mkdir(parents=True, exist_ok=True)
    env["CODEX_HOME"] = str(codex_home)
    proc = subprocess.run(
        [codex, "debug", "prompt-input", "verify codex harness discovery"],
        cwd=repo,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    output = proc.stdout
    markers = (f"{repo}/.codex/skills", ".codex/skills/")
    if proc.returncode == 0 and any(marker in output for marker in markers):
        return True, "codex discovery found repo-local .codex/skills"
    return False, "codex discovery did not show repo-local .codex/skills"


def verify(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve()
    errors: list[str] = []
    warnings: list[str] = []
    if not (repo / ".codex").exists():
        errors.append(f"{repo}/.codex does not exist")
    hooks = repo / ".codex" / "hooks.json"
    if hooks.exists():
        try:
            json.loads(hooks.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{hooks}: {exc}")
    config = repo / ".codex" / "config.toml"
    if config.exists():
        try:
            tomllib.loads(config.read_text(encoding="utf-8"))
        except tomllib.TOMLDecodeError as exc:
            errors.append(f"{config}: {exc}")
    for agent in sorted((repo / ".codex" / "agents").glob("*.toml")):
        try:
            tomllib.loads(agent.read_text(encoding="utf-8"))
        except tomllib.TOMLDecodeError as exc:
            errors.append(f"{agent}: {exc}")
    for skill in sorted((repo / ".codex" / "skills").glob("*/SKILL.md")):
        errors.extend(validate_skill_frontmatter(skill))
    if not args.skip_codex:
        ok, message = run_codex_discovery(repo)
        if ok:
            print(f"codex: {message}")
        else:
            warnings.append(message)
    if errors:
        print("verification failed:")
        for error in errors:
            print(f"  - {error}")
        return 1
    print("verification passed")
    for warning in warnings:
        print(f"warning: {warning}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    migrate_parser = sub.add_parser("migrate", help="Plan or apply a Claude-to-Codex migration")
    migrate_parser.add_argument("--repo", default=".", help="repository root, default: current directory")
    migrate_parser.add_argument("--apply", action="store_true", help="write files; default is dry-run")
    migrate_parser.add_argument("--force", action="store_true", help="overwrite existing migrated files")
    migrate_parser.set_defaults(func=migrate)
    verify_parser = sub.add_parser("verify", help="verify migrated Codex harness structure")
    verify_parser.add_argument("--repo", default=".", help="repository root, default: current directory")
    verify_parser.add_argument("--skip-codex", action="store_true", help="skip codex debug prompt-input discovery")
    verify_parser.set_defaults(func=verify)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
