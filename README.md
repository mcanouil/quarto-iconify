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

To embed an icon, use the `{{< iconify >}}` shortcode. For example:

```markdown
{{< iconify copilot-24 >}}
{{< iconify fluent-emoji exploding-head >}}
{{< iconify fluent-emoji:exploding-head >}}
{{< iconify copilot-24 size=2xl >}}
{{< iconify copilot-24 size=5x rotate=180deg >}}
{{< iconify copilot-24 size=Huge >}}
{{< iconify fluent-emoji-high-contrast 1st-place-medal >}}
{{< iconify twemoji 1st-place-medal >}}
{{< iconify line-md loading-alt-loop >}}
{{< iconify fa6-brands apple width=50px height=10px rotate=90deg flip=vertical >}}
{{< iconify simple-icons:quarto style="color:#74aadb;" >}}
```

This extension includes support for thousands of icons (including animated icons).
You can browse all of the available sets of icons here:

<https://icon-sets.iconify.design/>

### Iconify Attributes

Iconify API provides additional attributes: <https://docs.iconify.design/iconify-icon/>.  
Currently, this extension supports: `<set>`[^1], `size`[^2], `width`[^2], `height`[^2], `flip`, `rotate`, `title`[^3], `label`[^3] (_i.e._, `aria-label`), `inline`[^4], `mode`[^5], and `style`[^6].

```markdown
{{< iconify <set=...> <icon> <size=...> <width=...> <height=...> <flip=...> <rotate=...> <title=...> <label=...> <inline=...> <mode=...> <style=...> >}}
{{< iconify <set:icon> <size=...> <width=...> <height=...> <flip=...> <rotate=...> <title=...> <label=...> <inline=...> <mode=...> <style=...> >}}
```

Defining default values for attributes[^7]:

```yaml
extensions:
  iconify:
    set: "octicon"
    size: "Huge"
    width: "1em"
    height: "1em"
    flip: "horizontal"
    rotate: "90deg"
    inline: true
    mode: "svg"
    style: "color: #b22222;"
```

**Note:** The top-level `iconify:` configuration is deprecated but still supported for backward compatibility. A warning will be displayed when using the deprecated format. Please migrate to the new nested structure shown above.

[^1]: The default icon set is `octicon` (source: <https://github.com/microsoft/fluentui-emoji>).
[^2]: If `<size=...>` is defined, `<width=...>` and `<height=...>` are not used.
[^3]: `title` and `label` takes the following default value: `Icon <icon> from <set> Iconify.design set.`.
[^4]: `inline` is a boolean attribute that can be set to `true` or `false`. Default is `true`.
[^5]: `mode` is a string attribute that can be set to `"svg"`, `"style"`, `"bg"`, and `"mask"`. Default is `"svg"`. See [Iconify renderings mode](https://iconify.design/docs/iconify-icon/modes.html) for more details.
[^6]: `style` is a string attribute expected to be a CSS style.
[^7]: The default values can be defined in the YAML header of the document using the new nested structure under `extensions.iconify`. The old top-level `iconify` configuration is deprecated but still supported.
  `icon`, `title`, and `label` have to be defined in the shortcode.

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
