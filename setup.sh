#!/usr/bin/env bash
set -euo pipefail

# cspell:words redir tlsv

# Cloud development environment for bubble_shooter.
# The Flutter toolchain is defined by merry-setup and pinned to an immutable revision:
# https://github.com/AndrewDongminYoo/merry-setup
# ImageMagick for the store-asset tests is the one project-specific step, at the end.
#
# To move to a newer merry-setup:
#   1. Confirm the new commit is an ancestor of merry-setup's default branch. GitHub serves
#      commits from across a repository's fork network, so a SHA that resolves under this
#      URL does not by itself prove it is upstream work.
#   2. Set MERRY_SETUP_REVISION to the full commit SHA and MERRY_SETUP_SHA256 to the
#      SHA-256 of bin/merry-setup at that commit. The two move together: a mismatched pair
#      aborts below rather than running code nothing vouched for.
# The options below describe this project and change only when its toolchain does.

readonly MERRY_SETUP_REVISION=2f17c0afc7a8b876255c03ec228691059bce5048
readonly MERRY_SETUP_SHA256=a319cb35c2f5dc7c32ad54ef78f5b151717406cc3bbb7debd244cb8e8ed7ff26
readonly MERRY_SETUP_URL="https://raw.githubusercontent.com/AndrewDongminYoo/merry-setup/${MERRY_SETUP_REVISION}/bin/merry-setup"
readonly MERRY_SETUP_BIN="${HOME}/.merry-setup/bin/merry-setup-${MERRY_SETUP_REVISION}"

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

sha256_of() {
	sha256sum -- "$1" | awk '{print $1}'
}

[[ ${MERRY_SETUP_REVISION} =~ ^[0-9a-f]{40}$ ]] || die "MERRY_SETUP_REVISION must be a full commit SHA."
[[ ${MERRY_SETUP_SHA256} =~ ^[0-9a-f]{64}$ ]] || die "MERRY_SETUP_SHA256 must be a lowercase SHA-256 digest."

# Both guards below hash, so these are needed on a cache hit as well. curl is not: it is
# checked inside the download branch, which is the only path that reaches the network.
for required_cmd in sha256sum awk; do
	command -v "${required_cmd}" >/dev/null 2>&1 ||
		die "'${required_cmd}' is required to verify merry-setup."
done

# Download to a file and publish it by rename, so a partial transfer never becomes the executable.
if [[ ! -x ${MERRY_SETUP_BIN} ]]; then
	command -v curl >/dev/null 2>&1 || die "curl is required to download merry-setup."
	mkdir -p -- "${MERRY_SETUP_BIN%/*}"
	staged="$(mktemp "${MERRY_SETUP_BIN}.XXXXXX")"
	if ! curl --fail --silent --show-error --location \
		--proto '=https' --proto-redir '=https' --tlsv1.2 \
		--retry 3 --retry-delay 2 \
		--output "${staged}" "${MERRY_SETUP_URL}"; then
		rm -f -- "${staged}"
		die "Failed to download merry-setup ${MERRY_SETUP_REVISION}."
	fi
	# Checked before the rename, so a body that is not the pinned one never lands at the
	# cache path. The revision SHA already binds the URL to one blob, but only GitHub's
	# serving layer enforces that binding; nothing on this machine does. A proxy
	# intercepting TLS with a CA the container trusts satisfies every other constraint
	# here and fails this one.
	staged_sha256="$(sha256_of "${staged}")"
	if [[ ${staged_sha256} != "${MERRY_SETUP_SHA256}" ]]; then
		rm -f -- "${staged}"
		die "SHA-256 mismatch for the merry-setup ${MERRY_SETUP_REVISION} download: expected ${MERRY_SETUP_SHA256}, got ${staged_sha256}."
	fi
	chmod 0755 "${staged}"
	mv -f -- "${staged}" "${MERRY_SETUP_BIN}"
fi

# Re-checked on every run rather than only after a download: the cache is a plain file under
# $HOME, and hashing 60 KB costs less than trusting whatever now sits at that path.
cached_sha256="$(sha256_of "${MERRY_SETUP_BIN}")"
[[ ${cached_sha256} == "${MERRY_SETUP_SHA256}" ]] ||
	die "SHA-256 mismatch for ${MERRY_SETUP_BIN}: expected ${MERRY_SETUP_SHA256}, got ${cached_sha256}. Delete it and re-run."

# Run as a child rather than exec'd, so the ImageMagick step below still happens, and so a
# failure there leaves a usable Flutter toolchain behind instead of none.
"${MERRY_SETUP_BIN}" setup \
	--sdk flutter \
	--bootstrap flutter \
	--persist-path bashrc \
	--dart-package melos \
	--dart-package flutterfire_cli \
	--dart-package bloc_tools \
	--dart-package very_good_cli \
	--precache linux,web

# The store-asset tests shell out to `magick`, so without it each of them fails the coverage
# gate with a ProcessException. This mirrors the `setup` input in .github/workflows/main.yaml:
# Ubuntu packages ImageMagick 6, which has no `magick` entry point, so the same shim maps
# it onto `convert` and `identify`. Once `magick` resolves, re-runs skip apt entirely.
as_root() {
	if [[ ${EUID} -eq 0 ]]; then
		"$@"
	elif command -v sudo >/dev/null 2>&1; then
		sudo "$@"
	else
		die "Installing ImageMagick for the store-asset tests needs root or sudo."
	fi
}

if ! command -v magick >/dev/null 2>&1; then
	if ! command -v convert >/dev/null 2>&1 || ! command -v identify >/dev/null 2>&1; then
		command -v apt-get >/dev/null 2>&1 ||
			die "apt-get is required to install ImageMagick for the store-asset tests."
		as_root apt-get update
		as_root env DEBIAN_FRONTEND=noninteractive apt-get install --yes imagemagick
	fi
	as_root tee /usr/local/bin/magick >/dev/null <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "identify" ]]; then
  shift
  exec identify "$@"
fi
exec convert "$@"
SH
	as_root chmod 0755 /usr/local/bin/magick
fi

# A `convert` or `identify` that is not ImageMagick's, or one without a PNG coder, would
# otherwise surface only as ProcessExceptions deep in the store-asset tests. Both halves of
# the shim are checked, then exercised the way the tests call them: generate a PNG, identify it.
magick_version="$(magick -version)" || magick_version=""
[[ ${magick_version%%$'\n'*} == *ImageMagick* ]] ||
	die "'magick -version' does not report ImageMagick: '${magick_version%%$'\n'*}'."
identify_version="$(magick identify -version)" || identify_version=""
[[ ${identify_version%%$'\n'*} == *ImageMagick* ]] ||
	die "'magick identify -version' does not report ImageMagick: '${identify_version%%$'\n'*}'."

magick_probe_dir="$(mktemp -d)"
trap 'rm -rf -- "${magick_probe_dir}"' EXIT
magick -size 2x3 'xc:#123456' -alpha off "PNG24:${magick_probe_dir}/probe.png" ||
	die "ImageMagick failed to generate a probe PNG."
magick_probe="$(magick identify -format '%m|%w|%h' "${magick_probe_dir}/probe.png")" ||
	die "ImageMagick failed to identify the probe PNG."
[[ ${magick_probe} == 'PNG|2|3' ]] ||
	die "ImageMagick identified the 2x3 probe PNG as '${magick_probe}', expected 'PNG|2|3'."

printf 'ImageMagick ready: %s\n' "${magick_version%%$'\n'*}"
