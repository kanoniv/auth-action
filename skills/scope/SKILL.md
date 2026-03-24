---
name: scope
version: 0.1.0
description: |
  Quick scope change for an active delegation. Re-delegates with new scopes,
  keeping the same agent name and TTL. Use when asked to "change scope",
  "add code.edit", "switch to read-only", or just "/scope <scopes>".
allowed-tools:
  - Bash
  - Read
---

# /scope — Quick Scope Change

Re-delegates with new scopes without the full /delegate flow.

## Usage

The user invokes `/scope` with scopes as arguments, e.g.:
- `/scope code.edit,test.run`
- `/scope code.edit,test.run,git.commit,git.push`
- `/scope code.read,test.run`

## Flow

1. Check that `/tmp/.kanoniv-session-token` exists. If not, tell the user
   to run `/delegate` first.

2. Read the current token to get the agent name:

```bash
AGENT_NAME=$(python3 -c "
import base64, json
token = open('/tmp/.kanoniv-session-token').read().strip()
padded = token + '=' * (4 - len(token) % 4) if len(token) % 4 else token
data = json.loads(base64.urlsafe_b64decode(padded))
print(data.get('agent_name', 'claude-code'))
")
```

3. Extract the scopes from the user's message. The scopes are everything
   after `/scope` — a comma-separated list with no spaces.

4. Re-delegate with the new scopes (keep TTL at 4h):

```bash
rm -f /tmp/.kanoniv-session-token && TOKEN=$(kanoniv-auth delegate --name {agent_name} --scopes {scopes} --ttl 4h) && echo "$TOKEN" > /tmp/.kanoniv-session-token && kanoniv-auth status --agent {agent_name}
```

5. Print: "Scopes updated to: `{scopes}`"

That's it. No questions, no prompts.
