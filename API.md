# ShipHook Agent API

ShipHook exposes an authenticated JSON API from the same agent that hosts the web UI.

Open `/api` in the web UI for interactive documentation, token generation, and “try it” requests.

## Authentication

Browser sessions use the same secure cookie as the main web UI.

Automation should use bearer tokens:

```sh
curl -H 'Authorization: Bearer shiphook_xxx' https://shiphook.example.com/api/v1/status
```

Create tokens from `/api` or from Account & Security in the web UI. Tokens are stored hashed and are only shown once.

## Endpoints

### `GET /api/v1/repositories`

Returns all configured repositories, their configuration, runtime state, recent builds, and recent releases.

### `GET /api/v1/repository?id=REPOSITORY_ID`

Returns one repository snapshot.

### `GET /api/v1/status?id=REPOSITORY_ID`

Returns one repository runtime status. Omit `id` to return the full dashboard snapshot.

### `GET /api/v1/log?id=REPOSITORY_ID&tail=200`

Returns the latest log tail as JSON. `tail` is clamped to `1...2000`.

Use `/api/log?repo=REPOSITORY_ID` from an authenticated browser session to download the full `.log` file.

### `POST /api/v1/check`

Triggers ShipHook to check for work. If a repository has a buildable update, this can start a build.

```json
{ "repositoryID": "repo-abc" }
```

Omit `repositoryID` to check all repositories.

### `POST /api/v1/build`

Alias for `check`, intended for callers that think in “trigger a build” terms.

### `POST /api/v1/pull`

Pulls the configured branch locally without publishing.

```json
{ "repositoryID": "repo-abc" }
```

### `POST /api/v1/reclone`

Deletes and reclones the configured local checkout. Requires `repositoryID`.

```json
{ "repositoryID": "repo-abc" }
```

### `POST /api/v1/restart`

Requests a soft restart of the ShipHook agent.

### `POST /api/v1/hard-restart`

Schedules a recovery restart that bypasses the main app state. Use this only when the main agent is wedged and ordinary status/command endpoints do not respond.

### `GET /api/v1/files/list?repositoryID=REPOSITORY_ID&path=Sources`

Lists visible files inside the configured checkout. Results are limited to 200 entries.

### `GET /api/v1/files/read?repositoryID=REPOSITORY_ID&path=README.md`

Reads a UTF-8 text file from the configured checkout.

Security limits:

- Paths must stay inside the repository checkout.
- Absolute paths and `..` are rejected.
- `.git` and `.shiphook` are blocked.
- Hidden files are skipped in directory listings.
- File reads are limited to 256 KB.
- Binary/non-UTF-8 files are rejected.

## Token Management

Token management endpoints require an authenticated browser session or an existing bearer token for the same admin.

### `POST /api/auth/tokens`

```json
{ "name": "ci-runner" }
```

Returns the plaintext token once.

### `POST /api/auth/tokens/revoke`

```json
{ "id": "token-id" }
```

Revokes one of the current administrator’s API tokens.

## Audit Log

API token creation, token revocation, build/check/pull/reclone actions, hard restart requests, and other web UI actions are recorded in the web UI audit log.
