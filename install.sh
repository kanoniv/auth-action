#!/usr/bin/env bash
# Install kanoniv-auth skills for Claude Code
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

echo "Installing kanoniv-auth skills..."

# Install kanoniv-auth CLI if needed
if ! command -v kanoniv-auth &>/dev/null; then
  echo "Installing kanoniv-auth..."
  pip install kanoniv-auth
fi

# Generate root key if needed
if [ ! -f "$HOME/.kanoniv/root.key" ]; then
  echo "Generating root key..."
  kanoniv-auth init
fi

# Symlink each skill
for skill in delegate scope ttl status audit; do
  target="$SKILLS_DIR/$skill"
  source="$SCRIPT_DIR/skills/$skill"

  if [ -L "$target" ]; then
    rm "$target"
  elif [ -d "$target" ]; then
    echo "Warning: $target exists and is not a symlink. Backing up to ${target}.bak"
    mv "$target" "${target}.bak"
  fi

  ln -s "$source" "$target"
  echo "  ✓ /$(basename "$skill")"
done

echo ""
echo "Done! Skills installed:"
echo "  /delegate  — Start a scoped session"
echo "  /scope     — Change scopes mid-session"
echo "  /ttl       — Extend session time"
echo "  /status    — Check delegation status"
echo "  /audit     — View audit trail"
echo ""
echo "Run /delegate in Claude Code to get started."
