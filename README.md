# SingleStore for Flow Steward

Flow Steward extension `flowsteward.data-connector-mcp-toolbox-singlestore`, version **1.3.7**.

Connect SingleStore application data to Flow Steward for reusable lookups and workflow updates. The Dataset connector provides connection testing, typed schema inspection, saved SQL validation, previews, query execution and output-schema inference. Table and column resource selections constrain Dataset queries, while query parameters let the same saved definition accept different workflow values. Read results are limited to 100 rows and 480 KiB of inline output.

A separate execute_write action runs one INSERT, UPDATE or DELETE against a selected project connection. SQL uses named parameters and a values object, with an optional parameter schema, so reusable statements can accept record identifiers, statuses and other workflow values. For example, read records that need attention, send them through a review workflow, then update their status or insert a processing result using the record identifier as a parameter.

Set up the connection with an explicit SingleStore host, port, database and user, and keep the password in connection secrets. Reads remain read-only even when workflow write steps are available. This extension exposes selected SQL data access rather than database triggers, schema administration or multi-statement scripts. Use returned records in subsequent steps for branching, notifications or follow-up processing, and use separate write steps to persist the outcome.

Create a project SingleStore connection with host, port, database and user, plus a nonempty secret password. Give the database user the read privileges needed for Dataset queries and the INSERT/UPDATE/DELETE grants required by your workflow steps.

## Set up a SingleStore connection

Create a project connection using these settings:

| Setting | Meaning |
| --- | --- |
| `host` | SingleStore host. Required. |
| `port` | SingleStore port. Required. |
| `database` | SingleStore database. Required. |
| `user` | SingleStore user. Required. |

Store the SingleStore user password in the connection secrets. The pinned source requires a nonempty password; datasets may alternatively use their password environment secret. Resolved dataset secret environment values are forwarded to the native process; direct environment overrides retain their established precedence. Dataset advanced environment exposes only the named SINGLESTORE_ source variables; password overrides remain in secrets. Writer connections use the explicit settings above.

## Read datasets and write from workflows

Datasets support connection testing, typed schema introspection, saved SQL, visual-query resource scope validation, bounded previews and execution. Read queries use the native read-only path and are capped at 100 rows and 480 KiB inline output. No trigger surface is exposed.

`execute_write` runs one INSERT, UPDATE or DELETE on the selected SingleStore project connection. Provide `connection_ref`, SQL with named `:parameters`, a `params` object and optional JSON `param_schema`. Values stay separate from SQL and use native driver binding. The server must support the supplied SQL syntax.

The host resolves matching project configuration and secrets, account/project scope, execution context and a durable external-effect claim. Test mode suppresses writes before a driver starts. Writes execute once; uncertain dispatched failures return `retryable: false` and require checking the database before a manual retry. Workflow writes do not make dataset queries writable.

The bounded SQL subset refuses raw dollar characters and backslashes in read SQL; write SQL also refuses raw dollar characters. Put those values in bound parameters. A top-level read LIMIT accepts one integer literal with an optional integer OFFSET. The existing SQL safety guards are unchanged; 1.3.0 adds database-specific settings validation and preserves native payloads.

## Upgrade compatibility

The visible name is SingleStore. The legacy extension ID `flowsteward.data-connector-mcp-toolbox-singlestore`, project connection type `toolbox_sql_writer`, dataset connector IDs and action IDs remain unchanged so existing installations and workflows can upgrade. These are internal compatibility identifiers, not a second database selector.

## Technical implementation and packaging

Google MCP Toolbox is implementation tooling, pinned to tag `v1.16.0`, commit `06ea49d9a487a72c22419b5a8d5c22c11f0d7485`. Its fixed native build registers only this repository's SingleStore interfaces. Installation and runtime download no drivers. Native binaries are rebuilt with Go 1.27.4 and the reviewed module baseline; toolbox-provenance.json records exact patches, dependencies and binary digests.

To package the existing verified binaries:

```sh
python3 scripts/package_extension.py --runtime-target linux-amd64
python3 scripts/package_extension.py --runtime-target linux-arm64
```

`scripts/build_toolbox.sh` is the optional pinned implementation rebuild; it cannot select another database. `toolbox-provenance.json`, `THIRD_PARTY.yml` and root `SHA256SUMS` describe the native payloads. Each installer ZIP contains exactly one executable for its target and target/native metadata. The byte-exact Apache-2.0 license is in `LICENSE`; implementation notices are in `NOTICE`.

## Verification limits

Manifest isolation checks cover friendly names, database-specific fields, credential separation and the exact shipped SQL profiles. Contract tests cover scope/ref checks, parameter separation, test-mode suppression, output bounds and unknown write outcomes. No live SingleStore credentials were supplied; compile and contract evidence does not establish a successful authenticated database connection.

## Automated releases

CI runs on pull requests and pushes to `main`. Official releases run through the
pinned shared GitHub Actions workflow using `.github/release-config.json` to test,
package both Linux runtime targets, and publish the release assets automatically.
Manual ZIP uploads are not part of the release process.

After merging the version **1.3.7** update into `main`, create and push its tag:

```sh
git switch main
git pull --ff-only
git tag -a v1.3.7 -m "Release v1.3.7"
git push origin v1.3.7
```

To rerun the workflow for an existing tag without moving it:

```sh
gh workflow run release.yml --ref main -f tag=v1.3.7
```

The manifest remains the source for release identity and catalog descriptions.
The shared workflow installs the verified first-party SDK wheel before test
dependencies. Where native payloads are absent from source, the recipe restores
only the listed missing files from checksum-pinned published archives; the source
packager still verifies their provenance before packaging.
