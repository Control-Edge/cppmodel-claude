#!/usr/bin/env python3
"""Build plugins/cppmodel-portable from plugins/cppmodel.

plugins/cppmodel is the Claude Code plugin and the only source that gets edited. This script
derives from it an Agent Plugins package (https://agent-plugins.org) that OpenAI Codex, Cursor and
GitHub Copilot (CLI and VS Code) install, and that is also a Gemini CLI extension:

- skills/<name>/SKILL.md: each skill with an Agent Skills-conformant name (`<name>`, matching its
  directory, instead of Claude Code's `cppmodel:<name>`), a quoted description, and the same
  reading notes the MCP server's get_guide prepends, translating what's specific to Claude Code.
  `${CLAUDE_PLUGIN_ROOT}` becomes `<plugin>`, the package root.
- scripts/: copied unchanged, so `<plugin>/scripts/...` resolves inside the package.
- plugin.json, mcp.json: Agent Plugins 1.0 manifests (Codex settings under extensions.com.openai).
- gemini-extension.json: the Gemini CLI manifest, with the same MCP server.

It also writes the marketplace files those agents read at the repository root:
.agents/plugins/marketplace.json (Codex), .github/plugin/marketplace.json (Copilot) and
.cursor-plugin/marketplace.json (Cursor), all listing the portable package.

Versions and descriptions come from plugins/cppmodel/.claude-plugin/plugin.json and
.claude-plugin/marketplace.json.

Usage:
    python3 tools/build-portable-plugin.py           # regenerate plugins/cppmodel-portable
    python3 tools/build-portable-plugin.py --check   # exit 1 if it is out of date
"""

import argparse
import filecmp
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "plugins" / "cppmodel"
TARGET = REPO / "plugins" / "cppmodel-portable"

MCP_URL = "https://mcp.cppmodel.com/mcp"
OAUTH_CLIENT_ID = "cppmodel-mcp"

# Agent Skills: lowercase alphanumerics and single hyphens, not at either end, at most 64 chars.
SKILL_NAME = re.compile(r"^(?=.{1,64}$)[a-z0-9]+(-[a-z0-9]+)*$")

READING_NOTES = """\
## Reading notes

- This is the cppmodel plugin's `{name}` skill. It was written for Claude Code, but applies to any
  AI assistant; these notes translate what's specific to Claude Code.
- `cppmodel:<name>` ("the `cppmodel:<name>` skill") is this plugin's `<name>` skill, in
  `<plugin>/skills/<name>/SKILL.md`: when this one says to use it, load that skill and follow it.
- "The `cppmodel` MCP server" is the one this plugin installs (`{mcp_url}`).
- `<plugin>` is the root of this plugin: the directory two levels above this file.
- "Ask with `AskUserQuestion`": use your client's multiple-choice question tool if it has one,
  otherwise ask in a message that lists the options, and wait for the answer.
- "Authenticate with `/mcp`": sign in to the `cppmodel` MCP server the way your client does.
- Other remarks about Claude Code only apply there.

---

"""


def fail(message):
    sys.exit(f"build-portable-plugin: {message}")


def split_frontmatter(text, path):
    match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not match:
        fail(f"{path}: no YAML frontmatter")
    fields = {}
    for line in match.group(1).splitlines():
        key, sep, value = line.partition(": ")
        if not sep:
            fail(f"{path}: unexpected frontmatter line {line!r}")
        fields[key] = value
    return fields, text[match.end():]


def convert_skill(source_dir, target_dir):
    name = source_dir.name
    if not SKILL_NAME.match(name):
        fail(f"{source_dir}: '{name}' isn't a valid Agent Skills name")
    skill_md = source_dir / "SKILL.md"
    fields, body = split_frontmatter(skill_md.read_text(encoding="utf-8"), skill_md)
    if fields.get("name") != f"cppmodel:{name}":
        fail(f"{skill_md}: expected name 'cppmodel:{name}', found {fields.get('name')!r}")
    description = fields.get("description", "")
    if not 1 <= len(description) <= 1024:
        fail(f"{skill_md}: description must be 1-1024 characters, is {len(description)}")

    body = body.replace("${CLAUDE_PLUGIN_ROOT}", "<plugin>").lstrip("\n")
    notes = READING_NOTES.format(name=name, mcp_url=MCP_URL)
    frontmatter = f"---\nname: {name}\ndescription: {json.dumps(description, ensure_ascii=False)}\n---\n\n"

    shutil.copytree(source_dir, target_dir)
    (target_dir / "SKILL.md").write_text(frontmatter + notes + body, encoding="utf-8", newline="\n")


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


def build(out):
    claude_manifest = json.loads((SOURCE / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))

    (out / "skills").mkdir(parents=True)
    for skill_dir in sorted(p for p in (SOURCE / "skills").iterdir() if p.is_dir()):
        convert_skill(skill_dir, out / "skills" / skill_dir.name)
    shutil.copytree(SOURCE / "scripts", out / "scripts")

    write_json(out / "plugin.json", {
        "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
        "name": claude_manifest["name"],
        "version": claude_manifest["version"],
        "description": claude_manifest["description"],
        "author": claude_manifest["author"],
        "homepage": claude_manifest["homepage"],
        "repository": "https://github.com/Control-Edge/cppmodel-claude",
        "license": claude_manifest["license"],
        "keywords": claude_manifest["keywords"],
        "extensions": {
            "com.openai": {
                "interface": {
                    "displayName": claude_manifest["displayName"],
                    "shortDescription": claude_manifest["description"],
                    "developerName": claude_manifest["author"]["name"],
                    "websiteURL": claude_manifest["homepage"],
                },
            },
        },
    })

    write_json(out / "mcp.json", {
        "$schema": "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
        "mcpServers": {
            "cppmodel": {
                "type": "streamable-http",
                "url": MCP_URL,
                "extensions": {
                    "com.openai": {
                        "auth": {
                            "type": "oauth",
                            "client": {
                                "mode": "provided",
                                "clientId": OAUTH_CLIENT_ID,
                                "tokenEndpointAuthMethod": "none",
                            },
                        },
                    },
                },
            },
        },
    })

    write_json(out / "gemini-extension.json", {
        "name": claude_manifest["name"],
        "version": claude_manifest["version"],
        "description": claude_manifest["description"],
        "mcpServers": {
            "cppmodel": {
                "httpUrl": MCP_URL,
                "oauth": {
                    "enabled": True,
                    "clientId": OAUTH_CLIENT_ID,
                },
            },
        },
    })

    (out / "README.md").write_text(
        "# CppModel Toolkit (portable)\n\n"
        "Generated from `plugins/cppmodel` by `tools/build-portable-plugin.py`. Don't edit it here:\n"
        "edit the Claude Code plugin and regenerate. Install instructions are in the repository's\n"
        "README.\n",
        encoding="utf-8", newline="\n")


def marketplaces():
    """The repo-root marketplace files of the other agents, from .claude-plugin/marketplace.json."""
    claude = json.loads((REPO / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8"))
    entry = next(p for p in claude["plugins"] if p["source"] == "./plugins/cppmodel")
    source = "./" + TARGET.relative_to(REPO).as_posix()
    listing = {
        "name": claude["name"],
        "owner": claude["owner"],
        "plugins": [{
            "name": entry["name"],
            "source": source,
            "description": entry["description"],
            "version": entry["version"],
            "license": entry["license"],
        }],
    }
    codex = {
        "name": claude["name"],
        "interface": {"displayName": "CppModel Tools"},
        "plugins": [{
            "name": entry["name"],
            "source": {"source": "local", "path": source},
            "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
            "category": "Coding",
        }],
    }
    return {
        ".agents/plugins/marketplace.json": codex,     # OpenAI Codex
        ".github/plugin/marketplace.json": listing,    # GitHub Copilot
        ".cursor-plugin/marketplace.json": listing,    # Cursor
    }


def same_tree(a, b):
    cmp = filecmp.dircmp(a, b)
    if cmp.left_only or cmp.right_only or cmp.funny_files:
        return False
    _, mismatch, errors = filecmp.cmpfiles(a, b, cmp.common_files, shallow=False)
    if mismatch or errors:
        return False
    return all(same_tree(a / d, b / d) for d in cmp.common_dirs)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true", help="fail if the committed output is stale")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "cppmodel-portable"
        build(out)
        listings = {}
        for path, data in marketplaces().items():
            listings[path] = Path(tmp) / path
            listings[path].parent.mkdir(parents=True, exist_ok=True)
            write_json(listings[path], data)

        if args.check:
            stale = [p for p, f in listings.items()
                     if not (REPO / p).is_file() or not filecmp.cmp(f, REPO / p, shallow=False)]
            if not TARGET.is_dir() or not same_tree(out, TARGET):
                stale.insert(0, TARGET.relative_to(REPO).as_posix())
            if stale:
                fail(f"out of date: {', '.join(stale)}: run tools/build-portable-plugin.py")
            return
        if TARGET.exists():
            shutil.rmtree(TARGET)
        shutil.copytree(out, TARGET)
        for path, f in listings.items():
            (REPO / path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f, REPO / path)
    print(f"Wrote {TARGET.relative_to(REPO)} and {', '.join(listings)}")


if __name__ == "__main__":
    main()
