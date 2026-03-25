# kanoniv auth-action

> "The question isn't whether AI agents can write code. It's whether you'd let them `git push --force` to production at 3am." -- every engineering manager, eventually

AI agents are getting root access to your codebase. Claude Code runs `bash`. Codex executes shell commands. Cursor edits your files. And right now, the only thing between an agent and `rm -rf /` is... vibes. A system prompt that says "please don't."

**auth-action is sudo for AI agents.** Cryptographic delegation tokens that scope-confine what an agent can do -- not by policy, but by math. Ed25519 signatures. Hierarchical scopes. Time-bounded sessions. Full audit trails. If the token doesn't grant `git.push.prod`, the push doesn't happen. Not because a hook said no. Because the proof doesn't exist.

## The ecosystem

One cryptographic core, every surface:

| Surface | Install | Use case |
|---------|---------|----------|
| **Python SDK** | `pip install kanoniv-auth` | Programmatic delegation, verification, signing |
| **Python CLI** | `kanoniv-auth delegate --scopes ...` | Terminal-based agent management |
| **Rust crate** | `kanoniv-agent-auth` on crates.io | Native performance, MCP proxy |
| **Claude Code skills** | `/delegate`, `/scope`, `/audit` | Interactive sessions with scope enforcement |
| **GitHub Action** | `kanoniv/auth-action@v1` | CI/CD pipeline delegation |
| **wrap-mcp** | `kanoniv-auth wrap-mcp -- npx server` | Access control proxy for any MCP server |
| **Trust Observatory** | `pip install kanoniv-trust` | Agent registry, reputation, provenance dashboard |

```
/delegate -> choose scopes -> every tool call verified -> full audit trail
```

---

## Quick start (30 seconds)

**Requirements:** Python 3.10+, Claude Code (for skills), Git

```bash
git clone https://github.com/kanoniv/auth-action.git ~/.kanoniv/auth-action
cd ~/.kanoniv/auth-action && ./install.sh
```

That's it. Five skills are now available in Claude Code. Run `/delegate` to start your first scoped session.

---

## Python SDK

The core library. Everything else is built on this.

```bash
pip install kanoniv-auth
```

```python
from kanoniv_auth import delegate, verify, sign

# Issue a delegation token
token = delegate(scopes=["deploy.staging", "build"], ttl="4h")

# Verify before acting
verify(action="deploy.staging", token=token)   # passes
verify(action="deploy.prod", token=token)       # raises ScopeViolation

# Sign an execution envelope (provable audit)
envelope = sign(action="deploy.staging", token=token, result="success")
```

### Full API

```python
from kanoniv_auth import (
    # Core
    delegate,           # Issue delegation token
    verify,             # Verify scope against token
    sign,               # Sign execution envelope

    # Key management
    init_root,          # Generate root Ed25519 keypair
    load_root,          # Load existing root key
    load_token,         # Load token from disk/env
    list_tokens,        # List all saved tokens

    # Agent registry (persistent identities)
    register_agent,     # Register named agent (DID persists across sessions)
    get_agent,          # Look up agent by name
    list_agents,        # List all registered agents
    resolve_name,       # Resolve agent name to DID

    # Errors
    AuthError,          # Base error
    ScopeViolation,     # Scope not in token
    TokenExpired,       # TTL exceeded
    ChainTooDeep,       # Delegation chain limit
    SignatureInvalid,   # Ed25519 verification failed
    TokenParseError,    # Malformed token

    # Crypto primitives
    KeyPair,            # Ed25519 keypair
    generate_keys,      # Generate new keypair
    load_keys,          # Load from base64
)
```

### Sub-delegation (authority can only shrink)

```python
# Root delegates to coordinator
root_token = delegate(scopes=["deploy", "build", "test"], ttl="8h")

# Coordinator sub-delegates to deploy agent (narrower scopes)
deploy_token = delegate(
    scopes=["deploy.staging"],   # narrowed from "deploy"
    ttl="2h",                     # shorter TTL
    parent=root_token,            # chain link
)

# Deploy agent cannot exceed its authority
verify(action="deploy.staging", token=deploy_token)  # passes
verify(action="deploy.prod", token=deploy_token)     # ScopeViolation
verify(action="build", token=deploy_token)            # ScopeViolation
```

### Named agents (persistent identity)

```python
from kanoniv_auth import register_agent, delegate

# Agent gets a persistent DID that survives across sessions
agent = register_agent("deploy-bot")
print(agent.did)    # did:agent:a3f9c2b1e4d8...

# Delegate to the named agent
token = delegate(scopes=["deploy.staging"], ttl="4h", name="deploy-bot")

# Next session, same DID
agent = register_agent("deploy-bot")  # returns existing identity
```

---

## Python CLI

```bash
kanoniv-auth --help
```

### Key management

```bash
kanoniv-auth init                          # Generate root Ed25519 keypair
kanoniv-auth init -o ./my-key              # Custom output path
```

### Delegation

```bash
# Issue a token
kanoniv-auth delegate -s deploy.staging,build -t 4h -n my-agent

# With sub-delegation
kanoniv-auth delegate -s deploy.staging -t 2h --parent $ROOT_TOKEN

# Dry run (show what would happen)
kanoniv-auth delegate -s deploy.staging -t 4h --dry-run

# Export as shell variable
eval $(kanoniv-auth delegate -s deploy.staging -t 4h --export)
```

### Verification

```bash
# Verify a scope
kanoniv-auth verify -s deploy.staging                    # uses $KANONIV_TOKEN
kanoniv-auth verify -s deploy.staging -a my-agent        # by agent name
kanoniv-auth verify -s deploy.prod                       # fails: ScopeViolation

# Execute with scope check (verify + run + sign)
kanoniv-auth exec -s deploy.staging -- ./deploy.sh staging
```

### Signed execution

```bash
# Sign an action (creates execution envelope)
kanoniv-auth sign -a deploy.staging --target staging --result success

# Verify an execution envelope
kanoniv-auth audit '{"agent_did":"did:agent:...","action":"deploy.staging",...}'
```

### Agent management

```bash
kanoniv-auth agents list                   # List all registered agents
kanoniv-auth agents show deploy-bot        # Show agent details + DID
kanoniv-auth agents rename old-name new    # Rename (DID preserved)
kanoniv-auth agents remove old-agent       # Remove permanently

kanoniv-auth tokens                        # List all saved tokens
kanoniv-auth status                        # Current delegation status
kanoniv-auth status -a deploy-bot          # Status for named agent
kanoniv-auth whoami                        # Who am I? (DID, scopes, TTL)
kanoniv-auth audit-log -n 20              # Last 20 audit entries
kanoniv-auth audit-log -a deploy-bot       # Filter by agent
```

### Git hook

```bash
kanoniv-auth install-hook                  # Install pre-push hook
kanoniv-auth install-hook -r ./my-repo     # Specific repo
```

The hook verifies `git.push.{repo}.{branch}` scope before every push. No scope = no push.

---

## Rust crate

Native performance for MCP proxies and embedded verification.

```toml
[dependencies]
kanoniv-agent-auth = "0.3.1"
```

```rust
use kanoniv_agent_auth::{AgentIdentity, AgentKeyPair, DelegationToken};

// Generate identity
let keys = AgentKeyPair::generate();
let identity = AgentIdentity::new(keys);

// Issue delegation
let token = identity.delegate(&["deploy.staging", "build"], Duration::hours(4))?;

// Verify
identity.verify("deploy.staging", &token)?;  // Ok
identity.verify("deploy.prod", &token)?;     // Err(ScopeViolation)
```

### Binaries

| Binary | Purpose |
|--------|---------|
| `kanoniv-auth` | CLI (same as Python, Rust-native) |
| `kanoniv-auth-server` | Delegation service (HTTP API for cloud mode) |
| `kanoniv-auth wrap-mcp` | MCP proxy with delegation enforcement |

---

## `wrap-mcp` -- Access control for any MCP server

One line. No code changes. No SDK integration. Just a proxy.

```bash
# Before: any agent calls anything
npx my-mcp-server

# After: only delegated agents, only authorized tools
kanoniv-auth wrap-mcp --mode strict --root-key ~/.kanoniv/root.key -- npx my-mcp-server
```

The proxy intercepts every `tools/call` JSON-RPC message:
1. Reads the delegation token (from `_proof` argument or session file)
2. Verifies the Ed25519 delegation chain against the root key
3. Checks that the token grants scope for the tool being called
4. Forwards or rejects -- the MCP server never sees denied calls

```
resolve({name: "John"})     -> VERIFIED: token has "resolve" scope -> forwarded
merge({entity_id: "123"})   -> DENIED: "merge" not in token scopes -> blocked
```

### Modes

| Mode | Behavior |
|------|----------|
| `--mode strict` | No valid token = reject (JSON-RPC error) |
| `--mode warn` | No valid token = log warning, forward anyway |
| `--mode audit` | No verification, just log everything |

### Two verification paths

1. **`_proof` in tool arguments** -- cryptographic MCP proof (verified against root key)
2. **Session token file** -- delegation token read from disk (re-read on every call for mid-session changes)

Priority: `_proof` > token file > reject/warn/audit

---

## Claude Code skills

Interactive delegation for Claude Code sessions. Slash commands that extend your agent with cryptographic scope enforcement.

| Skill | What it does |
|-------|-------------|
| `/delegate` | Start a scoped session. Agent name, scopes, TTL. Interactive picker with presets. |
| `/scope` | Change scopes mid-session. No restart needed. |
| `/ttl` | Extend session time. Same agent, same scopes, new TTL. |
| `/status` | Check delegation status. Agent, DID, scopes, TTL remaining. |
| `/audit` | View the audit trail. Every action with timestamp, DID, tool, result. |

### Scope presets

| Preset | Scopes | Use case |
|--------|--------|----------|
| Full dev | `code.edit, test.run, git.commit, git.push` | Trusted development |
| Read-only + test | `code.read, test.run` | Code review, investigation |
| Repo-scoped | `code.edit, test.run, git.push.{repo}.{branch}` | Locked to one repo/branch |
| Build only | `code.edit, test.run` | Compile and test, no git |

### Scope mapping

Every Claude Code tool call is mapped to a required scope:

| Tool | Required Scope | Example |
|------|---------------|---------|
| `Bash` (git push) | `git.push.{repo}.{branch}` | `git.push.auth-action.main` |
| `Bash` (git commit/add) | `git.commit.{repo}` | `git.commit.auth-action` |
| `Bash` (test commands) | `test.run` | `cargo test`, `pytest`, `npm test` |
| `Bash` (build/other) | `code.edit` | Any non-read shell command |
| `Edit` / `Write` | `code.edit` | File modifications |
| `Read` | *always allowed* | Reading files never requires scope |

### Example session

```
You:    /delegate
Claude: What scopes should the new delegation have?
        -> Read-only + test (code.read, test.run)

Claude: Delegation active for claude-code.
        Agent:  claude-code
        DID:    did:agent:43d8eea1...
        Scopes: code.read, test.run
        TTL:    4h

You:    Can you refactor the auth module?
Claude: [Edit src/auth.rs]
        SCOPE DENIED: file editing requires code.edit scope

You:    /scope code.edit,test.run,git.commit
Claude: Scopes updated.

You:    Now refactor it.
Claude: [Edit src/auth.rs]  ok
        [Bash cargo test]   ok
        [Bash git commit]   ok
        [Bash git push]     SCOPE DENIED: requires git.push

You:    /audit
Claude: 2026-03-25 21:15:03  claude-code  tool:edit   src/auth.rs     ok
        2026-03-25 21:15:05  claude-code  tool:bash   cargo test      ok
        2026-03-25 21:15:08  claude-code  tool:bash   git commit      ok
        2026-03-25 21:15:12  claude-code  tool:bash   git push        DENIED
```

### Install skills

```bash
cd ~/.kanoniv/auth-action && ./install.sh
```

Or manually:

```bash
kanoniv-auth install-skill
```

---

## GitHub Action (CI/CD)

Same cryptography, different surface. Scope-confine your CI/CD pipeline agents.

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: kanoniv/auth-action@v1
        with:
          root_key: ${{ secrets.KANONIV_ROOT_KEY }}
          scopes: deploy.staging,build
          ttl: 4h

      - name: Agent deploys (scoped to staging only)
        run: |
          kanoniv-auth verify -s deploy.staging  # passes
          kanoniv-auth verify -s deploy.prod     # DENIED
          ./deploy.sh staging
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `root_key` | Yes* | - | Base64-encoded root private key |
| `scopes` | Yes | - | Comma-separated scopes |
| `ttl` | No | `4h` | Token time-to-live |
| `post_audit` | No | `false` | Post delegation audit comment on PR |
| `oidc` | No | `false` | Use GitHub OIDC for ephemeral root key |
| `api_key` | No | - | Kanoniv Cloud API key (for OIDC mode) |
| `version` | No | `0.1.0` | `kanoniv-auth` package version |

*Not required if `oidc: true`

### Outputs

| Output | Description |
|--------|-------------|
| `token` | Delegation token (also set as `KANONIV_TOKEN` env) |
| `agent_did` | The delegated agent's DID |

### PR audit comments

Set `post_audit: true` to post a delegation audit comment on PRs showing scopes, chain depth, and TTL remaining.

### OIDC mode (no secrets)

```yaml
    permissions:
      id-token: write
    steps:
      - uses: kanoniv/auth-action@v1
        with:
          oidc: true
          api_key: ${{ secrets.KANONIV_API_KEY }}
          scopes: deploy.staging
```

Exchanges a GitHub OIDC token for an ephemeral root key via Kanoniv Cloud. No `root_key` secret needed.

### Generate a root key

```bash
pip install kanoniv-auth
kanoniv-auth init
# Outputs base64 key -- add as KANONIV_ROOT_KEY in repo secrets
```

---

## Trust Observatory

Live dashboard for agent trust, reputation, and provenance.

```bash
pip install kanoniv-trust
```

```python
from kanoniv_trust import TrustClient

trust = TrustClient()  # connects to trust.kanoniv.com

# Register agents with DIDs
agent = trust.register("sdr-agent", capabilities=["resolve", "search"])

# Delegate (agent-to-agent, with caveats)
trust.delegate("coordinator", "sdr-agent", scopes=["resolve"],
               expires_in_hours=4, metadata={"max_amount": 100})

# Actions are enforced by the API
trust.action("sdr-agent", "resolve", metadata={"entity": "john@acme.com"})
# -> ALLOWED (has scope)

trust.action("sdr-agent", "merge", metadata={"target": "e3a1"})
# -> 403: delegation_denied (no merge scope)

# Reputation feedback
trust.feedback(agent["did"], "resolve", "success", reward_signal=0.9)
```

### CLI

```bash
kt agents                                          # List agents
kt register sdr-agent -c resolve,search            # Register
kt delegate coordinator sdr-agent -s resolve,merge  # Delegate
kt action sdr-agent resolve -m '{"entity":"..."}'  # Record action
kt log                                             # Provenance trail
```

### Observatory UI

Everything updates live at [trust.kanoniv.com](https://trust.kanoniv.com):
- Agent registry with DIDs, capabilities, reputation scores
- Delegation graph visualization
- Provenance audit trail
- Real-time enforcement (ALLOWED/BLOCKED)

---

## How it works

```
Root Key (Ed25519)
    |
    +-- signs -> Delegation Token
    |              +-- agent_did: did:agent:43d8eea1...
    |              +-- scopes: [code.edit, test.run]
    |              +-- expires_at: 2026-03-25T01:00:00Z
    |              +-- proof: { signature, nonce, chain }
    |
    v
Verification (every action)
    |
    +-- Extract action from tool/command
    +-- Map to required scope
    +-- Verify token grants scope (hierarchical match)
    +-- Verify Ed25519 signature chain
    |
    +-- PASS -> allow, log to audit
    +-- DENY -> block, log denial
```

### Hierarchical scopes

Scopes are hierarchical. A broader scope grants everything beneath it:

```
git.push                        -> all repos, all branches
git.push.auth-action            -> all branches in auth-action
git.push.auth-action.main       -> only main branch
```

Authority can only **narrow** through delegation chains -- never widen.

### Delegation chain

```
Root Key
  +-- delegates -> Coordinator (scopes: [deploy, build, test], ttl: 8h)
        +-- sub-delegates -> Deploy Agent (scopes: [deploy.staging], ttl: 2h)
              |
              +-- deploy.staging  -> ALLOWED (in chain)
              +-- deploy.prod     -> DENIED (narrowed out)
              +-- build           -> DENIED (narrowed out)
```

Every link in the chain is cryptographically signed. Forged tokens are rejected -- signatures must trace back to the root key.

---

## Troubleshooting

**Skill not showing up?** Run `cd ~/.kanoniv/auth-action && ./install.sh`

**`kanoniv-auth` not found?** `pip install kanoniv-auth`

**Scope denied unexpectedly?** Check your token: `kanoniv-auth whoami`

**Token expired?** `/ttl 4h` to extend, or `/delegate` to start fresh

**Disable hooks temporarily?** `rm /tmp/.kanoniv-session-token` -- hooks pass through when no token exists

---

## Links

| Resource | URL |
|----------|-----|
| GitHub Action | [kanoniv/auth-action](https://github.com/kanoniv/auth-action) |
| Full library | [kanoniv/agent-auth](https://github.com/kanoniv/agent-auth) |
| Python SDK (PyPI) | [kanoniv-auth](https://pypi.org/project/kanoniv-auth/) |
| Trust SDK (PyPI) | [kanoniv-trust](https://pypi.org/project/kanoniv-trust/) |
| Rust crate | [kanoniv-agent-auth](https://crates.io/crates/kanoniv-agent-auth) |
| Observatory | [trust.kanoniv.com](https://trust.kanoniv.com) |
| Kanoniv | [kanoniv.com](https://kanoniv.com) |

## License

MIT. Free forever. Go build something -- with guardrails.
