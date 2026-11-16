#!/bin/bash
# Fetch the source trees build.sh needs, at the pinned commits.
# Clones into this directory; they are git-ignored.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

clone_at() {
    local dir="$1" url="$2" commit="$3"
    if [[ -d "$ROOT/$dir/.git" ]]; then
        echo "==> $dir already present"
    else
        echo "==> cloning $dir"
        git clone --quiet "$url" "$ROOT/$dir"
    fi
    git -C "$ROOT/$dir" fetch --quiet origin || true
    git -C "$ROOT/$dir" checkout --quiet "$commit"
    echo "    $dir @ $(git -C "$ROOT/$dir" rev-parse --short HEAD)"
}

clone_at upstream     https://github.com/OpenIntelWireless/IntelBluetoothFirmware.git a414375505fa3b014be32f8fca31b5bbfdf9f10f
clone_at MacKernelSDK https://github.com/acidanthera/MacKernelSDK.git 3f75008
clone_at Lilu         https://github.com/acidanthera/Lilu.git 0249c3a

echo "==> diagnostics patch"
if git -C "$ROOT/upstream" apply --check "$ROOT/diffs/diag-vs-master.diff" 2>/dev/null; then
    git -C "$ROOT/upstream" apply "$ROOT/diffs/diag-vs-master.diff"
    echo "    applied diffs/diag-vs-master.diff"
elif git -C "$ROOT/upstream" apply --reverse --check "$ROOT/diffs/diag-vs-master.diff" 2>/dev/null; then
    echo "    already applied"
else
    echo "    warning: patch did not apply; upstream will build unmodified" >&2
fi

echo
echo "==> done. Now run ./build.sh"
