---
name: ctm-graphql
description: Use when working with the CallTrackingMetrics (CTM) API — writing GraphQL queries or mutations against the CTM GraphQL API, making direct HTTP requests to it, running ctm CLI commands, accessing call, text, form, report, tracking source, user, or phone number data, or automating CTM account management from scripts and agents.
---

# CTM GraphQL API & CLI

## Overview

The CTM GraphQL API supports two ways of working, and both are covered
here:

- **Direct GraphQL over HTTP (preferred)**: download the published
  `schema.graphql`, derive your operations from it, and `POST` them to the
  API with a short-lived bearer token from `ctm auth token`. This gives
  you the full schema with any GraphQL tooling, while the CLI stays the
  custodian of the long-lived credential.
- **The `ctm` CLI** (<https://github.com/calltracking/ctm-cli>): typed
  commands generated from the schema, plus `ctm exec` to run a GraphQL
  document without handling tokens at all. Best for shell scripts,
  one-liners, and tabular/CSV output.

Either way, never hand-roll authentication headers from the long-lived
Basic Authentication Token — let the CLI hold and exchange it.

The GraphQL conventions below (operations, ids, pagination, timeframes,
money) apply identically to both paths.

Customer phone calls, text messages, and form submissions are exposed as
account-scoped `Activity` values. Activity lists and typed reads come from
Elasticsearch activity history; outbound texts use the existing CTM
delivery workflow.

## Before Doing Anything

1. `ctm version` — confirm the CLI is installed and note the version. If
   not installed, run the installer (it verifies checksums; re-running it
   upgrades only the copy in its own target directory, `~/.local/bin` by
   default). Download it to a file first rather than piping into `sh` — a
   pipe reports only `sh`'s exit status, so a failed download would look
   like a successful install to automation:

   ```bash
   installer=$(mktemp) \
     && curl -fsSL -o "$installer" https://cli.ctm.com/install.sh \
     && sh "$installer" \
     && rm -f "$installer"
   ```

   On macOS with Homebrew, `brew install calltracking/tap/ctm` works too,
   but Homebrew marks what it installs as quarantined and `ctm` is not yet
   notarized, so macOS blocks the first run ("Apple could not verify...").
   Clear the flag once after installing or upgrading — this is why the
   installer above is the smoother path on macOS:

   ```bash
   xattr -dr com.apple.quarantine "$(brew --prefix)/Caskroom/ctm"
   ```

   Builds are also on the
   [releases page](https://github.com/calltracking/ctm-cli/releases).
   An existing Homebrew or system-wide `ctm` upgrades through whatever
   installed it (`brew upgrade ctm`), not through this script — after
   installing, check that `command -v ctm` resolves to the copy you expect,
   since an older binary earlier in PATH still wins.
   This skill tracks the **latest** release: on an older binary, a command
   this skill names (such as `ctm auth token`) or a typed command for a
   newer schema field may not exist yet. When something described here is
   missing, update the CLI rather than working around it — and if you must
   stay on an older binary, download the schema assets from the release
   matching your `ctm version` instead of `latest`, and skip the parts of
   this skill your version predates.
2. `ctm auth check` — reports the endpoint and which credential is in
   play. Skip this (and all credential setup) when the task only needs the
   unauthenticated public API — `ctm public ...`, `ctm exec --public`, or
   a direct `POST` to `/public_graphql` — which deliberately requires no
   token, so an auth failure there is not a blocker.

If an authenticated operation is needed and no credential works, there are
two paths:

- **Interactive**: ask the user to run `ctm auth login` themselves — it opens
  their browser and reuses their CTM session. The token lasts one hour and is
  **read-only unless the user checks "Write access required"** on the
  authorization screen (a read-only token makes mutations fail with a clear
  error — except the rare mutations whose schema description says they are
  permitted for read-only tokens — while queries work normally). **Always ask for
  `ctm auth login --readonly` unless you expect to run mutations** — it pins
  the token to read-only and hides the write-access option, so the session
  never holds more access than the work needs. Only when the user has asked
  for changes that require a mutation should you have them run plain
  `ctm auth login` and check "Write access required". Do not run
  `ctm auth login` yourself to capture its `--show-token` output: the sign-in
  blocks until a person approves the request in the browser, and a captured
  token is a live credential sitting in your transcript for the rest of its
  hour. Once the user has signed in, `ctm auth token` hands you the same
  token through a pipe, with no browser wait.
- **Remote / agent-driven**: when there is no browser on this machine or the
  person who can approve is elsewhere (reachable over chat), run
  `ctm auth login --remote` (add `--readonly` unless you expect to run
  mutations). It prints a URL and a short code — neither is a credential —
  which you relay verbatim to the account holder; they approve in their own
  browser while the command waits, and the token lands in the CLI config
  without ever passing through you. Then use `ctm auth token` as below. The
  code expires after 10 minutes; if nobody approves in time, run it again.

  When your session only needs the bearer token for direct HTTP requests,
  prefer `ctm auth login --agent`: the same relayed approval, pinned
  read-only, but the verified token is printed bare on stdout and **never
  written to any config file**. Capture it straight into a private header
  file rather than echoing it. Shell variables do not survive a fresh
  shell per command, so nothing here relies on one: `mktemp` runs bare so
  its unique path is printed for you to remember (it creates the file
  `0600`), and the host is written out literally in both commands so the
  token is always minted for the host it is sent to:

  ```bash
  mktemp   # prints e.g. /tmp/tmp.k3vAx1 - remember it across your calls
  # pipefail shares the login's command line on purpose: set state dies with
  # a fresh shell just like variables do. Without it a denied or expired
  # sign-in exits through sed's zero status, leaving an empty header file
  # and an unexplained 401 later.
  set -o pipefail; ctm auth login --agent --endpoint https://app.ctm.com/graphql \
    | sed 's/^/Authorization: Bearer /' > /tmp/tmp.k3vAx1
  curl -s --fail-with-body https://app.ctm.com/graphql -H @/tmp/tmp.k3vAx1 \
    -H "Content-Type: application/json" -d @request.json
  rm -f /tmp/tmp.k3vAx1   # when the session ends
  ```

  With `--no-config` in effect the `--endpoint` flag selects the host for
  this run without storing anything. Since nothing is stored, an `--agent`
  sign-in also cannot hijack the identity of other `ctm` processes on a
  shared machine.

  `--agent` always pins the token read-only. When the session's purpose is
  a **mutation** over direct HTTP, use the unpinned ephemeral form —
  `ctm auth login --remote --show-token --no-config --endpoint <host>`,
  with the same literal host as your requests — and ask the approver to
  check "Write access required" on the approval page; otherwise the token
  they grant cannot run it.

  When the session instead needs the typed `ctm` commands (which read the
  credential from the config), scope the stored login to the same private
  temp config on every invocation. Create the directory once with
  `mktemp -d` — never a fixed name like `/tmp/agent-session`, which another
  user on a shared host can pre-create and own, swapping the config out
  from under you — and remember the unique path it prints. In most agent
  harnesses each command runs in a fresh shell, so an `export` made
  alongside the sign-in is gone by the next call and `ctm` silently falls
  back to `~/.ctm.yml` — prefix every command with the remembered path
  instead (or use `--config`):

  ```bash
  mktemp -d      # prints e.g. /tmp/tmp.x1QZk3vA - remember it
  CTM_CONFIG=/tmp/tmp.x1QZk3vA/ctm.yml ctm auth login --remote
  CTM_CONFIG=/tmp/tmp.x1QZk3vA/ctm.yml ctm account users list 12345
  ```

  (In a genuinely persistent shell a single
  `export CTM_CONFIG=$(mktemp -d)/ctm.yml` works.)

  A fresh config also starts with no endpoint. If the target host lives in
  `~/.ctm.yml` as `api_endpoint` rather than in `CTM_API_ENDPOINT`, the
  session config hides it and the sign-in silently targets the production
  default — pass `--endpoint <host>` on the login, which stores it in the
  session config for every later call.

  The prefix belongs on **every** `ctm` invocation for the rest of the
  session, not just the login — including the `ctm auth check` and
  `ctm auth token` calls in the request examples below, which are written
  for the default config. A bare invocation reads `~/.ctm.yml` instead and
  either fails or runs as whatever unrelated credential is stored there.
  Delete the file when the session ends. This matters on a shared machine:
  a stored login outranks `CTM_API_TOKEN` until it expires, so signing in
  against the default `~/.ctm.yml` would silently switch identity for
  every other `ctm` process relying on that exported token. Never print or
  read the config file itself — it holds the live token.
- **Headless / scripts**: set `CTM_API_TOKEN` to the account's Basic
  Authentication Token (found in CTM under **Account Settings → API
  Integration**). Ask the user to provide it through an environment variable
  or secret store. Never print, log, or echo the token.

Credential precedence: `--token` flag, then an unexpired `ctm auth login`
token, then `CTM_API_TOKEN`, then `api_token` in `~/.ctm.yml`.

## Direct HTTP Requests (Preferred)

Authenticated requests are a `POST` to the GraphQL endpoint with a JSON
body of `{"query": ..., "variables": ...}`. Send them to the **same
endpoint the CLI resolved the token for** — the `Endpoint:` line of
`ctm auth check` (default `https://app.ctm.com/graphql`, but `--endpoint`,
`CTM_API_ENDPOINT`, or the config file may select a different host, and a
token minted for one host must never be posted to another). Get a bearer
token from the CLI so the long-lived credential never enters your
commands:

```bash
# One shared endpoint resolution. CTM_API_ENDPOINT and the config file
# are picked up automatically; if you use the per-command --endpoint
# override instead, it must be passed HERE too (`ctm auth check
# --endpoint <host>`) — a flag given to one command never reaches
# another. Then pass $ENDPOINT to every later command explicitly so the
# token is minted for the same host the request goes to.
ENDPOINT=$(ctm auth check | sed -n 's/^Endpoint: //p')

# Pipe the Authorization header to curl's stdin (-H @-, curl >= 7.55)
# instead of expanding the token into the argument list, where `ps` on a
# shared host or a traced script (`set -x`) could expose it. pipefail
# surfaces a failed `ctm auth token` instead of curl's status, and
# --fail-with-body (curl >= 7.76) makes an HTTP 401/5xx exit non-zero
# while keeping the response body. pipefail requires Bash (or zsh/ksh) —
# POSIX sh (e.g. dash as /bin/sh) rejects it, so give scripts a
# #!/usr/bin/env bash shebang.
set -o pipefail
ctm auth token --endpoint "$ENDPOINT" \
  | sed 's/^/Authorization: Bearer /' \
  | curl -s --fail-with-body "$ENDPOINT" -H @- \
      -H "Content-Type: application/json" \
      -d @request.json
```

- `ctm auth token` never prompts or opens a browser: with no usable
  credential it exits non-zero with an error naming the fix. Verify it
  works before wiring it into a pipeline — a silent failure there becomes
  an empty header and a bare 401 — but check the exit status without
  exposing the credential in your transcript or logs:
  `ctm auth token >/dev/null` (or run `ctm auth check`). Never print the
  token itself, and never expand it into a command's argument list.
- The printed token is short-lived — about an hour, whether it was
  exchanged from an API token or is an unexpired `ctm auth login`
  credential printed as-is (the exchange response's `expires_in` is
  authoritative). Treat every emitted token as a secret regardless.
- Re-run `ctm auth token` when a request comes back unauthorized — that is
  what expiry looks like. For a batch of requests, write the header to a
  private temp file once and reuse it, so the token is never expanded in
  any command text — not even in a shell builtin, which `set -x` tracing
  would print:

  ```bash
  set -euo pipefail   # abort on the first failed command or pipeline —
                      # a failed token write must not fall through to curl,
                      # and a failed request must not end the script with
                      # cleanup's exit status. Bash-only: use a
                      # #!/usr/bin/env bash shebang, not #!/bin/sh
  umask 077
  header_file=$(mktemp)
  trap 'rm -f "$header_file"' EXIT   # remove the token file even when the
                                     # script aborts or is interrupted
  ctm auth token --endpoint "$ENDPOINT" \
    | sed 's/^/Authorization: Bearer /' > "$header_file"
  curl -s --fail-with-body "$ENDPOINT" -H @"$header_file" ...   # reuse per request
  ```
- The unauthenticated public API is `/public_graphql` on the same host
  (`https://app.ctm.com/public_graphql` by default) and needs no
  `Authorization` header.
- Derive operations from the published schema files (see "Schema Files"
  below) — do not guess field names or rely on introspection being
  identical across versions.

If the CLI is genuinely unavailable, the underlying exchange is: `POST` to
`/api/v1/auth_tokens/graphql` on the same host, with an `Authorization`
header containing the Basic Authentication Token behind exactly one
`Basic ` prefix. The CLI accepts `CTM_API_TOKEN` with or without that
prefix, but a raw HTTP header must not end up as `Basic Basic ...` — so
build it conditionally:

```sh
# Match the scheme case-insensitively, as the CLI does — "basic <cred>"
# is accepted too and must not gain a second prefix.
case "$CTM_API_TOKEN" in
  [Bb][Aa][Ss][Ii][Cc]\ *) AUTH="$CTM_API_TOKEN" ;;
  *)                       AUTH="Basic $CTM_API_TOKEN" ;;
esac
```

The response is `{"token": "Bearer JWTGQL...", "expires_in": ...}` — the
token value **already includes the `Bearer ` scheme**, so use it as the
whole `Authorization` header value; prepending another `Bearer ` produces
a rejected `Bearer Bearer ...` header. Keep the Basic token in an
environment variable or secret store only — never inline it in a command,
file, or log.

## Finding Commands and Accounts

- `ctm --help` lists every command; `--help` on any subcommand shows its
  flags. Generated commands mirror the GraphQL schema, so if a field exists
  in the schema there is usually a typed command for it.
- Most commands take an account id as their first argument, because one
  token can reach more than one account.
- `ctm viewer` describes the signed-in user or API token.
- `ctm accounts list --output table --fields id,legacyId,name` finds
  account ids.

## Output for Scripting

- `--output raw` — compact JSON, ideal for piping to `jq`.
- `--output csv` / `--output table` with `--fields id,name,createdAt` —
  tabular output with chosen columns.
- `--field path.to.value` — print a single value by dot path, relative to
  the command's result. Typed commands unwrap their root field, so it is
  `ctm viewer --field email`; only `ctm exec` keeps the full response
  `data` root, where the same value is `--field viewer.email`.
- Default is `--output pretty` (colorized JSON); color is skipped
  automatically when output is not a terminal.

## Customer Activities

`Activity` is a GraphQL interface implemented by `PhoneCall`,
`TextMessage`, and `FormSubmission`. Its `id` and `legacyId` identify the
underlying Call activity record. A text's separate Message identity is in
`messageId`; a form's configured reactor identity is in `formId`.

When a request names a call or call ID, read it directly with
`ctm account phone-call view ACCOUNT_ID ACTIVITY_ID`. When the request names
an activity whose kind is unknown, use `ctm account activity view` first,
then read the corresponding typed record. Do not fall back to the v1 REST
API merely because the underlying record is called a Call; consider v1 only
after confirming the requested data is absent from the current schema that
matches the installed CLI.

The generated CLI can list the common activity fields and read each concrete
kind (including call transcript and summary):

```bash
ctm account activities list ACCOUNT_ID \
  --all --kinds PHONE_CALL,TEXT_MESSAGE \
  --start-at 2026-08-01T00:00:00Z \
  --end-at 2026-09-01T00:00:00Z \
  --order OCCURRED_AT --sort-mode DESC

ctm account activity view ACCOUNT_ID ACTIVITY_ID
ctm account phone-call view ACCOUNT_ID ACTIVITY_ID
ctm account text-message view ACCOUNT_ID ACTIVITY_ID
ctm account form-submission view ACCOUNT_ID ACTIVITY_ID
```

List output contains fields common to every activity. Use `ctm exec` with
inline fragments when one result set needs concrete fields, including form
custom fields:

```graphql
query CustomerActivity(
  $accountId: ID!
  $first: Int!
  $after: String
  $kinds: [ActivityKind!]
  $startAt: Instant
  $endAt: Instant
) {
  account(id: $accountId) {
    activities(
      first: $first
      after: $after
      kinds: $kinds
      startAt: $startAt
      endAt: $endAt
      order: OCCURRED_AT
      sortMode: DESC
    ) {
      nodes {
        __typename
        id
        legacyId
        occurredAt
        direction
        contactName
        contactNumber
        ... on PhoneCall {
          fromNumber
          toNumber
          status
          durationSeconds
          talkTimeSeconds
          transcription
          summary
        }
        ... on TextMessage {
          messageId
          fromNumber
          toNumber
          body
          status
        }
        ... on FormSubmission {
          formId
          formName
          submitterName
          submitterEmail
          callbackNumber
          fields { id label labels value }
        }
      }
      pageInfo { hasNextPage endCursor }
    }
  }
}
```

The activity connection is forward-only search-after pagination. Use
`first`/`after` or the generated command's `--all`; `last` and `before` are
not supported. `startAt` and `endAt` are inclusive exact instants. Results
and fields honor account membership, call-log visibility, text access, and
audio access; a null transcript, summary, body, or phone field can therefore
mean either absent data or restricted visibility.

To queue a text, use the named mutation through `ctm exec` (or direct
GraphQL). This requires a login authorized for write access, an SMS-enabled
account and agency, and call-log access to texts:

```graphql
mutation SendCustomerText($input: SendTextMessageInput!) {
  sendTextMessage(input: $input) {
    messageId
    activityId
    status
    errors
  }
}
```

Pass `accountId`, `toNumber`, `body`, and optionally
`fromTrackingNumberId` or `statusCallbackUrl`. Always inspect the payload's
`errors` even when the HTTP request itself succeeds. The text `activityId`
may be null until background processing creates its Call activity record.

## Object IDs

- `id` values in API responses are **opaque global ids**, unique across
  every object type. Hold them and pass them back; never parse them, build
  them by hand, or compare them numerically.
- Model-specific id arguments are polyglot: they also accept the numeric
  id shown in the CTM app and the opaque id from CTM web app URLs. The
  generic `node`/`nodes` lookups are the exception — they take only the
  opaque global id, and return null for a bare number.
- Type checking applies to the opaque forms: passing a tracking source's
  global id where a user id is expected returns "not found" rather than
  loading the wrong record. A bare number carries no type — the argument
  supplies the expected model, so a number copied from the wrong object
  can silently resolve an unrelated record that happens to share that
  database id. Prefer global ids in scripts; the plain number is the only
  unchecked form.
- When you need the plain numeric id (for the v1 REST API, spreadsheets, or
  exports), select `legacyId` alongside `id` — where the type defines it.
  Most entity types do, but not all (`AccountBillingAddress`, for example,
  has only the opaque `id`), and selecting it where it does not exist fails
  validation, so check the schema. It is a string of digits, not a JSON
  number, because ids can exceed exact JSON number range — in JavaScript
  parse it with `BigInt()`, not `Number()`.
- Do not use deprecated `numericId` fields in new work.

## Writing GraphQL Operations

These rules apply to every GraphQL document, whether you send it with
direct HTTP or through `ctm exec`, which runs a document from a file or
stdin without you touching tokens:

```sh
echo 'query Viewer { viewer { id email } }' | ctm exec
ctm exec --input ./query.graphql --variables '{"accountId": "12345", "first": 25}'
ctm exec --input ./query.graphql --variables-file ./vars.json
```

Rules for the documents themselves:

- Always name operations, and always pass dynamic values (ids, filters,
  cursors, limits) as variables.
- Keep field selections specific to the use case. Include `id` on the
  entity types you select — but only where the type defines it; value
  objects such as `Money` and `PageInfo` have no `id`, and selecting one
  there fails validation. Check the schema when unsure.
- In **queries**, account-scoped data nests under `account(id:)`.
  **Mutations** do not nest: they live at the `Mutation` root and carry
  account scope inside their input (e.g. `createVoiceBot(input:)` takes
  `accountId` in the input object) — read each mutation's input type from
  the schema rather than looking for a `Mutation.account` field:

  ```graphql
  query AccountTrackingSources($accountId: ID!, $first: Int, $after: String) {
    account(id: $accountId) {
      trackingSources(first: $first, after: $after, order: NAME, sortMode: ASC) {
        totalCount
        nodes {
          id
          legacyId
          name
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
  ```

- Most collection fields are Relay-style connections (their type name ends
  in `Connection`). Paginate those with `first` and `after`, looping while
  `pageInfo.hasNextPage` using `pageInfo.endCursor`, and never try to fetch
  an unbounded connection in one request. Some fields return a plain list
  instead — they take no `first`/`after` and have no `pageInfo`, so select
  them directly. Check the field's type in the schema file rather than
  assuming.
- `order` picks the column; `sortMode` picks the direction. Pass both
  whenever you pass either — each collection declares its own defaults and
  the default direction is not uniform across collections. Read the
  declared defaults from the schema file rather than assuming.
- Some collections (`accounts`, `activities`, `users`, `virtualPhoneNumbers`) default to
  `order: RELEVANCE`, which ranks by search score against `filter`;
  `sortMode` never affects the ranking itself. What happens on tied scores
  differs: `accounts`, `activities`, and `virtualPhoneNumbers` fall back to
  a fixed newest-first tie breaker, while `users` falls back to a user-ID
  tie breaker that does follow `sortMode` — so on an unfiltered `users`
  list the direction still changes the order. Relevance is only meaningful
  when `filter` is set; when listing without search text, name the column
  you actually want.
- Enum values are UPPER_SNAKE (`NAME`, `UPDATED_AT`, `ASC`); field and
  argument names are camelCase.

## Timeframe Arguments

- Instant bounds are named `startAt` / `endAt` and typed `Instant`: a full
  ISO8601 timestamp **with an explicit offset**, e.g.
  `"2026-08-01T00:00:00Z"`. A bare date on an `Instant` bound is a
  deliberate coercion error, not a value silently expanded to midnight.
- Calendar-date bounds are named `startOn` / `endOn` and take a bare
  `YYYY-MM-DD`. A timestamp on a date bound is rejected the same way.
- Each bound's schema description states inclusivity and the timezone it
  resolves in; date bounds generally resolve in the account's timezone.
- The v1 REST API's `start_date` / `end_date` parameter names never appear
  in GraphQL — do not carry them over.

## Money Values

Money is a structured object, never a bare number:

```graphql
{ amount currency minorUnits scale }
```

- `amount` is the value in the currency's major unit as a decimal string
  (e.g. `"59.0025"`), exact and unrounded. Pass it through as-is for
  display, CSV, or export. Never accumulate it as a binary float — totals
  drift.
- For exact arithmetic use `minorUnits` with `scale` (`minorUnits`
  `"590025"` at scale 4 is 59.0025). Like `amount`, `minorUnits` arrives as
  a **signed integer string**, not a JSON number — `"-500"` is a legitimate
  value (a credit or negative balance), so do not validate it as
  digits-only. Parse it with an arbitrary-precision integer type
  (`BigInt()` in JavaScript). `scale` varies between values, so normalize
  to a common scale before comparing or summing `minorUnits`.
- `currency` is a currency code enum (currently `USD`).

## Public API

The unauthenticated public API (`public_schema.graphql`) is served at
`https://app.ctm.com/public_graphql` and needs no token. Through the CLI:

```sh
ctm public rack-rate-plans list
ctm exec --public --input ./public-query.graphql
```

## Schema Files

Every CLI release attaches the exact GraphQL schemas the binaries were
generated from — the API contract for that version:

```sh
curl -sLO https://github.com/calltracking/ctm-cli/releases/latest/download/schema.graphql
curl -sLO https://github.com/calltracking/ctm-cli/releases/latest/download/public_schema.graphql
```

If the installed binary is not the latest release, download from the
release tagged `v<ctm version>` instead of `latest`, so the schema you
derive operations from matches the binary's generated commands.

Use them as the source of truth for field names, argument types, enum
values, and declared defaults; for code generation (`graphql-codegen`,
Apollo) and query linting; and diff between releases (e.g.
`graphql-inspector diff`) to see how the API changed.

## Safety

- Mutations change live account configuration. Show the user the mutation
  and variables and get confirmation before executing one; prefer read-only
  queries when exploring. A `ctm auth login` token only permits mutations
  when the user checked "Write access required" while authorizing — a
  mutation rejected as read-only means the user has to sign in again with
  write access, not that the operation is wrong.
- GraphQL responses can carry both partial `data` and an `errors` array —
  check both before treating a request as successful.
- Exports the user asked for (CSV/JSON of reports, numbers, users)
  legitimately contain real customer data — write them to the destination
  the user chose. Everywhere else — example queries, documentation, logs,
  bug reports, anything shared beyond that destination — use placeholders,
  never real phone numbers, tokens, or customer data.
