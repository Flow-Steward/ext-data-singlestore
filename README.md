# SingleStore for Flow Steward

Connect **SingleStore** datasets and run parameterized workflow writes. This repository contains one installable SingleStore extension, version **1.3.2**, with separate Linux AMD64 and ARM64 archives. No other database can be selected or installed from this package.

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

Google MCP Toolbox is implementation tooling, pinned to tag `v1.3.0`, commit `b0010060a939455d91e4f8ba62dc3e72b1892469`. Its fixed native build registers only this repository's SingleStore interfaces. Installation and runtime download no drivers. Existing native binaries and provenance are unchanged by the 1.3.0 UI/schema correction.

To package the existing verified binaries:

```sh
python3 scripts/package_extension.py --runtime-target linux-amd64
python3 scripts/package_extension.py --runtime-target linux-arm64
```

`scripts/build_toolbox.sh` is the optional pinned implementation rebuild; it cannot select another database. `toolbox-provenance.json`, `THIRD_PARTY.yml` and root `SHA256SUMS` describe the native payloads. Each installer ZIP contains exactly one executable for its target and target/native metadata. The byte-exact Apache-2.0 license is in `LICENSE`; implementation notices are in `NOTICE`.

## Verification limits

Manifest isolation checks cover friendly names, database-specific fields, credential separation and the exact shipped SQL profiles. Contract tests cover scope/ref checks, parameter separation, test-mode suppression, output bounds and unknown write outcomes. No live SingleStore credentials were supplied; compile and contract evidence does not establish a successful authenticated database connection.
