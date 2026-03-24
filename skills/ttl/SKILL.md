---
name: ttl
version: 0.1.0
description: |
  Quick TTL change for an active delegation. Re-delegates with a new TTL,
  keeping the same agent name and scopes. Use when asked to "extend session",
  "more time", "change ttl", or just "/ttl <duration>".
allowed-tools:
  - Bash
  - Read
---

# /ttl — Quick TTL Change

Re-delegates with a new TTL without the full /delegate flow.

## Usage

The user invokes `/ttl` with a duration, e.g.:
- `/ttl 2h`
- `/ttl 30m`
- `/ttl 8h`

## Flow

1. Check that `/tmp/.kanoniv-session-token` exists. If not, tell the user
   to run `/delegate` first.

2. Read the current token to get the agent name and scopes:

```bash
python3 -c "
import base64, json
token = open('/tmp/.kanoniv-session-token').read().strip()
padded = token + '=' * (4 - len(token) % 4) if len(token) % 4 else token
data = json.loads(base64.urlsafe_b64decode(padded))
print(data.get('agent_name', 'claude-code'))
print(','.join(data.get('scopes', [])))
"
```

3. Extract the TTL from the user's message. The TTL is everything after
   `/ttl` — a duration string like `2h`, `30m`, `8h`.

4. Re-delegate with the new TTL (keep agent name and scopes):

```bash
rm -f /tmp/.kanoniv-session-token && TOKEN=$(kanoniv-auth delegate --name {agent_name} --scopes {scopes} --ttl {ttl}) && echo "$TOKEN" > /tmp/.kanoniv-session-token && kanoniv-auth status --agent {agent_name}
```

5. Print: "TTL updated to: `{ttl}`"

That's it. No questions, no prompts.
