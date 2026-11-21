#!/bin/sh
# Writes the release version into a built app's Info.plist.
# Usage: stamp-version.sh <info-plist> [repo-dir]
#
# The version is the highest plain vX.Y.Z tag reachable from HEAD (the tags main's CI adds per
# release); the build number is the commit count. Without git or a tag the build still succeeds
# and reads 0.0.0, so an untagged build is recognisable.
set -eu

plist=$1
repo=${2:-"$(cd "$(dirname "$0")/.." && pwd)"}

# Same pattern as the semver-tag workflow, so a tag like v1.2.3-rc1 never becomes the version
semver='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
# Outside a repository, or before its first commit, both git calls fail quietly to the defaults
tag=$(git -C "$repo" tag --merged HEAD --sort=-v:refname 2>/dev/null | grep -E "$semver" | head -n 1)
version=${tag#v}
version=${version:-0.0.0}
build=$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $build" "$plist"
echo "stamped $version ($build) into $plist"
