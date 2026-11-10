#!/bin/sh
# Rebuild only SingleStore for Linux AMD64 and ARM64 from pinned implementation source.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VARIANT=singlestore
TOOLBOX_TAG=v1.16.0
TOOLBOX_COMMIT=06ea49d9a487a72c22419b5a8d5c22c11f0d7485
BOOTSTRAP_IMAGE=golang:1.27.3-bookworm@sha256:dc0963f32053e4bc451d24d87e3892d42d01021b61f093e98eb95c0352bb84b0
PATCH=scripts/patches/0001-flowsteward-driver-bound-query-params.patch
SECURITY_PATCH=scripts/patches/0003-flowsteward-security-dependencies.patch
PROFILE_PATCH=scripts/patches/0004-flowsteward-approved-profiles.patch
# This repository pins only SingleStore SQL interfaces.
test -f "$ROOT/scripts/toolbox-prebuilts.txt" \
  || { echo "[FAIL] missing fixed database prebuilt list" >&2; exit 2; }
PREBUILTS=$(cat "$ROOT/scripts/toolbox-prebuilts.txt")
mkdir -p "$ROOT"

# Optional clean checkout must match the exact pinned source revision.
set --
if test -n "${FS_TOOLBOX_SOURCE_DIR:-}"; then
  set -- --mount "type=bind,source=$FS_TOOLBOX_SOURCE_DIR,target=/upstream,readonly"
fi

docker run --rm --cpus=2 --memory=4g \
  -v flow-steward-db-batch-go-cache:/go/pkg/mod -v flow-steward-db-batch-build-cache:/root/.cache/go-build \
  -e TOOLBOX_TAG="$TOOLBOX_TAG" -e TOOLBOX_COMMIT="$TOOLBOX_COMMIT" -e PATCH="$PATCH" \
  -e PROFILE_PATCH="$PROFILE_PATCH" -e SECURITY_PATCH="$SECURITY_PATCH" -e GOTOOLCHAIN=local -e GOFLAGS=-mod=readonly \
  -e PREBUILTS="$PREBUILTS" -e VARIANT="$VARIANT" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$ROOT:/out" "$@" "$BOOTSTRAP_IMAGE" sh -c '
    set -eu
    sh /out/scripts/install-go-toolchain.sh /out/scripts/go-toolchain-selected.json
    if test -d /upstream/.git; then
      test -z "$(git -c safe.directory=/upstream -C /upstream status --porcelain)"
      cp -a /upstream /src
    else
      git clone --quiet --filter=blob:none --branch "$TOOLBOX_TAG" --depth 1 \
        https://github.com/googleapis/mcp-toolbox.git /src
    fi
    git config --global --add safe.directory /src
    test "$(git -C /src rev-parse HEAD)" = "$TOOLBOX_COMMIT"
    cd /src
    git apply --check "/out/$SECURITY_PATCH"
    git apply "/out/$SECURITY_PATCH"
    sha256sum go.mod go.sum > /tmp/locked-modules.sha256
    git apply --check "/out/$PROFILE_PATCH"
    git apply "/out/$PROFILE_PATCH"
    git apply --check "/out/$PATCH"
    git apply "/out/$PATCH"

    # Every resource type the prebuilt configurations name ...
    : > /tmp/types
    for prebuilt in $PREBUILTS; do
      file="internal/prebuiltconfigs/tools/$prebuilt.yaml"
      test -f "$file" || { echo "[FAIL] Toolbox $TOOLBOX_TAG has no prebuilt $prebuilt" >&2; exit 2; }
      sed -n "s/^type:[[:space:]]*\([a-z0-9-]*\).*/\1/p" "$file" >> /tmp/types
    done
    sort -u /tmp/types -o /tmp/types
    # ... mapped to the package that registers it.
    : > /tmp/packages
    while read -r type; do
      dir=$(grep -rlE "^const [A-Za-z]+ string = \"$type\"$" internal/sources internal/tools \
        | xargs -r -n1 dirname | sort -u)
      test "$(printf "%s\n" "$dir" | grep -c .)" = 1 \
        || { echo "[FAIL] type $type is registered by: ${dir:-nothing}" >&2; exit 2; }
      printf "github.com/googleapis/mcp-toolbox/%s\n" "$dir" >> /tmp/packages
    done < /tmp/types
    sort -u /tmp/packages -o /tmp/packages
    awk "NR==FNR { keep[\"\\\"\" \$0 \"\\\"\"] = 1; next }
         /internal\/(sources|tools|prompts|resources)\// { if (keep[\$2]) print; next }
         { print }" /tmp/packages cmd/internal/imports.go > /tmp/imports.go
    test "$(grep -c "internal/\(sources\|tools\|prompts\|resources\)/" /tmp/imports.go)" = "$(wc -l < /tmp/packages)" \
      || { echo "[FAIL] a needed package is not in cmd/internal/imports.go" >&2; exit 2; }
    mv /tmp/imports.go cmd/internal/imports.go
    echo "[PASS] $VARIANT: $(wc -l < /tmp/types) types from $(wc -l < /tmp/packages) packages for: $PREBUILTS"
    cp /tmp/packages "/out/packages.txt"

    gofmt -w internal/util/flowstewardbinding internal/sources/sqlite internal/sources/singlestore internal/sources/oceanbase internal/sources/clickhouse internal/sources/snowflake internal/sources/spanner
    go test -mod=readonly -p 1 ./internal/util/flowstewardbinding ./internal/tools/singlestore/singlestoreexecutesql ./internal/sources/singlestore
    for package in $(cat /tmp/packages | grep /internal/sources/); do
      go test -mod=readonly -p 1 -run TestFlowStewardBoundWrite "./${package#github.com/googleapis/mcp-toolbox/}"
    done
    export SOURCE_DATE_EPOCH=1779400183
    for target in linux-amd64 linux-arm64; do
      arch=${target#linux-}
      mkdir -p "/out/bin/$target"
      CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -mod=readonly -p 1 -trimpath -buildvcs=false \
        -ldflags "-s -w -buildid= -X github.com/googleapis/mcp-toolbox/cmd.buildType=flowsteward.dataset-connectors -X github.com/googleapis/mcp-toolbox/cmd.commitSha=$TOOLBOX_COMMIT" \
        -o "/out/bin/$target/toolbox" .
      chmod 0755 "/out/bin/$target/toolbox"
      echo "[PASS] $VARIANT $target: $(stat -c %s "/out/bin/$target/toolbox") bytes"
    done
    sha256sum -c /tmp/locked-modules.sha256
    chown -R "$HOST_UID:$HOST_GID" "/out/bin" "/out/packages.txt"
  '

python3 "$ROOT/scripts/provenance.py"
