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
  API with a short-lived bearer token from the applicable CLI login flow
  below. This gives you the full schema with any GraphQL tooling without
  handling a long-lived credential directly.
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

First determine whether `ctm` is already installed locally:

```bash
command -v ctm
```

### Existing local installation

1. Record the installed version and resolve the latest release before using
   the CLI:

   ```bash
   installed_version=$(ctm version | sed -n '1s/^ctm //p')
   latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
     https://github.com/calltracking/ctm-cli/releases/latest)
   latest_version=${latest_url##*/}
   latest_version=${latest_version#v}
   printf 'installed=%s latest=%s\n' "$installed_version" "$latest_version"
   ```

   If the versions differ, tell the user which version is installed and
   suggest upgrading to the latest release before continuing. Do not replace
   an existing install automatically. It must be upgraded through the method
   that installed it, for example `brew upgrade ctm` for Homebrew; standalone
   builds and instructions are on the
   [releases page](https://github.com/calltracking/ctm-cli/releases). If the
   user continues on an older version, use the schema assets from its matching
   `v<installed_version>` release and do not assume newer commands exist.

2. For authenticated work, use the standard local login flow: run
   `ctm auth check`, and if it reports no usable credential, have the user run
   plain `ctm auth login`. Do not substitute `--agent`, `--remote`,
   `--show-token`, `--no-config`, or `--readonly` for an existing local
   installation. The authorization page leaves the token read-only unless the
   user checks **Write access required**; tell them to check it only when the
   requested mutation requires write access. After login, use `ctm auth token`
   through a pipe as shown below rather than printing or capturing it.

Skip authentication when the task only needs the unauthenticated public API:
`ctm public ...`, `ctm exec --public`, or a direct `POST` to
`/public_graphql`.

### No local installation

Install the latest CLI into a unique temporary directory for this session
only. Never install it into `~/.local/bin`, Homebrew, or another persistent
location, and never alter the user's `PATH`. Download the installer before
running it so a failed download cannot be hidden by a shell pipeline:

```bash
session_dir=$(mktemp -d)
curl -fsSL -o "$session_dir/install.sh" https://cli.ctm.com/install.sh
CTM_INSTALL_DIR="$session_dir/bin" sh "$session_dir/install.sh"
printf 'Temporary ctm directory: %s\n' "$session_dir"
```

Remember the printed absolute directory. Agent tool calls often start fresh
shells, so use the absolute binary path (for example
`/tmp/tmp.x1QZk3vA/bin/ctm`) on every later invocation instead of relying on
`session_dir` or an exported `PATH`.

Do not use `ctm auth check`, a stored config, `CTM_API_TOKEN`, or the standard
browser login with this temporary install. Authenticate ephemerally and pipe
the token directly into a private header file inside the same temporary
directory:

- For queries and any mutation whose schema explicitly permits a read-only
  token, use `ctm auth login --agent`. It is shorthand for
  `--remote --readonly --show-token --no-config`.
- Only for a mutation that the schema does not permit with a read-only token,
  use `ctm auth login --remote --show-token --no-config` and tell the approver
  to check **Write access required**.

Use the same literal endpoint for login and every request. `--show-token`
owns stdout while the approval URL and short code remain visible on stderr;
pipe stdout immediately and never print, echo, command-substitute, or otherwise
capture the live token in the transcript:

```bash
# Read-only query or read-only-permitted mutation:
set -o pipefail; /tmp/tmp.x1QZk3vA/bin/ctm auth login --agent \
  --endpoint https://app.ctm.com/graphql \
  | sed 's/^/Authorization: Bearer /' \
  > /tmp/tmp.x1QZk3vA/authorization-header

# Write mutation instead (replace the command above, do not run both):
set -o pipefail; /tmp/tmp.x1QZk3vA/bin/ctm auth login --remote \
  --show-token --no-config --endpoint https://app.ctm.com/graphql \
  | sed 's/^/Authorization: Bearer /' \
  > /tmp/tmp.x1QZk3vA/authorization-header

curl -s --fail-with-body https://app.ctm.com/graphql \
  -H @/tmp/tmp.x1QZk3vA/authorization-header \
  -H "Content-Type: application/json" -d @request.json
```

The approver follows the URL and short code printed by the login command; the
code expires after 10 minutes. Remove the exact temporary session directory
when the work ends. It contains the CLI, installer, and live bearer-token
header and must not survive the session:

```bash
rm -rf -- /tmp/tmp.x1QZk3vA
```

Credential precedence for an existing local install is: `--token` flag, then
an unexpired `ctm auth login` token, then `CTM_API_TOKEN`, then `api_token` in
`~/.ctm.yml`.

## Direct HTTP Requests (Preferred)

Authenticated requests are a `POST` to the GraphQL endpoint with a JSON
body of `{"query": ..., "variables": ...}`. A token minted for one host
must never be posted to another. With an existing local installation, send
requests to the endpoint reported by `ctm auth check` (default
`https://app.ctm.com/graphql`, but `--endpoint`, `CTM_API_ENDPOINT`, or the
config file may select a different host) and get a bearer token from the CLI
so the long-lived credential never enters your commands. With a temporary
installation, skip this token-exchange example and use the endpoint and
private header file created in the no-installation flow above.

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
