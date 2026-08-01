# Documentation website extensions

The extensions here fall into two groups, told apart by where they sit.

## Committed, under `mcanouil/`

`mcanouil/atelier`, `mcanouil/iconify`, `mcanouil/gitlink`, `mcanouil/code-window`, and `mcanouil/pastel` are dependencies of the website itself: the project type and theme, the footer glyphs, the repository widget, the code block decoration, and the shared palette.
They arrive with the scaffold, which carries its own copies, and are checked in like any other Quarto extension.
Beyond that they are managed for you: [Quarto Wizard](https://m.canouil.dev/quarto-wizard) installs them, and the Quarto Extensions Updates workflow keeps them current by scanning this directory.

> [!IMPORTANT]
> Do not add or update them by hand with the Quarto CLI.
>
> `quarto add` and `quarto update` rewrite the manifest and drop the `source` and `source-type` fields, which are the only record of where each extension came from and at which version. An extension without them is invisible to the updater, and stays at whatever version it was left on.
>
> `quarto add` also fails here outright: `../_quarto.yml` declares `project: type: atelier`, and it builds a project context before installing anything, so it reports `Unsupported project type atelier` whenever atelier is missing or is the extension being replaced.

## Generated, directly under `_extensions/`

`iconify/` is a copy of the extension this repository publishes, taken from `_extensions/` at the repository root.
It is ignored by Git and produced by `../_scripts/sync-extension.sh`, so the repository root stays the single source of truth.

Run the sync before previewing the site locally:

```bash
./docs/_scripts/sync-extension.sh
quarto render docs
```

The Pages workflow runs it before every render, so CI always builds the checked-out source.

A real copy is needed, rather than a symlink or a pre-render step.
Quarto builds its extension registry while reading `_quarto.yml`, before any pre-render script runs, and it does not follow symlinks.
A shortcode contributed by an extension that is only linked, or only copied in by `pre-render`, is reported as `Shortcode 'iconify' not found` and renders as nothing.
