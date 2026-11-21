#!/bin/sh
# Runs stamp-version.sh against throwaway git repositories and checks the stamped plist.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/stamp-version.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

new_plist() {
    plist="$work/Info.plist"
    rm -f "$plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string placeholder" \
        -c "Add :CFBundleVersion string placeholder" "$plist" >/dev/null
}

new_repo() {
    repo="$work/repo-$1"
    git init -q "$repo"
    git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "first"
}

# Annotated and unsigned, like the tags the semver-tag workflow pushes
tag() {
    git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c tag.gpgSign=false tag -a -m "$1" "$1"
}

commit() {
    git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "$1"
}

expect() {
    label=$1 version=$2 build=$3
    actual_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
    actual_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
    if [ "$actual_version" = "$version" ] && [ "$actual_build" = "$build" ]; then
        echo "PASS $label"
    else
        echo "FAIL $label: got $actual_version ($actual_build), want $version ($build)"
        failures=$((failures + 1))
    fi
}

new_plist
new_repo untagged
commit second
sh "$script" "$plist" "$repo"
expect "no tag stamps 0.0.0 and the commit count" 0.0.0 2

new_plist
new_repo prerelease
tag v0.1.0
commit second
tag v0.1.1-rc1
sh "$script" "$plist" "$repo"
expect "a tag that is not plain vX.Y.Z is ignored" 0.1.0 2

new_plist
new_repo ordering
tag v1.9.0
commit second
tag v1.10.0
sh "$script" "$plist" "$repo"
expect "v1.10.0 sorts after v1.9.0" 1.10.0 2

new_plist
new_repo newest
tag v1.0.0
commit second
tag v1.1.0
sh "$script" "$plist" "$repo"
expect "the newest of several tags wins" 1.1.0 2

new_plist
git init -q "$work/empty-repo"
sh "$script" "$plist" "$work/empty-repo"
expect "a repository without commits stamps 0.0.0 and 0" 0.0.0 0

new_plist
new_repo other-branch
tag v0.2.0
git -C "$repo" checkout -q -b side
commit side
tag v9.0.0
git -C "$repo" checkout -q -
sh "$script" "$plist" "$repo"
expect "a tag not reachable from HEAD is ignored" 0.2.0 1

new_plist
mkdir -p "$work/not-a-repo"
sh "$script" "$plist" "$work/not-a-repo"
expect "outside a git repository stamps 0.0.0 and 0" 0.0.0 0

[ "$failures" -eq 0 ]
