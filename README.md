# Iconify Extension for Quarto

This extension provides support to free and open source icons provided by [Iconify](https://icon-sets.iconify.design/).

Icons are rendered in HTML-based documents (via the Iconify web component) and in Typst output (via cached SVGs retrieved from the Iconify API).
See [Typst output](#typst-output) for details.
Other formats (LaTeX, `docx`, …) render nothing.

## Installation

```sh
quarto add mcanouil/quarto-iconify@3.3.0
```

This will install the extension under the `_extensions` subdirectory.

If you're using version control, you will want to check in this directory.

## Usage

To embed an icon, use the `{{< iconify >}}` shortcode.

For convenience, a special `{{< quarto >}}` shortcode is also available to quickly insert the Quarto logo with preset styling.

For example:

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
{{< quarto >}}
```

This extension includes support for thousands of icons (including animated icons).
You can browse all of the available sets of icons here:

<https://icon-sets.iconify.design/>

### Iconify Attributes

Iconify API provides additional attributes: <https://docs.iconify.design/iconify-icon/>.

Currently, this extension supports the following attributes:

```markdown
{{< iconify <set=...> <icon> <size=...> <width=...> <height=...> <flip=...> <rotate=...> <title=...> <label=...> <inline=...> <mode=...> <style=...> >}}
{{< iconify <set:icon> <size=...> <width=...> <height=...> <flip=...> <rotate=...> <title=...> <label=...> <inline=...> <mode=...> <style=...> >}}
```

#### Available Attributes

- `set`: The icon set to use. Default is `octicon` (source: <https://github.com/microsoft/fluentui-emoji>).

- `size`: Sets both width and height. When `size` is defined, `width` and `height` are ignored. See [Sizing Icons](#sizing-icons) for available size options.

- `width` and `height`: Set icon dimensions whilst keeping aspect ratio. Not used if `size` is defined.

- `flip`: Flip the icon horizontally, vertically, or both.

- `rotate`: Rotate the icon by a specified angle (e.g., `90deg`, `180deg`).

- `title`: Tooltip text for the icon. Default: `Icon <icon> from <set> Iconify.design set.`.

- `label` (i.e., `aria-label`): Accessibility label for screen readers. Default: `Icon <icon> from <set> Iconify.design set.`.

- `inline`: Boolean attribute (`true` or `false`). When `true`, the icon is displayed inline with text. Default is `true`.

- `mode`: Rendering mode. Can be `"svg"` (default), `"style"`, `"bg"`, or `"mask"`. See [Iconify renderings mode](https://iconify.design/docs/iconify-icon/modes.html) for more details.

- `style`: CSS style string to apply custom styling to the icon.

- `fallback`: Text or emoji shown when the icon cannot be loaded (unknown name, offline, or CDN unreachable). See [Fallback](#fallback) for details.

#### Setting Default Values

You can define default values for most attributes in the YAML header using the nested structure under `extensions.iconify`:

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

**Note:** The attributes `icon`, `title`, and `label` must be defined in the shortcode itself and cannot have default values in the YAML header.

**Deprecation warning:** The top-level `iconify:` configuration is deprecated but still supported for backward compatibility. A warning is emitted at least once per attribute name when the deprecated format is used. Please migrate to the new nested structure shown above.

### Input Validation

Since version 3.3.0, the extension validates a few common authoring mistakes and warns at render time:

- Invalid icon or set names (anything outside lowercase letters, digits, and single hyphens) produce a warning. The icon is still emitted so the malformed name is visible in the output.
- Invalid `size` values (not a known keyword, not a CSS length) produce a warning and the size is dropped, matching the README contract that "When the size is invalid, no size changes are made.".

### Fallback

The `fallback` attribute lets you declare text or an emoji that is shown when the icon fails to load.
Loading can fail for three reasons:

- The icon set or icon name does not exist.
- The browser is offline.
- The Iconify CDN is unreachable from the reader's network.

The wrapper renders the `<iconify-icon>` web component plus a hidden fallback span; a small companion script monitors the icon and reveals the fallback once the component reports a failure.

```markdown
{{< iconify fluent-emoji exploding-head fallback="🤯" >}}
```

You can also set a document-wide default fallback under `extensions.iconify.fallback`.

### Offline / Preloaded Icons

For documents that must render offline (or simply do not want to rely on the Iconify CDN for known icons), you can preload one or more Iconify icon-collection JSON files.
This requires the iconify filter to be enabled.

```yaml
filters:
  - iconify
extensions:
  iconify:
    preload:
      - icons/octicon.json
      - icons/fluent-emoji.json
```

Each file must contain a valid Iconify icon collection (an object beginning with `{`).
The extension injects them as `window.IconifyPreload`, which the Iconify Web Component consumes at boot instead of calling the CDN.

You can download icon collections from <https://github.com/iconify/icon-sets> or from the Iconify API (`https://api.iconify.design/<prefix>.json?icons=<comma-separated-names>`).

### Typst Output

For Typst output (including PDF produced with the Typst engine), the extension retrieves each icon's SVG from the Iconify API at render time, caches it on disk, and emits a Typst `#image(...)` referencing the cached file.
The same shortcodes work without changes:

```markdown
{{< iconify octicon heart-fill-16 >}}
{{< iconify mdi home size=2em >}}
{{< iconify fa6-brands apple color=red flip=vertical rotate=90deg >}}
{{< quarto >}}
```

How the options map to Typst:

- `size` is applied as the Typst image height so the icon scales with the surrounding text. Use a Typst-compatible unit (`em`, `pt`, `cm`, `mm`, `in`, `%`); `px` and other CSS-only units fall back to `1em` with a warning.
- `flip`, `rotate`, and `color` are baked into the fetched SVG by the Iconify API. Monochrome icons use `currentColor`, which renders black in Typst unless you set `color`; multi-colour icons (e.g. emoji) are unaffected.
- `label` (or `title`) becomes the image `alt` text.
- `inline` keeps the icon in the text flow (default); `inline=false` emits a standalone image.
- `mode` and `style` are HTML-only and ignored for Typst (a `color:` declaration inside `style` is still honoured).
- `fallback` text is rendered in place of the icon when it cannot be retrieved (unknown name, or offline with an empty cache).

#### Caching

Retrieved SVGs are cached under `.quarto/iconify-svg/` in the project root (Quarto's cache location, which is gitignored).
Once cached, an icon is reused on later renders without any network access, so a populated cache renders fully offline.
Point the cache elsewhere to commit a reproducible, offline cache:

```yaml
extensions:
  iconify:
    typst-cache: assets/iconify-svg
```

The cache is pruned automatically so it does not grow without bound:

- `typst-cache-max-age` (default `30`): entries unused for this many days are removed. Set to `0` to disable age-based pruning.
- `typst-cache-max-entries` (default `0`, unlimited): caps the number of cached icons, removing the least-recently-used beyond the cap. Recently-used icons are never removed, so a single document needing more icons than the cap still renders.

Pruning is concurrency-safe: independent `quarto render` processes sharing one cache will not remove icons another render is currently using.

### Sizing Icons

This extension provides relative, literal, and LaTeX-style sizing for icons.

When the size is invalid, no size changes are made.

- CSS-style sizing: `{{< iconify fluent-emoji:exploding-head size=42px >}}`.

- Relative sizing: `{{< iconify fluent-emoji:exploding-head size=2xl >}}`.

  | Relative Sizing | Font Size | Equivalent in Pixels |
  |-----------------|-----------|----------------------|
  | 2xs             | 0.625em   | 10px                 |
  | xs              | 0.75em    | 12px                 |
  | sm              | 0.875em   | 14px                 |
  | lg              | 1.25em    | 20px                 |
  | xl              | 1.5em     | 24px                 |
  | 2xl             | 2em       | 32px                 |

- Literal sizing: `{{< iconify fluent-emoji:exploding-head size=5x >}}`.

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

- LaTeX-style sizing: `{{< iconify fluent-emoji:exploding-head size=Huge >}}`.

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

- `width` or `height` can be set to define icon's property whilst keeping aspect ratio. _Note:_ `width` and `height` are not set if `size` was defined.

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).

Output of `example.qmd`:

- [HTML](https://m.canouil.dev/quarto-iconify/)

---

[Iconify](https://github.com/iconify/iconify) by Vjacheslav Trushkin under MIT License.
