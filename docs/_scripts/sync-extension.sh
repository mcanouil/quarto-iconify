#!/usr/bin/env bash
#
# Documentation Extension Sync
# Mirrors the repository's own extension into the documentation project.
#
# @license MIT License
# @copyright 2026 Mickaël Canouil
# @author Mickaël Canouil
#
# The website demonstrates the extension it documents, so the extension has to
# be resolvable from docs/. Quarto builds its extension registry while reading
# _quarto.yml, before any pre-render script runs and without following symlinks,
# so a staged or linked copy is not found: shortcodes report "not found" and the
# page renders empty. The copy therefore has to exist on disk before Quarto
# starts.
#
# The repository root stays the single source of truth, so the copy is ignored
# by Git rather than committed. Run this script before previewing locally; the
# Pages workflow runs it before every render.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$(dirname "${SCRIPT_DIR}")"
ROOT_DIR="$(dirname "${DOCS_DIR}")"
# Directly under _extensions/, not under an owner directory: the owner
# directories hold the website's own installed dependencies, so keeping this
# copy beside them makes generated and vendored easy to tell apart.
TARGET_DIR="${DOCS_DIR}/_extensions"

for extension_dir in "${ROOT_DIR}"/_extensions/*/; do
	[[ -f "${extension_dir}_extension.yml" ]] || continue
	extension_name="$(basename "${extension_dir}")"
	target="${TARGET_DIR}/${extension_name}"
	# Remove first: copying onto an existing directory nests the new copy inside
	# the old one.
	rm -rf "${target}"
	mkdir -p "${TARGET_DIR}"
	cp -R "${extension_dir%/}" "${target}"
	printf '[sync] _extensions/%s -> docs/_extensions/%s\n' \
		"${extension_name}" "${extension_name}"
done
