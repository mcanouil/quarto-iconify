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
{{< iconify exploding-head size=2xl >}}
{{< iconify exploding-head size=10x >}}
{{< iconify fluent-emoji-high-contrast 1st-place-medal >}}
{{< iconify twemoji 1st-place-medal >}}
{{< iconify line-md loading-alt-loop >}}
{{< iconify exploding-head size=2xl>}}
{{< iconify fluent-emoji-flat exploding-head size=10x>}}
```

This extension includes support for thousands of icons (including animated icons).
You can browse all of the available sets of icons here:

<https://icon-sets.iconify.design/>

[^1]: The default icon set is `fluent-emoji` (source: <https://github.com/microsoft/fluentui-emoji>).

### Sizing Icons

This extension provides relative, literal, and LaTeX-style sizing for icons.  
When the size is invalid, no size changes are made.

- Relative sizing: `{{< iconify exploding-head size=2xl >}}`.

  | Relative Sizing Class | Font Size | Equivalent in Pixels |
  |-----------------------|-----------|----------------------|
  | fa-2xs                | 0.625em   | 10px                 |
  | fa-xs                 | 0.75em    | 12px                 |
  | fa-sm                 | 0.875em   | 14px                 |
  | fa-lg                 | 1.25em    | 20px                 |
  | fa-xl                 | 1.5em     | 24px                 |
  | fa-2xl                | 2em       | 32px                 |

- Literal sizing: `{{< iconify exploding-head size=5x >}}`.

  | Literal Sizing Class | Font Size |
  |----------------------|-----------|
  | fa-1x                | 1em       |
  | fa-2x                | 2em       |
  | fa-3x                | 3em       |
  | fa-4x                | 4em       |
  | fa-5x                | 5em       |
  | fa-6x                | 6em       |
  | fa-7x                | 7em       |
  | fa-8x                | 8em       |
  | fa-9x                | 9em       |
  | fa-10x               | 10em      |

- LaTeX-style sizing: `{{< iconify exploding-head size=Huge >}}`.

  | Sizing Command                   | Font Size (HTML) |
  | -------------------------------- | ---------------- |
  | tiny (= `\tiny`)                 | 0.5em            |
  | scriptsize (= `\scriptsize`)     | 0.7em            |
  | footnotesize (= `\footnotesize`) | 0.8em            |
  | small (= `\small`)               | 0.9em            |
  | normalsize (= `\normalsize`)     | 1em              |
  | large (= `\large`)               | 1.25em           |
  | Large (= `\Large`)               | 1.5em            |
  | LARGE (= `\LARGE`)               | 1.75em           |
  | huge (= `\huge`)                 | 2em              |
  | Huge (= `\Huge`)                 | 2.5em            |

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).

This is the output of `example.qmd` for [HTML](https://m.canouil.fr/quarto-iconify/).
