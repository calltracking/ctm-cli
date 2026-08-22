# ctm

`ctm` is the official CallTrackingMetrics command line client. It talks to the
[CTM GraphQL API](https://app.ctm.com/graphql) and gives you typed commands for
accounts, tracking sources, phone numbers, users, reports, flows, and more —
plus an escape hatch for running any GraphQL document you write yourself.

This repository hosts binary releases only. Grab the latest build from the
[Releases](../../releases) page.

## Installation

### Homebrew (macOS)

```sh
brew install --no-quarantine calltracking/tap/ctm
```

Upgrades come through `brew upgrade` like everything else.

`--no-quarantine` is not optional decoration: `ctm` is not yet notarized by
Apple, and Homebrew flags what it installs as quarantined, so without it the
first run is blocked with *"Apple could not verify 'ctm' is free of malware."*
If you already installed and hit that dialog, clear the flag once — no
reinstall needed:

```sh
xattr -dr com.apple.quarantine "$(brew --prefix)/Caskroom/ctm"
```

See [macOS: "Apple could not verify ctm"](#macos-apple-could-not-verify-ctm)
for the other ways around it.

### Quick install (macOS / Linux)

```sh
curl -fsSL https://cli.ctm.com/install.sh | sh
```

The [script](install.sh) is republished with every release, pinned to it —
so it installs the current release's immutable assets (or upgrades a
previous install in place) after verifying the download against the
release's `checksums.txt`. It installs to the user-private `~/.local/bin`
(set `CTM_INSTALL_DIR` to choose another directory, `CTM_VERSION` to pin a
version) and never uses `sudo` — for a system-wide install use Homebrew
above. Nothing it downloads is quarantined, so it is the one path that never
triggers the macOS Gatekeeper prompt described below.

### Manual download

Download the archive for your platform from the
[latest release](../../releases/latest), extract it, and put the `ctm` binary
somewhere on your `PATH`.

| OS      | Architecture          | Archive                          |
| ------- | --------------------- | -------------------------------- |
| macOS   | Apple Silicon         | `ctm_<version>_darwin_arm64.tar.gz` |
| macOS   | Intel                 | `ctm_<version>_darwin_amd64.tar.gz` |
| Linux   | x86-64                | `ctm_<version>_linux_amd64.tar.gz`  |
| Linux   | ARM64                 | `ctm_<version>_linux_arm64.tar.gz`  |
| Windows | x86-64                | `ctm_<version>_windows_amd64.zip`   |
| Windows | ARM64                 | `ctm_<version>_windows_arm64.zip`   |

### macOS / Linux

```sh
tar -xzf ctm_<version>_<os>_<arch>.tar.gz
sudo mv ctm /usr/local/bin/
ctm version
```

### macOS: "Apple could not verify ctm"

`ctm` is not yet notarized with an Apple Developer certificate, so macOS
Gatekeeper blocks it whenever the file arrives carrying a quarantine flag.
Two install paths set that flag: **Homebrew**, which quarantines what it
installs, and a **browser download** of the release archive. If your first
run is blocked, click **Done** (not Move to Trash), then clear the flag:

```sh
# installed with Homebrew
xattr -dr com.apple.quarantine "$(brew --prefix)/Caskroom/ctm"

# installed by hand
xattr -d com.apple.quarantine /usr/local/bin/ctm
```

`ctm version` should work immediately afterwards. Other ways around it:

- Install with `brew install --no-quarantine calltracking/tap/ctm`, which
  never sets the flag in the first place.
- Open **System Settings → Privacy & Security**, find the message that `ctm`
  was blocked, and choose **Open Anyway**.
- Use the [quick install script](#quick-install-macos--linux), or download the
  archive from the command line — neither is quarantined:

  ```sh
  curl -sLO https://github.com/calltracking/ctm-cli/releases/download/v<version>/ctm_<version>_darwin_arm64.tar.gz
  ```

None of this reflects on the download's integrity: every release ships a
`checksums.txt` you can verify (see below), and the binaries are built and
published straight from CI.

### Windows

```powershell
Expand-Archive ctm_<version>_windows_amd64.zip
```

Move `ctm.exe` to a directory on your `PATH`, then run `ctm version` in a new
terminal.

### Verifying downloads

Each release includes a `checksums.txt`. Verify your download with:

```sh
shasum -a 256 -c checksums.txt --ignore-missing
```

## Authentication

There are two ways to authenticate. Which one you want depends on whether a
person or a script is running the command.

|                | `ctm auth login`                          | Basic Authentication Token           |
| -------------- | ----------------------------------------- | ------------------------------------ |
| **Use it for** | day-to-day work at your own terminal      | scripts, CI, cron, anything headless |
| **Acts as**    | you, with your own permissions            | your account's API user              |
| **Lifetime**   | one hour, re-run to renew                 | long-lived until you rotate it       |
| **Setup**      | sign in through the browser               | copy the token from Account Settings |
| **Browser**    | required                                  | never needed                         |

Both are stored in `~/.ctm.yml`, which is written with `0600` permissions.

### Signing in through the browser

Best for interactive use: there is no secret to copy around, and the CLI acts
as you rather than as a shared API user.

```sh
ctm auth login
```

This opens your browser and reuses the CTM session already there. If you are
not signed in, you go through the normal login first — single sign-on and
two-factor included. Confirm the prompt and the CLI stores the token:

```
Endpoint: https://app.ctm.com/graphql
Authenticated as jane@example.com (usr123)
Token saved to /Users/jane/.ctm.yml and expires Mon, 03 Aug 2026 15:12:02 EDT
```

The token lasts one hour; run `ctm auth login` again to renew it. It is also
tied to the endpoint that issued it, so a token from a sandbox or dev endpoint
is never sent to production.

Useful flags:

| Flag           | Effect                                                              |
| -------------- | ------------------------------------------------------------------- |
| `--force`      | Sign in again instead of reusing the browser's current CTM session  |
| `--no-browser` | Print the URL instead of launching a browser                        |
| `--endpoint`   | Sign in against a specific endpoint, and store it as the default    |
| `--timeout`    | How long to wait for you to finish in the browser (default `3m`)    |

`--no-browser` is for when the CLI cannot open a browser for you, not for
signing in from a different machine: the browser has to reach `127.0.0.1` on the
machine running `ctm`. Over SSH that means forwarding the port the command
prints (`ssh -L`). On a host where that is impractical, use an API token
instead.

To sign out, drop the stored token:

```sh
ctm config unset --login
```

Only a short-lived, single-use authorization code ever travels through the
browser. The CLI exchanges it for the token itself over HTTPS, proving it
started the request with a secret that never leaves your machine (PKCE), so the
token never appears in a URL or in your browser history. The browser hands the
code back only to `127.0.0.1` on a port the CLI is listening on.

### Using an API token

Best for anything unattended. Use the **Basic Authentication Token** from CTM
under **Account Settings → API Integration** (not the Access Key or Secret
Key):

```sh
ctm config set --token YOUR_TOKEN
ctm auth check
```

Or keep it out of the config file entirely:

```sh
export CTM_API_TOKEN=YOUR_TOKEN
ctm auth check
```

### Getting a token for direct HTTP requests

If you (or a script or AI agent) want to talk to the GraphQL API directly —
with `curl`, an HTTP library, or GraphQL tooling — don't build the
`Authorization` header from your long-lived API token. Ask the CLI for a
short-lived bearer token instead:

```bash
set -o pipefail   # Bash/zsh/ksh; POSIX sh rejects pipefail
ENDPOINT=$(ctm auth check | sed -n 's/^Endpoint: //p')
ctm auth token --endpoint "$ENDPOINT" \
  | sed 's/^/Authorization: Bearer /' \
  | curl -s --fail-with-body "$ENDPOINT" -H @- \
      -H "Content-Type: application/json" \
      -d '{"query": "query Viewer { viewer { id email } }"}'
```

Piping the header through stdin (`-H @-`) keeps the token out of the
process argument list, where `ps` or a traced script could expose it.

`ctm auth token` resolves whichever credential the CLI would use (see below)
and prints only the bearer token, so it composes straight into a header. The
token expires after about an hour — capture it once per batch of requests
and re-run the command when a request comes back unauthorized. Send it only
to the endpoint the CLI resolved it for (`ctm auth check` prints it). The
long-lived Basic Authentication Token never appears in your command line,
shell history, or logs.

### Which credential gets used

When more than one is available, the CLI picks the first of:

1. `--token`
2. An unexpired token from `ctm auth login`
3. `CTM_API_TOKEN`
4. `api_token` in the config file

Note the second entry: **signing in takes effect immediately even if you keep
`CTM_API_TOKEN` exported**, so an interactive login is never silently ignored.
Once that token expires the CLI falls back to `CTM_API_TOKEN` or `api_token`, so
scripts on the same machine keep working without a browser.

`ctm auth check` always reports which credential is in play, and points out when
one is outranking another:

```
Endpoint: https://app.ctm.com/graphql
Credential: auth login (config graphql_token)
Authenticated as jane@example.com (usr123)
```

The endpoint is resolved separately, in this order:

1. `--endpoint`
2. `CTM_API_ENDPOINT`
3. `api_endpoint` in the config file
4. `https://app.ctm.com/graphql`

Inspect the current configuration at any time (tokens are redacted unless you
pass `--show-token`):

```sh
ctm config show
```

```
Config: /Users/jane/.ctm.yml
api_endpoint: https://app.ctm.com/graphql
api_token: abcd************************wxyz
graphql_token: JWTG************************jkGw
graphql_token_expires_at: 2026-08-03T15:12:02-04:00
graphql_token_endpoint: https://app.ctm.com/graphql
```

The `graphql_token*` entries are managed by `ctm auth login`; `api_token` is the
one you set yourself.

## Usage

Run `ctm --help` to see every command, or `--help` on any subcommand for its
flags. A few examples:

```sh
# Who am I?
ctm viewer

# View your account
ctm account view 12345

# List tracking sources
ctm account tracking-sources list 12345

# List users, as a table with selected columns
ctm account users list 12345 --output table --fields id,email,name

# List virtual phone numbers as CSV
ctm account virtual-phone-numbers list 12345 --output csv --fields id,number
```

Most commands take an account id as their first argument, because a token can
reach more than one account. `ctm viewer` is the exception — it describes the
signed-in user, not an account.

### Object IDs

Wherever a command takes an id, you can use any of these. They all work, so
use whichever you already have:

```sh
# The numeric account id, as shown in the CTM app and the v1 REST API
ctm account tracking-sources list 12345

# The opaque id from a CTM web app URL
ctm account tracking-source view 12345 TSOF6FC2D2594D22C52C7F22FA76C7AEAFA21FB8F34CCCFFF30

# The id this API returns
ctm account tracking-source view Z2lkOi8vY3RtL0FjY291bnQvMTIzNDU Z2lkOi8vY3RtL1RyYWNraW5nU291cmNlLzk4NzY1NA

# ...which is base64, and also accepted unencoded
ctm account tracking-source view 'gid://ctm/Account/12345' 'gid://ctm/TrackingSource/987654'
```

The ids in API responses are always the last form — a global id, unique across
every object type. **Treat them as opaque strings.** Hold them and pass them
back; do not parse them, build them by hand, or compare them numerically. The
encoding is not part of the contract and may change.

Two behaviors to expect:

- **Ids are type-checked.** Passing a tracking source id where a user is
  expected returns "not found" rather than quietly loading the user that
  happens to share that number.
- **The plain number is the only ambiguous form**, since nothing in `12345`
  says what it is. It works because the command already knows what it is
  asking for. Prefer global ids in scripts.

If you need the plain numeric id back — to cross-reference the v1 REST API, a
spreadsheet, or an existing export — select `legacyId` alongside `id`:

```sh
ctm account users list 12345 --output table --fields id,legacyId,email
```

`legacyId` is returned as a string of digits, not a JSON number, because ids
can exceed what JSON numbers represent exactly. In JavaScript, parse it with
`BigInt()` rather than `Number()`.

### Running your own GraphQL

`ctm exec` executes any GraphQL document against the API, reading from a file
or stdin:

```sh
# From stdin
echo 'query { viewer { id email } }' | ctm exec

# From a file, with variables
ctm exec --input ./my-query.graphql --variables '{"first": 25}'

# Variables from a JSON file
ctm exec --input ./my-query.graphql --variables-file ./vars.json
```

### Public API commands

Commands under `ctm public` (for example, published rack rates) use the
unauthenticated public endpoint and require no token:

```sh
ctm public rack-rate-plans list
ctm public inbound-rack-call-rates list
```

`ctm exec --public` does the same for hand-written documents.

### Output formats

Every command that returns data supports:

- `--output pretty` (default) — colorized, indented JSON
- `--output raw` — compact JSON, ideal for piping to `jq`
- `--output csv` / `--output table` — tabular output; choose columns with
  `--fields id,name,createdAt`
- `--field path.to.value` — print a single value by dot path, such as
  `--field viewer.email`
- `--no-color` — disable colored output (color is also skipped automatically
  when output is not a terminal)

## API schema

Every release attaches the GraphQL schemas the binaries were generated from:

- `schema.graphql` — the authenticated API served at `/graphql`
- `public_schema.graphql` — the unauthenticated public API served at
  `/public_graphql`

They are the exact API contract for that release (and are listed in
`checksums.txt` like every other asset). The latest schema is always at a
stable URL:

```sh
curl -sLO https://github.com/calltracking/ctm-cli/releases/latest/download/schema.graphql
```

Use them to power your own tooling — code generation (`graphql-codegen`,
Apollo), IDE autocompletion via `graphql-config`, or query linting — instead
of hand-rolling an introspection dump. Diffing the schema between two
releases (for example with `graphql-inspector diff`) shows exactly how the
API changed from one CLI version to the next.

## Agent skills

If an AI coding agent (Claude Code, Codex, or a compatible tool) works with
the CTM API on your behalf, install the skill from the
[`skills/`](skills/) directory. A skill is a plain Markdown playbook the
agent loads when the task matches; [`skills/ctm-graphql/SKILL.md`](skills/ctm-graphql/SKILL.md)
teaches an agent to:

- work schema-first: derive GraphQL operations from the released
  `schema.graphql` and send them directly over HTTP with a short-lived
  token from `ctm auth token`, or use the CLI's typed commands and
  `ctm exec` for scripts — never hand-rolling auth headers from the
  long-lived API token
- write correct GraphQL operations: named operations with variables,
  account nesting, connection pagination, and sorting
- handle CTM API conventions that agents otherwise get wrong: opaque global
  ids and `legacyId`, strict timeframe scalars, and exact money values
- confirm with you before running mutations against live account
  configuration

For Claude Code, copy the skill into your project (or into
`~/.claude/skills/` to enable it everywhere):

```sh
mkdir -p .claude/skills
curl -sL --create-dirs -o .claude/skills/ctm-graphql/SKILL.md \
  https://raw.githubusercontent.com/calltracking/ctm-cli/master/skills/ctm-graphql/SKILL.md
```

Other agents can use the same file wherever they load skills or custom
instructions from.

The skills are maintained alongside the CLI and schemas in the CTM source
repository and synced here on every release, so the copy on `master` always
matches the latest released binary and schema.

## Environment variables

| Variable           | Purpose                                                  |
| ------------------ | -------------------------------------------------------- |
| `CTM_API_TOKEN`    | Basic Authentication Token used for API requests. Outranked by an unexpired `ctm auth login` token |
| `CTM_API_ENDPOINT` | GraphQL endpoint (defaults to `https://app.ctm.com/graphql`) |
| `CTM_CONFIG`       | Path to the YAML config file (defaults to `~/.ctm.yml`)   |

## Support

- API documentation: https://www.calltrackingmetrics.com/developers/
- Questions or problems with the CLI: open an [issue](../../issues) or contact
  CTM support at https://www.calltrackingmetrics.com/support/

## License

The `ctm` CLI is distributed as a binary release, © CallTrackingMetrics. See
the release notes for details on each version.
