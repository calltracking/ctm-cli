#!/bin/sh
# Installer for the ctm CLI (https://github.com/calltracking/ctm-cli).
#
#   curl -fsSL https://cli.ctm.com/install.sh | sh
#
# Installs into a user-private directory (no sudo, ever — the same model as
# other modern CLI installers), or upgrades the copy there in place.
# Environment overrides:
#   CTM_VERSION      install a specific version (e.g. "0.7.0")
#   CTM_INSTALL_DIR  install into this directory instead of ~/.local/bin
#
# For a system-wide install use Homebrew (brew install calltracking/tap/ctm)
# or move the binary yourself after installing.
#
# POSIX sh only — no bashisms; /bin/sh may be dash.
set -eu

REPO="calltracking/ctm-cli"

say() { printf '%s\n' "$*"; }
fail() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

# --- platform ---------------------------------------------------------------
case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux)  os=linux ;;
  *) fail "unsupported OS '$(uname -s)'. On Windows, download the zip from https://github.com/$REPO/releases/latest" ;;
esac

case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64)  arch=amd64 ;;
  *) fail "unsupported architecture '$(uname -m)'. Download a build from https://github.com/$REPO/releases/latest" ;;
esac

# --- version ----------------------------------------------------------------
# The release workflow renders the released version into this assignment when
# syncing the script to the public repository, so the served installer and
# the assets it downloads always come from the same immutable release. The
# source-tree copy keeps the placeholder and resolves the latest release.
RENDERED_VERSION="0.12.2"

if [ -n "${CTM_VERSION:-}" ]; then
  version=${CTM_VERSION#v}
elif [ "$RENDERED_VERSION" != "__CTM_VERSION""__" ]; then
  version=$RENDERED_VERSION
else
  # The /releases/latest redirect ends in the tag name; no API token needed.
  location=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") \
    || fail "could not resolve the latest release"
  version=${location##*/}
  version=${version#v}
  [ -n "$version" ] || fail "could not parse a version from '$location'"
fi

archive="ctm_${version}_${os}_${arch}.tar.gz"
base_url="https://github.com/$REPO/releases/download/v${version}"

# --- download and verify ----------------------------------------------------
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

say "Downloading ctm v${version} (${os}/${arch})..."
curl -fsSL -o "$workdir/$archive" "$base_url/$archive" \
  || fail "download failed: $base_url/$archive"
curl -fsSL -o "$workdir/checksums.txt" "$base_url/checksums.txt" \
  || fail "download failed: $base_url/checksums.txt"

# Verify only our archive's entry so a plain `-c` works everywhere —
# BusyBox sha256sum (Alpine) lacks GNU's --ignore-missing.
grep "  ${archive}\$" "$workdir/checksums.txt" > "$workdir/archive.sum" \
  || fail "checksums.txt has no entry for $archive"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$workdir" && sha256sum -c archive.sum >/dev/null) \
    || fail "checksum verification failed for $archive"
elif command -v shasum >/dev/null 2>&1; then
  (cd "$workdir" && shasum -a 256 -c archive.sum >/dev/null) \
    || fail "checksum verification failed for $archive"
else
  fail "sha256sum or shasum is required to verify the download"
fi

tar -xzf "$workdir/$archive" -C "$workdir" ctm || fail "could not extract ctm from $archive"

# --- choose the install directory --------------------------------------------
# A fixed user-private default, deliberately: this installer never escalates
# privileges and never adopts whatever directory PATH happens to resolve, so
# there is no privileged staging to attack and no system state to corrupt.
install_dir=${CTM_INSTALL_DIR:-"$HOME/.local/bin"}
if [ ! -d "$install_dir" ]; then
  # Create every missing component under a restrictive umask, not just the
  # leaf: with a collaborative caller umask (0002), a bare mkdir -p would
  # leave a fresh ~/.local group-writable even if bin/ itself were fixed.
  (umask 022 && mkdir -p "$install_dir") || fail "could not create $install_dir"
fi
[ -w "$install_dir" ] || fail "$install_dir is not writable by $(id -un). Choose a writable CTM_INSTALL_DIR, or install system-wide with Homebrew: brew install calltracking/tap/ctm"

# Refuse a group- or world-writable install directory: another local user
# could swap the staged file for a symlink between its creation and the
# copy, or plant a binary that the old-version probe below would execute.
# (Ancestors of $HOME and deliberate shared setups are the caller's domain,
# as with peer installers — this checks the directory we write into.)
dir_mode=$(ls -ldn "$install_dir" | cut -c1-10)
case "$dir_mode" in
  ?????w????|????????w?)
    fail "$install_dir is writable by other users; refusing to install there. Set CTM_INSTALL_DIR to a private directory." ;;
esac

target="$install_dir/ctm"

# mv renames onto a file but moves *into* a directory, which would bury the
# staged binary under its temporary name and report success anyway.
if [ -d "$target" ] && [ ! -h "$target" ]; then
  fail "$target is a directory; remove it or set CTM_INSTALL_DIR elsewhere"
fi

# A managed ctm must not be replaced by a standalone binary, no matter how
# the directory was chosen: the Homebrew cask links the binary into brew's
# bin (a symlink), and version managers front commands with wrapper-script
# shims (regular files starting "#!"). The released ctm is a compiled
# binary, never a script, so either shape means some manager owns this
# entry — send the upgrade through it instead.
if [ -h "$target" ] || { [ -f "$target" ] && [ "$(head -c 2 "$target" 2>/dev/null)" = "#!" ]; }; then
  fail "$target is managed by a package or version manager; upgrade with that manager (e.g. \`brew upgrade ctm\`), or set CTM_INSTALL_DIR to install separately"
fi

if [ -f "$target" ]; then
  old_version=$("$target" version 2>/dev/null | head -n 1 || true)
  say "Upgrading ${old_version:-existing install} at $target"
fi

# --- install ------------------------------------------------------------------
# Stage inside the install directory, then rename over any existing binary.
# mktemp creates the staged file exclusively under an unpredictable name,
# the cross-filesystem copy happens into that staged name, and the final
# rename is atomic on one filesystem — an interrupted upgrade can never
# leave a truncated ctm behind.
staged=$(mktemp "$install_dir/.ctm.new.XXXXXX") || fail "could not stage in $install_dir"
cp "$workdir/ctm" "$staged" || { rm -f "$staged"; fail "could not write to $install_dir"; }
chmod 0755 "$staged"

# Prove the new binary runs BEFORE renaming it over an existing install, so
# a wrong-architecture or unsupported-OS artifact (or a noexec mount) never
# destroys a working ctm. Captured rather than piped: a `... | head`
# pipeline would report head's status and hide the failure.
installed_version=$("$staged" version 2>/dev/null) || {
  rm -f "$staged"
  fail "the downloaded binary failed to run (wrong architecture, unsupported OS, or a noexec mount?); any existing install was left untouched"
}

mv "$staged" "$target" || { rm -f "$staged"; fail "could not install to $install_dir"; }
say "Installed $(printf '%s\n' "$installed_version" | head -n 1) to $target"

case ":${PATH}:" in
  *":${install_dir}:"*) ;;
  *) say "Note: $install_dir is not on your PATH. Add it, e.g.:"
     say "  export PATH=\"$install_dir:\$PATH\"" ;;
esac

# Another ctm earlier in PATH (a Homebrew install, an old copy) would shadow
# this one; surface that rather than leaving a stale-version mystery.
resolved=$(command -v ctm 2>/dev/null || true)
if [ -n "$resolved" ] && [ "$resolved" != "$target" ]; then
  say "Note: \`ctm\` currently resolves to $resolved, which shadows this install."
fi

say "To uninstall later: rm $target"
