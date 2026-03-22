# Kanoniv Auth Action

**Sudo for AI agents.** Issue scoped, time-bounded delegation tokens for your CI/CD pipeline agents.

```yaml
- uses: kanoniv/auth-action@v1
  with:
    root_key: ${{ secrets.KANONIV_ROOT_KEY }}
    scopes: deploy.staging,build
    ttl: 4h
```

Your agent gets a `KANONIV_TOKEN` environment variable with a cryptographically scoped delegation. It can deploy to staging but **cannot** touch prod - not policy-blocked, cryptographically impossible.

## Inputs

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

## Outputs

| Output | Description |
|--------|-------------|
| `token` | The delegation token (also set as `KANONIV_TOKEN` env) |
| `agent_did` | The delegated agent's DID |

## Usage

### Basic: Scoped agent deploy

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
          # $KANONIV_TOKEN is set automatically
          kanoniv-auth verify --scope deploy.staging  # passes
          kanoniv-auth verify --scope deploy.prod     # DENIED
          ./deploy.sh staging
```

### With PR audit comment

```yaml
      - uses: kanoniv/auth-action@v1
        with:
          root_key: ${{ secrets.KANONIV_ROOT_KEY }}
          scopes: build,test,deploy.staging
          ttl: 4h
          post_audit: true
```

Posts a comment on the PR showing what scopes were delegated, the delegation chain, and TTL.

### Generate a root key

```bash
pip install kanoniv-auth
kanoniv-auth init
# Outputs base64 key - add as KANONIV_ROOT_KEY secret
```

## How it works

1. Action installs `kanoniv-auth` Python package
2. Loads your root key from the secret
3. Issues a delegation token scoped to the specified actions
4. Sets `KANONIV_TOKEN` in the environment for subsequent steps
5. Optionally posts an audit comment on the PR

The token uses Ed25519 cryptographic signatures. Scopes can only narrow through delegation chains - never widen. Every action is verifiable without trusting any single system.

## Links

- [kanoniv-agent-auth](https://github.com/kanoniv/agent-auth) - Full library (Rust + Python + TypeScript)
- [kanoniv-auth on PyPI](https://pypi.org/project/kanoniv-auth/) - Python package
- [Documentation](https://kanoniv.com/docs)

## License

MIT
