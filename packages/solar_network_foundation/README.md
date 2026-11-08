# solar_network_foundation

Reusable building blocks shared by Solar Network Flutter clients:

- `cloud_files.dart` / `cloud_file_widgets.dart` — cloud-file URL building and
  shared presentation primitives.
- `format.dart`, `markdown.dart`, `markdown_content.dart` — formatting and
  markdown rendering.
- `media_kit_init.dart` — idempotent `media_kit` bootstrap.
- `drive/` — the cloud drive service shared by Solian and SolWatt.
- `auth/` — the multi-factor auth form primitives, the factor picker, and the
  step-up elevation (sudo) flow every client needs before a gated mutation.

## Drive host seam

`drive/drive_service.dart` and `drive/upload_tasks.dart` are app-agnostic: they
never read app state directly. Everything they need from the host is declared in
`drive/drive_host.dart` and supplied by the host through Riverpod overrides.

A host **must** override these before any drive code runs, otherwise the drive
throws `UnimplementedError` on first use:

| Provider | Contract |
| --- | --- |
| `driveClientProvider` | authenticated `SolarNetworkClient` |
| `driveServerUrlProvider` | base URL for rendering drive assets |
| `driveSecretStoreProvider` | `setSecret` / `getSecret` for E2EE file keys |
| `driveTaskSinkProvider` | `addTask` / `updateTask` / `getTask` for the host's task overlay |
| `driveNavigatorKeyProvider` | navigator key for sheets shown above the whole app |

Optional:

| Provider | Effect when overridden | Default |
| --- | --- | --- |
| `driveSettingsProvider` | data-saver, image compression, default pool | `const DriveSettings()` |
| `driveErrorReporterProvider` | surfaces upload/download errors to the user | no-op |
| `driveQuotaUpgradePresenterProvider` | shows the host's "buy more storage" flow; `null` hides the action | `null` |

Both apps wire these in `lib/core/drive_wiring.dart`, and both use the same
`driveHostOverrides()` helper in their root `ProviderScope`.

### Task and status types

The drive reports progress through `DriveTaskSink` using `DriveTaskStatus` and
`DriveTaskTypes` / `DriveUploadStage` / `DriveUploadTaskMeta` /
`DriveDownloadTaskMeta`. `DriveTaskStatus` is re-exported from
`solar_network_sdk`; the host maps it onto its own task model (Solian's and
SolWatt's task models differ, so this is the only way to keep one drive copy).

### Localization

The drive reads its strings with `easy_localization`'s `tr()`, so hosts must
ship the drive keys in their own `assets/i18n` catalogs.

## Auth host seam

Stargate gates auth-critical mutations (factors, contacts, passkeys, API keys,
account deletion, mail credentials, login approval) behind a per-session
step-up elevation: the first attempt answers `403 AUTH_SUDO_REQUIRED`, and only
after the caller completes a sudo challenge does the same request go through.

`auth/sudo_prompt.dart` owns that client half for every host:

```dart
await withSudoRetry(context, ref, () => client.drive.deleteFile(id));
```

It runs the action, and on `AUTH_SUDO_REQUIRED` shows the elevation sheet and
retries the *same* action exactly once. Anything else — a 401, an unrelated
403 (a missing permission) — is handed back to the caller untouched, and
backing out of the sheet rethrows the original refusal, so a server that keeps
refusing can never loop the UI. The refusal is identified by the response's
`code`, never by the 403 alone.

A host **must** override the client provider, otherwise the flow throws
`UnimplementedError` on first use:

| Provider | Contract |
| --- | --- |
| `authClientProvider` | authenticated `SolarNetworkClient` (only `client.auth` is used) |

Optional:

| Provider | Effect when overridden | Default |
| --- | --- | --- |
| `authErrorReporterProvider` | surfaces a failed elevation (no factor, rate limit) to the user | no-op |

`auth/auth_form_widgets.dart` and `auth/auth_factor_widgets.dart` hold the
login-style form primitives, the factor picker and the factor descriptions that
both the login flow and the elevation sheet render, so a host names and draws a
factor the same way everywhere.

### Localization

The auth widgets read their strings with `tr()` as well, so hosts must ship the
auth keys (`sudoPromptTitle`, `sudoPromptDescription`, `sudoNoFactors`,
`sudoGranted`, `sudoUnavailable`, `authFactor*`, `loginPickFactor`,
`loginMultiFactor`, `next`, `back`, `password`, …) in their own catalogs.

## Consuming this package

The package lives in the Solian repo and is consumed either by relative path
(Solian itself) or through the repo's git remote (SolWatt). Relative path
dependencies (`../solar_network_sdk`, `../island_ui_foundation`) are resolved
within the same checkout, so all Solar Network packages must come from a single
source in a given app — mixing one package from `path:` and another from `git:`
for the same repo is rejected by pub.
