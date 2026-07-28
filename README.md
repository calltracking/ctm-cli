# ctm

`ctm` is the official CallTrackingMetrics command line client. It talks to the
[CTM GraphQL API](https://app.ctm.com/graphql) and gives you typed commands for
accounts, tracking sources, phone numbers, users, reports, flows, and more —
plus an escape hatch for running any GraphQL document you write yourself.

This repository hosts binary releases only. Grab the latest build from the
[Releases](../../releases) page.

## Installation

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

#### macOS: “ctm” Not Opened

The `ctm` binary is not yet signed with an Apple developer certificate, and
macOS quarantines files downloaded with a browser. If you downloaded the
archive in Safari or Chrome, the first run is blocked with a dialog saying
Apple could not verify `ctm` is free of malware. Click **Done** (not Move to
Trash), then either:

- remove the quarantine attribute and run it again:

  ```sh
  xattr -d com.apple.quarantine /usr/local/bin/ctm
  ```

- or open **System Settings → Privacy & Security**, scroll to the message
  that `ctm` was blocked, and choose **Open Anyway**.

Downloads made from the command line are not quarantined and skip this
dialog entirely:

```sh
curl -sLO https://github.com/calltracking/ctm-cli/releases/download/v<version>/ctm_<version>_darwin_arm64.tar.gz
```

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

The CLI authenticates with your account's **Basic Authentication Token**, found
in CTM under **Account Settings → API Integration**.

Store it in the CLI config (written to `~/.ctm.yml` with `0600` permissions):

```sh
ctm config set --token YOUR_TOKEN
ctm auth check
```

A successful check prints the endpoint and the user you're authenticated as:

```
Endpoint: https://app.ctm.com/graphql
Authenticated as jane@example.com (usr123)
```

You can also supply credentials per invocation or via the environment. The CLI
resolves each value in this order:

1. Command line flags (`--token`, `--endpoint`)
2. Environment variables (`CTM_API_TOKEN`, `CTM_API_ENDPOINT`)
3. Config file (`~/.ctm.yml`, or the path in `CTM_CONFIG` / `--config`)
4. Default endpoint `https://app.ctm.com/graphql`

Inspect the current configuration at any time (the token is redacted unless
you pass `--show-token`):

```sh
ctm config show
```

## Usage

Run `ctm --help` to see every command, or `--help` on any subcommand for its
flags. A few examples:

```sh
# Who am I?
ctm viewer

# View your account
ctm account view

# List tracking sources
ctm account tracking-sources list

# List users, as a table with selected columns
ctm account users list --output table --fields id,email,name

# List virtual phone numbers as CSV
ctm account virtual-phone-numbers list --output csv --fields id,number
```

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

## Environment variables

| Variable           | Purpose                                                  |
| ------------------ | -------------------------------------------------------- |
| `CTM_API_TOKEN`    | Basic Authentication Token used for API requests          |
| `CTM_API_ENDPOINT` | GraphQL endpoint (defaults to `https://app.ctm.com/graphql`) |
| `CTM_CONFIG`       | Path to the YAML config file (defaults to `~/.ctm.yml`)   |

## Support

- API documentation: https://www.calltrackingmetrics.com/developers/
- Questions or problems with the CLI: open an [issue](../../issues) or contact
  CTM support at https://www.calltrackingmetrics.com/support/

## License

The `ctm` CLI is distributed as a binary release, © CallTrackingMetrics. See
the release notes for details on each version.
