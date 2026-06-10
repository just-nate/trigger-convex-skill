#!/usr/bin/env bash
set -euo pipefail

# ELI5: This script copies the skill into an agent skills folder so other agents can find it.
REPO_URL="https://github.com/just-nate/trigger-convex-skill.git"
SKILL_NAME="trigger-convex"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.agents/skills}"
INSTALL_DIR="$SKILLS_DIR/$SKILL_NAME"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$SKILLS_DIR"

# ELI5: Clone only what we need, then copy the skill folder into place.
git clone --depth 1 "$REPO_URL" "$TMP_DIR/repo" >/dev/null 2>&1
rm -rf "$INSTALL_DIR"
cp -R "$TMP_DIR/repo/skills/$SKILL_NAME" "$INSTALL_DIR"

printf 'Installed %s skill to %s\n' "$SKILL_NAME" "$INSTALL_DIR"
printf 'Restart or reload your agent so it discovers the new skill.\n'
