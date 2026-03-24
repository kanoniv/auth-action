# kanoniv auth-action

> "The question isn't whether AI agents can write code. It's whether you'd let them `git push --force` to production at 3am." — every engineering manager, eventually

AI agents are getting root access to your codebase. Claude Code runs `bash`. Codex executes shell commands. Cursor edits your files. And right now, the only thing between an agent and `rm -rf /` is... vibes. A system prompt that says "please don't."

**auth-action is sudo for AI agents.** Cryptographic delegation tokens that scope-confine what an agent can do — not by policy, but by math. Ed25519 signatures. Hierarchical scopes. Time-bounded sessions. Full audit trails. If the token doesn't grant `git.push.prod`, the push doesn't happen. Not because a hook said no. Because the proof doesn't exist.

```
/delegate → choose scopes → every tool call verified → full audit trail
```

Two surfaces, same cryptography:
- **Claude Code skills** — interactive sessions with `/delegate`, `/scope`, `/ttl`
- **GitHub Action** — CI/CD pipelines with `kanoniv/auth-action@v1`

## Quick start

1. Install (30 seconds — see below)
2. Run `/delegate` in Claude Code
3. Choose your scopes — `code.edit,test.run` or go read-only
4. Work normally. Every tool call is verified silently.
5. Run `/audit` to see what happened

## Install — 30 seconds

**Requirements:** [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Python 3.8+, Git

Open Claude Code and paste:

> Install kanoniv auth-action: run **`git clone https://github.com/kanoniv/auth-action.git ~/.kanoniv/auth-action && cd ~/.kanoniv/auth-action && ./install.sh`** — this installs the kanoniv-auth CLI, generates a root key, and symlinks five skills: /delegate, /scope, /ttl, /status, /audit. Then run /delegate to start your first scoped session.

Or do it manually:

```bash
git clone https://github.com/kanoniv/auth-action.git ~/.kanoniv/auth-action
cd ~/.kanoniv/auth-action && ./install.sh
```

That's it. Five skills are now available in Claude Code.

## See it work

```
You:    /delegate
Claude: Name this agent and set the session duration?
        → claude-code, 4h

Claude: What should claude-code be allowed to do?
        → Read-only + test (code.read, test.run)

Claude: Delegation active for claude-code.
        Agent:  claude-code
        DID:    did:agent:43d8eea1...
        Scopes: code.read, test.run
        TTL:    4h

You:    Can you refactor the auth module?
Claude: [Edit src/auth.rs]
        ✗ SCOPE DENIED: file editing requires code.edit scope

You:    /scope code.edit,test.run,git.commit
Claude: Scopes updated to: code.edit, test.run, git.commit

You:    Now refactor it.
Claude: [Edit src/auth.rs]  ✓
        [Bash cargo test]   ✓
        [Bash git commit]   ✓
        [Bash git push]     ✗ SCOPE DENIED: requires git.push.auth-action.main

You:    /audit
Claude: 2026-03-24 21:15:03  claude-code  tool:edit   src/auth.rs        ok
        2026-03-24 21:15:05  claude-code  tool:bash   cargo test         ok
        2026-03-24 21:15:08  claude-code  tool:bash   git commit -m ...  ok
        2026-03-24 21:15:12  claude-code  tool:bash   git push origin    DENIED
```

The agent can edit, test, and commit — but not push. Not because you told it not to. Because the cryptographic proof for `git.push` doesn't exist in the token.

## Skills

| Skill | What it does | When to use |
|-------|-------------|-------------|
| `/delegate` | **Start a scoped session.** Agent name, scopes, TTL, hooks. Full onboarding or streamlined re-delegation if a session exists. | Beginning of a session, or to fully reset |
| `/scope` | **Change scopes mid-session.** No prompts, no restart. | `/scope code.edit,test.run` when you need to escalate or restrict |
| `/ttl` | **Extend session time.** Same agent, same scopes, new TTL. | `/ttl 8h` when the session is about to expire |
| `/status` | **Check delegation status.** Agent name, DID, scopes, TTL remaining. | "Am I still delegated?" |
| `/audit` | **View the audit trail.** Every action logged with timestamp, agent DID, tool, and result. | "What did the agent do?" |

### Scope mapping

Every Claude Code tool call is mapped to a required scope:

| Tool | Required Scope | Example |
|------|---------------|---------|
| `Bash` (git push) | `git.push.{repo}.{branch}` | `git.push.auth-action.main` |
| `Bash` (git commit/add/reset) | `git.commit.{repo}` | `git.commit.auth-action` |
| `Bash` (test commands) | `test.run` | `cargo test`, `pytest`, `npm test` |
| `Bash` (build commands) | `code.edit` | `cargo build`, `npm run build` |
| `Bash` (other) | `code.edit` | Any non-read shell command |
| `Edit` / `Write` | `code.edit` | File modifications |
| `Read` | *always allowed* | Reading files never requires scope |

### Hierarchical scopes

Scopes are hierarchical. A broader scope grants everything beneath it:

```
git.push                        → all repos, all branches
git.push.auth-action            → all branches in auth-action
git.push.auth-action.main       → only main branch in auth-action
```

This means you can grant `git.push` for full push access, or lock it down to a single repo and branch. Scopes can only **narrow** through delegation chains — never widen.

### Re-delegation

Change scopes or TTL mid-session without restarting:

```
/scope code.read,test.run         # drop to read-only
/scope code.edit,git.push         # escalate when needed
/ttl 8h                           # extend the session
/delegate                         # full reset (detects existing session)
```

### Presets

Common scope combinations:

| Preset | Scopes | Use case |
|--------|--------|----------|
| Full dev | `code.edit,test.run,git.commit,git.push` | Trusted development |
| Read-only + test | `code.read,test.run` | Code review, investigation |
| Repo-scoped | `code.edit,test.run,git.push.{repo}.{branch}` | Locked to one repo/branch |
| Build only | `code.edit,test.run` | Compile and test, no git |

## How it works

```
Root Key (Ed25519)
    │
    ├── signs → Delegation Token
    │              ├── agent_did: did:agent:43d8eea1...
    │              ├── scopes: [code.edit, test.run]
    │              ├── expires_at: 2026-03-25T01:00:00Z
    │              └── proof: { signature, nonce, chain }
    │
    ▼
PreToolUse Hook (every Bash/Edit/Write call)
    │
    ├── Extract command from tool input
    ├── Map tool → required scope
    ├── Verify token grants scope (hierarchical match)
    │
    ├── ✓ PASS → allow tool, log to audit
    └── ✗ DENY → block tool, log denial
```

1. A root key signs a delegation token with specific scopes and a TTL
2. The token is stored at `/tmp/.kanoniv-session-token`
3. PreToolUse hooks intercept every Bash, Edit, and Write call
4. The hook extracts the command and maps it to a required scope
5. `kanoniv-auth verify` checks the token cryptographically
6. Denied = the proof doesn't exist in the token. Not a policy check.
7. Every verification is logged to `~/.kanoniv/audit.log`

### Audit trail

Every tool call is logged with agent attribution:

```
TIMESTAMP            AGENT            DID                       TOOL          COMMAND                                   STATUS
2026-03-24 21:15:03  claude-code      did:agent:43d8eea1...     tool:bash     cargo test --lib                          ok
2026-03-24 21:15:05  claude-code      did:agent:43d8eea1...     tool:edit     src/lib.rs                                ok
2026-03-24 21:15:08  claude-code      did:agent:43d8eea1...     tool:bash     git commit -m "feat: ..."                 ok
2026-03-24 21:15:12  claude-code      did:agent:43d8eea1...     tool:bash     git push origin main                      DENIED
```

---

## GitHub Action (CI/CD)

Same cryptography, different surface. Use `kanoniv/auth-action@v1` in your GitHub Actions workflow:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: kanoniv/auth-action@v1
        with:
          root_key: ${{ secrets.KANONIV_ROOT_KEY }}
          scopes: deploy.staging
          ttl: 4h

      - name: Agent deploys (scoped to staging only)
        run: |
          kanoniv-auth verify --scope deploy.staging  # ✓ passes
          kanoniv-auth verify --scope deploy.prod     # ✗ DENIED
          ./deploy.sh staging
```

Your agent gets a `KANONIV_TOKEN` environment variable. It can deploy to staging but **cannot** touch prod — cryptographically impossible.

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `root_key` | Yes* | - | Base64-encoded root private key |
| `scopes` | Yes | - | Comma-separated scopes (e.g. `deploy.staging,build`) |
| `ttl` | No | `4h` | Token time-to-live (`4h`, `30m`, `1d`) |
| `post_audit` | No | `false` | Post delegation audit comment on PR |
| `oidc` | No | `false` | Use OIDC for ephemeral root key (requires `api_key`) |
| `api_key` | No | - | Kanoniv Cloud API key (for OIDC mode) |
| `version` | No | `0.1.0` | `kanoniv-auth` package version |

*Not required if `oidc: true`

### Outputs

| Output | Description |
|--------|-------------|
| `token` | The delegation token (also set as `KANONIV_TOKEN` env) |
| `agent_did` | The delegated agent's DID |

### PR audit comments

```yaml
      - uses: kanoniv/auth-action@v1
        with:
          root_key: ${{ secrets.KANONIV_ROOT_KEY }}
          scopes: build,test,deploy.staging
          ttl: 4h
          post_audit: true
```

Posts a comment on the PR showing what scopes were delegated, the delegation chain, and TTL remaining.

### Generate a root key

```bash
pip install kanoniv-auth
kanoniv-auth init
# Outputs base64 key — add as KANONIV_ROOT_KEY secret
```

---

## Troubleshooting

**Skill not showing up?** Run `cd ~/.kanoniv/auth-action && ./install.sh` to re-symlink.

**`kanoniv-auth` not found?** `pip install kanoniv-auth`

**Hook error?** Make sure the skills are symlinked, not copied. The hook paths use `~/.claude/skills/delegate/bin/...` which must resolve to the actual scripts. Run `ls -la ~/.claude/skills/delegate` — it should be a symlink.

**Scope denied unexpectedly?** Check your token: `python3 -c "import base64,json; t=open('/tmp/.kanoniv-session-token').read().strip(); p=t+'='*(4-len(t)%4) if len(t)%4 else t; print(json.dumps(json.loads(base64.urlsafe_b64decode(p))['scopes'],indent=2))"`

**Token expired?** Run `/ttl 4h` to extend, or `/delegate` to start fresh.

**Want to disable hooks temporarily?** Delete the token file: `rm /tmp/.kanoniv-session-token`. The hooks pass through when no token exists.

## Links

- [kanoniv-agent-auth](https://github.com/kanoniv/agent-auth) — Full library (Rust + Python + TypeScript)
- [kanoniv-auth on PyPI](https://pypi.org/project/kanoniv-auth/) — Python package
- [Kanoniv](https://kanoniv.com) — Shared identity layer for AI agents

## License

MIT. Free forever. Go build something — with guardrails.
