# Changelog

## Unreleased

### Bug Fixes

- fix: Recover an attribute written without quotes inside a metadata field. Quarto reads a shortcode in `title:`, `subtitle:`, or a navbar `text:` with a different parser from the one it uses for the body, and that parser demotes an unquoted `key=value` to a positional argument. `{{< iconify octicon:heart-fill-16 aria-hidden=true >}}` in a `title:` was therefore announced instead of skipped. The pair is now folded back into the attributes, so one shortcode means the same thing in a metadata field as in the body.

## 4.1.0 (2026-08-04)

### New Features

- feat: Add the `aria-hidden` attribute, marking an icon as decorative. `aria-hidden=true` omits `role`, `aria-label`, and `title` in HTML, and the `alt` text in Typst, so an icon placed beside visible text no longer doubles the accessible name of the surrounding link. It is a shortcode attribute only, with no document-level default.

### Documentation

- docs: Mark the documentation website's own footer icons decorative, so the two footer links are announced as "Quarto" and "Sponsor" rather than "Quarto Quarto" and "Heart Sponsor".

## 4.0.1 (2026-08-01)

### Bug Fixes

- fix: Honour `inline: false` written as a bare YAML boolean. The value was read as an absent option, so icons kept the `inline` attribute that the default applies.

### Documentation

- docs: Add a documentation website under `docs/`, built on the `atelier` project type and published to <https://m.canouil.dev/quarto-iconify/>, drawing its icons with the extension itself.
- docs: Trim `README.md` to a landing page pointing at the website.
- docs: Add the Pages workflow, which renders `docs/` on pull requests and deploys it from the release tag.
- docs: Add the Quarto Extensions Updates workflow, scanning `docs` for the website's own dependencies.

## 4.0.0 (2026-06-22)

### New Features

- feat: Render icons in Typst output. The SVG for each icon is retrieved from the Iconify API at render time, cached on disk, and emitted as a Typst `#image(...)`. `flip`, `rotate`, and `color` are applied by the API; `size` becomes the image height; `label`/`title` become `alt` text; `fallback` text is shown when an icon cannot be retrieved.
- feat: Cache retrieved SVGs under `.quarto/iconify-svg/` (configurable via `extensions.iconify.typst-cache`). A populated cache renders fully offline. The cache is pruned automatically and is concurrency-safe via `extensions.iconify.typst-cache-max-age` (default 30 days) and `extensions.iconify.typst-cache-max-entries` (default unlimited).

### Documentation

- docs: Document Typst output, the on-disk cache, and the cache-bounding options.

## 3.3.0 (2026-05-31)

### New Features

- feat: Add `fallback` attribute (text or emoji) shown when an icon fails to load (unknown name, offline, or CDN unreachable).
- feat: Add `extensions.iconify.preload` metadata to inject local Iconify icon-collection JSON files as `window.IconifyPreload`, enabling offline rendering of preloaded icons. Requires the iconify filter to be active.

### Bug Fixes

- fix: Deprecation warning for the top-level `iconify:` configuration now fires at least once per attribute name instead of only once per render.
- fix: Validate icon and set names against the Iconify name pattern (`^[a-z0-9]+(-[a-z0-9]+)*$`) and emit a warning when a name is invalid.
- fix: Validate `size` values; unknown keywords and malformed CSS lengths are now dropped with a warning, honouring the README contract that "no size changes are made" when invalid.

### Documentation

- docs: Document the `fallback` attribute, the offline/preload workflow, and the new input-validation behaviour.

### Refactoring

- refactor: Synchronise shared modules (`string.lua`, `logging.lua`, `metadata.lua`) with the canonical versions.

## 3.2.1 (2026-04-15)

### Refactoring

- refactor: Synchronise shared module (`logging.lua`) with canonical version.

## 3.2.0 (2026-03-23)

### Refactoring

- refactor: Replace monolithic `utils.lua` with focused modules (`string.lua`, `logging.lua`, `metadata.lua`, `pandoc-helpers.lua`, `html.lua`, `paths.lua`, `colour.lua`).

## 3.1.0 (2026-02-21)

### New Features

- feat: Add extension-provided code snippets (#53).
- feat: Add _schema.yml for configuration validation and IDE support (#49).

### Documentation

- docs: Add missing icon set prefix.
- docs: Add missing prefix for icon set.

## 3.0.3 (2026-02-11)

### Bug Fixes

- fix: Update copyright year.
- fix: Use british english spelling.

## 3.0.2 (2025-10-25)

### New Features

- feat: Update metadata in example.qmd.

### Refactoring

- refactor: Use module and enhance iconify extension (#46).

## 3.0.1 (2025-07-14)

### New Features

- feat: Add Quarto shortcode for icon rendering (#43).

### Refactoring

- refactor: Extension configuration structure under `extensions` (#44).

### Documentation

- docs: Add type hint.

## 3.0.0 (2025-05-20)

### New Features

- feat: Iconify 3.0.0, YAML defaults, and new "style" attribute (#39).

### Bug Fixes

- fix: Stringify "set" from meta.

## 2.3.1 (2025-04-05)

### New Features

- feat: Add CITATION file for project citation.

### Bug Fixes

- fix: Use output-file option.

## 2.3.0 (2025-03-22)

## 2.1.2 (2024-08-11)

### Bug Fixes

- fix: Allow to set/unset `inline` attribute (#32).

## 2.1.1 (2024-07-17)

### Bug Fixes

- fix: Add `role` attribute to `<iconify-icon>` tag for accessibility (#29).

### Documentation

- docs: Add Quarto Iconify Example for simple-icons:quarto (#25).

## 2.1.0 (2024-05-01)

### Bug Fixes

- fix: Use proper warning message for `set:icon` or `set icon` (#22).
- fix: Allow name copied from iconify website to be used (#20).

## 2.0.0 (2024-03-10)

### Bug Fixes

- fix: Title/label args (#17).

## 1.0.8 (2023-12-21)

## 1.0.7 (2023-08-27)

### Documentation

- docs: Update quarto command.
- docs: Add explicitly source, author, and license.

## 1.0.0 (2022-12-27)

### Bug Fixes

- fix: Update/Release for Quarto v1.2 (#6).

## 0.3.0 (2022-08-14)

### New Features

- feat: Brings accessibility support along with new options.

### Bug Fixes

- fix: Rm fa prefix class.

### Documentation

- docs: Tweak readme.

## 0.2.0 (2022-08-13)

### Bug Fixes

- fix: Add latex sizing example.
- fix: Add size option to shortcode.

### Style

- style: Breakline.

## 0.1.0 (2022-08-13)

### Bug Fixes

- fix: Typo.
- fix: Rm unsupported pdf format.
