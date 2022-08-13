# Iconify Extension for Quarto

This extension provides support to free and open source icons provided by [Iconify](https://icon-sets.iconify.design/).
Icons can be used only in HTML-based documents.

## Installing

```sh
quarto install extension mcanouil/quarto-iconify
```

This will install the extension under the `_extensions` subdirectory.
If you're using version control, you will want to check in this directory.

## Using

To embed an icon, use the `{{< iconify >}}` shortcode[^1]. For example:

```default
{{< iconify exploding-head >}}
{{< iconify fluent-emoji-high-contrast 1st-place-medal >}}
{{< iconify twemoji 1st-place-medal >}}
{{< iconify line-md loading-alt-loop >}}
```

This extension includes support for thousands of icons (including animated icons).
You can browse all of the available sets of icons here:

<ttps://icon-sets.iconify.design/>

[^1]: The default icon set is `fluent-emoji` (source: <https://github.com/microsoft/fluentui-emoji>).

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).

This is the output of `example.qmd` for [HTML](https://m.canouil.fr/quarto-iconify/).
