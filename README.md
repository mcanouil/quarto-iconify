# Iconify Extension for Quarto

This extension provides support to free and open source icons provided by [Iconify](https://icon-sets.iconify.design/).  
Icons can be used only in HTML-based documents.

## Installing

```sh
quarto add mcanouil/quarto-iconify
```

This will install the extension under the `_extensions` subdirectory.  
If you're using version control, you will want to check in this directory.

## Using

To embed an icon, use the `{{< iconify >}}` shortcode[^1]. For example:

```default
{{< iconify exploding-head >}}
{{< iconify fluent-emoji exploding-head >}}
{{< iconify fluent-emoji:exploding-head >}}
{{< iconify exploding-head size=2xl >}}
{{< iconify exploding-head size=5x rotate=180deg >}}
{{< iconify exploding-head size=Huge >}}
{{< iconify fluent-emoji-high-contrast 1st-place-medal >}}
{{< iconify twemoji 1st-place-medal >}}
{{< iconify line-md loading-alt-loop >}}
{{< iconify fa6-brands apple width=50px height=10px rotate=90deg flip=vertical >}}
{{< iconify simple-icons:quarto >}}
```

This extension includes support for thousands of icons (including animated icons).
You can browse all of the available sets of icons here:

<https://icon-sets.iconify.design/>

[^1]: The default icon set is `fluent-emoji` (source: <https://github.com/microsoft/fluentui-emoji>).

### Iconify Attributes

Iconify API provides additional attributes: <https://docs.iconify.design/iconify-icon/>.  
Currently, this extension supports: `width`, `height`, `title`[^2], `label`[^2] (_i.e._, `aria-label`), `flip`, and `rotate`.

``` markdown
{{< iconify <set> <icon> <size=...> <width=...> <height=...> <flip=...> <rotate=...> <title=...> <label=...> >}}
{{< iconify <set:icon> <size=...> <width=...> <height=...> <flip=...> <rotate=...> <title=...> <label=...> >}}
```

[^2]: `title` and `label` takes the following default value: `Icon <icon> from <set> Iconify.design set.`.

### Sizing Icons

This extension provides relative, literal, and LaTeX-style sizing for icons.  
When the size is invalid, no size changes are made.

- CSS-style sizing: `{{< iconify exploding-head size=42px >}}`.

- Relative sizing: `{{< iconify exploding-head size=2xl >}}`.

  | Relative Sizing | Font Size | Equivalent in Pixels |
  |-----------------|-----------|----------------------|
  | 2xs             | 0.625em   | 10px                 |
  | xs              | 0.75em    | 12px                 |
  | sm              | 0.875em   | 14px                 |
  | lg              | 1.25em    | 20px                 |
  | xl              | 1.5em     | 24px                 |
  | 2xl             | 2em       | 32px                 |

- Literal sizing: `{{< iconify exploding-head size=5x >}}`.

  | Literal Sizing | Font Size |
  |----------------|-----------|
  | 1x             | 1em       |
  | 2x             | 2em       |
  | 3x             | 3em       |
  | 4x             | 4em       |
  | 5x             | 5em       |
  | 6x             | 6em       |
  | 7x             | 7em       |
  | 8x             | 8em       |
  | 9x             | 9em       |
  | 10x            | 10em      |

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

- `width` or `height` can be set to define icon's property while keeping aspect ratio.  
  _Note:_ `width` and `height` are not set if `size` was defined.

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).

This is the output of `example.qmd` for [HTML](https://m.canouil.dev/quarto-iconify/).

---

[Iconify](https://github.com/iconify/iconify) by Vjacheslav Trushkin under MIT License.
