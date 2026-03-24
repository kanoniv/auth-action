#!/usr/bin/env bash
# check-scope.sh - PreToolUse hook for /delegate skill
# Supports hierarchical scopes: git.push.{repo}.{branch}
# Pattern matches gstack's check-careful.sh / check-freeze.sh
set -euo pipefail

# Read stdin (JSON with tool_input)
INPUT=$(cat)

TOKEN_FILE="/tmp/.kanoniv-session-token"
if [ ! -f "$TOKEN_FILE" ]; then
  echo '{}'
  exit 0
fi

TOKEN=$(cat "$TOKEN_FILE")
if [ -z "$TOKEN" ]; then
  echo '{}'
  exit 0
fi

# Extract the "command" field value from tool_input
# Try grep/sed first (handles 99% of cases), fall back to Python for escaped quotes
CMD=$(printf '%s' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)

# Python fallback if grep returned empty (e.g., escaped quotes in command)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("tool_input",{}).get("command",""))' 2>/dev/null || true)
fi

# If we still couldn't extract a command, allow
if [ -z "$CMD" ]; then
  echo '{}'
  exit 0
fi

CMD_LOWER=$(printf '%s' "$CMD" | tr '[:upper:]' '[:lower:]')
SCOPE=""

# --- Git push: extract remote and branch for hierarchical scope ---
if printf '%s' "$CMD_LOWER" | grep -qE 'git\s+push' 2>/dev/null; then
  REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
  BRANCH=$(printf '%s' "$CMD" | sed -E 's/.*git\s+push\s+//' | sed -E 's/^-[^ ]+\s+//' | awk '{if(NF>=2) print $2; else if(NF==1 && $1 !~ /^-/) print ""; else print ""}' || true)
  if [ -z "$BRANCH" ]; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  fi
  SCOPE="git.push.${REPO_NAME}.${BRANCH}"

# --- Git commit: extract repo for hierarchical scope ---
elif printf '%s' "$CMD_LOWER" | grep -qE 'git\s+(commit|add|rm|reset|checkout|rebase|merge|cherry-pick)' 2>/dev/null; then
  REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
  SCOPE="git.commit.${REPO_NAME}"

# Test commands
elif printf '%s' "$CMD_LOWER" | grep -qE '(cargo\s+test|pytest|npm\s+test|npm\s+run\s+test|vitest|jest)' 2>/dev/null; then
  SCOPE="test.run"
# Build commands
elif printf '%s' "$CMD_LOWER" | grep -qE '(cargo\s+build|cargo\s+check|npm\s+run\s+build)' 2>/dev/null; then
  SCOPE="code.edit"
# Always allowed
elif printf '%s' "$CMD_LOWER" | grep -qE 'kanoniv-auth' 2>/dev/null; then
  echo '{}'; exit 0
elif printf '%s' "$CMD_LOWER" | grep -qE 'git\s+(status|log|diff|show|branch|tag|remote|fetch)' 2>/dev/null; then
  echo '{}'; exit 0
elif printf '%s' "$CMD_LOWER" | grep -qE '^(cat|head|tail|ls|find|grep|echo|printf|pwd|which|type|env|date|wc|rm|mkdir|touch|cp|mv|chmod|sed|awk|sort|curl|sleep|pip|python|node|cargo\s+--version)' 2>/dev/null; then
  echo '{}'; exit 0
elif printf '%s' "$CMD_LOWER" | grep -qE '^\[|^test\s|^if\s|^command\s' 2>/dev/null; then
  echo '{}'; exit 0
else
  SCOPE="code.edit"
fi

# --- Hierarchical scope verification ---
if [ -n "$SCOPE" ]; then
  VERIFIED=false

  # Try exact scope
  if kanoniv-auth verify --scope "$SCOPE" --token "$TOKEN" >/dev/null 2>&1; then
    VERIFIED=true
  else
    # Try parent scopes by stripping from the right
    PARENT="$SCOPE"
    while [[ "$PARENT" == *.* ]]; do
      PARENT="${PARENT%.*}"
      if kanoniv-auth verify --scope "$PARENT" --token "$TOKEN" >/dev/null 2>&1; then
        VERIFIED=true
        break
      fi
    done
  fi

  if [ "$VERIFIED" = false ]; then
    SCOPES=$(kanoniv-auth whoami --token "$TOKEN" 2>/dev/null | grep "Scopes:" | sed 's/.*Scopes:\s*//' || echo "unknown")
    printf '{"permissionDecision":"block","message":"SCOPE DENIED: requires %s\\n\\nYou have: %s\\n\\nRe-delegate with: kanoniv-auth delegate --scopes ...,%s --ttl 4h"}\n' "$SCOPE" "$SCOPES" "$SCOPE"
    exit 0
  fi
fi

echo '{}'
