--- @module "iconify"
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil

--- Extension name constant
local EXTENSION_NAME = "iconify"

--- Load modules
local str = require(quarto.utils.resolve_path('_vendor/quarto-lua-modules/string.lua'):gsub('%.lua$', ''))
local log = require(quarto.utils.resolve_path('_vendor/quarto-lua-modules/logging.lua'):gsub('%.lua$', ''))
local meta_mod = require(quarto.utils.resolve_path('_vendor/quarto-lua-modules/metadata.lua'):gsub('%.lua$', ''))
local typst = require(quarto.utils.resolve_path('_modules/typst.lua'):gsub('%.lua$', ''))
local schema = require(quarto.utils.resolve_path('_vendor/quarto-wizard/schema.lua'):gsub('%.lua$', ''))

--- The parsed `_schema.yml`, loaded once and reused by every shortcode call.
--- Nil means the file could not be read, in which case calls are not checked
--- and the render carries on: a configuration file must not stop a document.
--- @type table|nil
local extension_schema = nil

--- Whether loading has already been attempted this render.
--- @type boolean
local schema_loaded = false

--- Last resort for the two values the extension cannot render without, used
--- only when `_schema.yml` could not be read. `_schema.yml` stays the source
--- of truth on every normal path; without these an unreadable configuration
--- file would turn every icon into `icon=":name"` and stop Typst caching.
--- @type table<string, string>
local SCHEMA_UNAVAILABLE = {
  set = 'octicon',
  ['typst-cache'] = '.quarto/iconify-svg',
}

--- Whether the document configuration has already been checked this render.
--- The check lives here rather than in the companion filter because that
--- filter is opt-in (`filters: [iconify]`), while a shortcode always runs
--- when there is an icon to render.
--- @type boolean
local options_validated = false

--- The document configuration resolved against `_schema.yml`, holding the
--- `provided`, `merged` and `defaults` tables. Nil until the first shortcode
--- runs, and left nil when there is no readable schema.
--- @type table|nil
local resolved_options = nil

--- Per-key deprecation warning tracker. Each deprecated metadata key warns
--- at least once per render rather than once total. The companion filter
--- (`iconify-filter.lua`) is responsible for any per-document state reset
--- in batch renders; this shortcode keeps the tracker local to its own
--- module instance.
--- @type table<string, boolean>
local deprecation_warned_keys = {}

--- Ensures the Typst SVG cache is pruned at most once per render. The cleanup
--- runs from the shortcode (not the filter) because contributed filters run
--- before shortcodes expand, so the cache does not yet exist at filter time.
--- @type boolean
local typst_cleanup_done = false

--- Ensure Iconify HTML dependencies are included.
--- @return nil
local function ensure_html_deps()
  quarto.doc.add_html_dependency({
    name = 'iconify',
    version = '3.0.0',
    scripts = { 'iconify-icon.min.js' }
  })
end

--- Ensure the fallback runtime stylesheet and script are loaded.
--- The runtime monitors each `<iconify-icon>` and reveals an author-provided
--- fallback span if the icon fails to load (e.g. unknown icon name, offline,
--- or CDN unreachable).
--- @return nil
local function ensure_fallback_runtime()
  quarto.doc.add_html_dependency({
    name = 'iconify-fallback',
    version = '1.0.0',
    scripts = { 'iconify-fallback.js' },
    stylesheets = { 'iconify-fallback.css' }
  })
end

--- Check for deprecated top-level iconify configuration and emit a warning
--- the first time each key is accessed during a render.
--- @param meta table<string, any> Document metadata table
--- @param key string The configuration key being accessed
--- @return string|nil The value from deprecated config, or nil if not found
local function check_deprecated_config(meta, key)
  --- @type boolean
  local already_warned = deprecation_warned_keys[key] or false
  local value, updated = meta_mod.check_deprecated_config(meta, 'iconify', key, already_warned)
  deprecation_warned_keys[key] = updated
  return value
end

--- @type table<string, string> Known size keywords mapped to CSS font-size values
local SIZE_KEYWORDS = {
  ['tiny']         = '0.5em',
  ['scriptsize']   = '0.7em',
  ['footnotesize'] = '0.8em',
  ['small']        = '0.9em',
  ['normalsize']   = '1em',
  ['large']        = '1.2em',
  ['Large']        = '1.5em',
  ['LARGE']        = '1.75em',
  ['huge']         = '2em',
  ['Huge']         = '2.5em',
  ['1x']           = '1em',
  ['2x']           = '2em',
  ['3x']           = '3em',
  ['4x']           = '4em',
  ['5x']           = '5em',
  ['6x']           = '6em',
  ['7x']           = '7em',
  ['8x']           = '8em',
  ['9x']           = '9em',
  ['10x']          = '10em',
  ['2xs']          = '0.625em',
  ['xs']           = '0.75em',
  ['sm']           = '0.875em',
  ['lg']           = '1.25em',
  ['xl']           = '1.5em',
  ['2xl']          = '2em'
}

--- Allowed CSS length units. `%` is included for completeness even though it
--- is rarely meaningful for font-size.
--- @type table<string, boolean>
local CSS_LENGTH_UNITS = {
  px = true, em = true, rem = true, pt = true, pc = true, ex = true,
  ch = true, cm = true, mm = true, ['in'] = true, vh = true, vw = true,
  vmin = true, vmax = true, ['%'] = true
}

--- Check whether a size value is a syntactically valid CSS length.
--- Accepts an optional leading sign, a number (integer or decimal), and a
--- supported unit. Returns false for unknown units or malformed values.
--- @param value string
--- @return boolean
local function is_css_length(value)
  --- @type string|nil, string|nil
  local number_part, unit = value:match('^([-+]?%d*%.?%d+)(.*)$')
  if not number_part or number_part == '' or number_part == '.' then
    return false
  end
  if unit == nil or unit == '' then
    -- Bare numbers are not valid CSS lengths (except zero).
    return value == '0'
  end
  return CSS_LENGTH_UNITS[unit] == true
end

--- Resolve a size value to a raw CSS length, mapping known keywords.
--- Returns an empty string when the value is empty or invalid, after emitting
--- a warning for the invalid case. This honours the README contract that
--- "When the size is invalid, no size changes are made."
--- @param size string|nil
--- @return string
local function resolve_size_value(size)
  if str.is_empty(size) then
    return ''
  end
  --- @cast size string
  --- @type string|nil
  local mapped = SIZE_KEYWORDS[size]
  if mapped ~= nil then
    return mapped
  end
  if is_css_length(size) then
    return size
  end
  log.log_warning(
    EXTENSION_NAME,
    'Ignoring invalid size value "' .. size .. '". ' ..
    'Use a CSS length (e.g. "1.5em", "32px"), a literal size like "2x", ' ..
    'or a LaTeX-style keyword like "Huge". Size left unchanged.'
  )
  return ''
end

--- Validate and convert a size value to a CSS font-size declaration.
--- @param size string|nil
--- @return string
local function resolve_size(size)
  --- @type string
  local value = resolve_size_value(size)
  if value == '' then
    return ''
  end
  return 'font-size: ' .. value .. ';'
end

--- Validate an Iconify icon or set name.
--- Matches the pattern enforced by the Iconify Web Component itself
--- (`/^[a-z0-9]+(-[a-z0-9]+)*$/`): lowercase letters or digits separated
--- by single hyphens, with no leading or trailing hyphen.
--- @param value string
--- @return boolean
local function is_valid_iconify_name(value)
  if value == nil or value == '' then return false end
  if value:find('%-%-') then return false end
  if value:sub(1, 1) == '-' or value:sub(-1) == '-' then return false end
  return value:match('^[a-z0-9-]+$') ~= nil
end

--- Read an attribute value with a surrounding quote pair removed.
--- Quarto's body parser strips those quotes before the value reaches the
--- shortcode, but the parser it uses for a text or attribute string (a
--- `page-footer:` entry, for instance) hands the raw token over instead, so
--- `aria-hidden='true'` arrives as the five-character string `'true'`.
--- Stripping here is what makes a quoted and an unquoted value mean the same
--- thing in every context; drop it once Quarto's parsers agree.
--- @param kwargs table<string, any> Key-value options for the icon
--- @param key string The attribute name to read
--- @return string
local function attr_value(kwargs, key)
  --- @type string
  local value = str.stringify(kwargs[key])
  --- @type string
  local quote = value:sub(1, 1)
  if #value > 1 and (quote == '"' or quote == "'") and value:sub(-1) == quote then
    return value:sub(2, -2)
  end
  return value
end

--- Build a single HTML attribute, escaping the value.
--- Every value reaching this point is author-supplied and lands inside a
--- double-quoted attribute, so an unescaped `"` would close the attribute
--- early and let the rest of the value be read as markup. Going through one
--- function rather than concatenating at each site is what keeps that from
--- being forgotten as attributes are added.
--- @param name string Attribute name
--- @param value string Attribute value
--- @return string The attribute, with a leading space
local function html_attribute(name, value)
  return ' ' .. name .. '="' .. str.escape_attribute(value) .. '"'
end

--- Resolve the `aria-hidden` attribute, which marks an icon as decorative.
--- A decorative icon carries no `role`, `aria-label` or `title`, so assistive
--- technology skips it entirely. Read from the shortcode arguments alone:
--- whether an icon is decorative depends on whether visible text sits beside
--- that icon, which no document-level default can know.
--- Accepts only 'true' and 'false'; anything else is ignored, and warns when
--- `warn` is set, so a typo cannot silently strip an icon's accessible name.
--- The `quarto` shortcode resolves the value without warning, since the icon
--- it builds passes through this function again on the way out.
--- @param kwargs table<string, any> Key-value options for the icon
--- @param warn boolean Whether to warn about an unrecognised value
--- @return boolean
local function is_decorative(kwargs, warn)
  --- @type string
  local value = attr_value(kwargs, 'aria-hidden')
  if str.is_empty(value) or value == 'false' then
    return false
  end
  if value == 'true' then
    return true
  end
  if warn then
    log.log_warning(
      EXTENSION_NAME,
      'Ignoring invalid aria-hidden value "' .. value .. '". ' ..
      'Use aria-hidden="true" to mark an icon as decorative, or "false". ' ..
      'The icon keeps its accessible name.'
    )
  end
  return false
end

--- Fold `key=value` positional arguments back into `kwargs`.
--- Quarto parses body shortcodes with `lpegshortcode.lua`, which reads an
--- unquoted `key=value`, but a shortcode in a metadata field (`title:`,
--- `subtitle:`, a navbar `text:`) goes through `astshortcode.lua`, which reads
--- a key only when the value is quoted and otherwise hands the whole token
--- over as a positional argument. Recovering the pair here is what makes one
--- shortcode mean the same thing in a metadata field as in the body; drop this
--- once Quarto's metadata parser matches its body parser.
--- An explicitly parsed entry always wins, and an icon or set name cannot
--- contain `=`, so the icon arguments are never captured.
--- Pandoc splits on whitespace before the extension sees the shortcode, so an
--- unquoted value carrying a space (`label=Hello world`) recovers its first
--- token alone. Quoting the value remains the documented form.
--- @param args table<integer, any> Icon arguments (icon set and name)
--- @param kwargs table<string, any> Key-value options for the icon
--- @return table<integer, any> Icon arguments with the recovered pairs removed
local function recover_kwargs(args, kwargs)
  --- @type table<integer, any>
  local positional = {}
  for _, arg in ipairs(args) do
    --- @type string, string
    local key, value = string.match(str.stringify(arg), '^([%a][%w%-]*)=(.*)$')
    if key == nil then
      table.insert(positional, arg)
    elseif str.is_empty(str.stringify(kwargs[key])) then
      kwargs[key] = value
    end
  end
  return positional
end

--- Load `_schema.yml` once per render.
--- @return table|nil The parsed schema, or nil when it could not be read
local function load_extension_schema()
  if not schema_loaded then
    schema_loaded = true
    local loaded, err = schema.load_schema(quarto.utils.resolve_path('_schema.yml'))
    if err then
      log.log_error(EXTENSION_NAME, err)
    else
      extension_schema = loaded
    end
  end
  return extension_schema
end

--- Flatten a shortcode's named options to plain strings for validation.
--- Every value is read through `attr_value`, so a quoted and an unquoted
--- value are checked as the same thing.
--- @param kwargs table<string, any> Key-value options for the icon
--- @return table<string, string>
local function plain_kwargs(kwargs)
  --- @type table<string, string>
  local plain = {}
  for key in pairs(kwargs) do
    plain[tostring(key)] = attr_value(kwargs, key)
  end
  return plain
end

--- Check `extensions.iconify` against `_schema.yml` once per render, and keep
--- what it resolves. `_schema.yml` holds every default this extension applies,
--- so the values it produces are read back here rather than restated in Lua.
---
--- Three tables are kept, because they answer different questions:
---   provided  what the document actually set, which is the only way to tell
---             a deliberate `false` or `0` from an absent key,
---   merged    the same values with coercion and defaults applied,
---   defaults  the schema defaults on their own, from a pass over an empty
---             table, used as the last resort in `document_option`.
--- @param meta table<string, any> Document metadata
--- @return table|nil The resolved tables, or nil when there is no schema
local function resolve_document_options(meta)
  if resolved_options ~= nil then
    return resolved_options
  end
  if options_validated then
    return nil
  end
  options_validated = true

  --- @type table|nil
  local loaded = load_extension_schema()
  if loaded == nil or next(loaded.options) == nil then return nil end

  --- @type table<string, any>
  local provided = schema.extract_meta_options(meta, EXTENSION_NAME)
  local valid, errors, warnings, merged = schema.validate(provided, loaded.options)

  for _, message in ipairs(warnings) do
    log.log_warning(EXTENSION_NAME, message)
  end
  if not valid then
    for _, message in ipairs(errors) do
      log.log_error(EXTENSION_NAME, message)
    end
  end

  --- Validating an empty configuration yields the declared defaults alone.
  local _, _, _, defaults = schema.validate({}, loaded.options, { unknown = 'ignore' })

  resolved_options = { provided = provided, merged = merged, defaults = defaults }
  return resolved_options
end

--- Check one shortcode call against its entry in `_schema.yml` and report
--- whatever it finds. This reports only; nothing about the rendered icon
--- changes, so an unrecognised attribute is surfaced rather than dropped.
--- @param name string Shortcode name, 'iconify' or 'quarto'
--- @param args table<integer, any> Positional arguments
--- @param kwargs table<string, any> Key-value options for the icon
--- @return nil
local function validate_call(name, args, kwargs)
  --- @type table|nil
  local loaded = load_extension_schema()
  if loaded == nil then return end

  --- @type table|nil
  local entry = loaded.shortcodes and loaded.shortcodes[name]
  if entry == nil then return end

  --- @type table<integer, string>
  local positional = {}
  for index, value in ipairs(args) do
    positional[index] = str.stringify(value)
  end

  local _, errors, warnings = schema.validate_shortcode(
    name, positional, plain_kwargs(kwargs), entry)

  -- Reported as warnings, not errors: the rendered icon never changes because
  -- of a schema mismatch on an attribute, so this is advice rather than a
  -- failure. An unrecognised value is still handled by the code that reads it.
  for _, message in ipairs(warnings) do
    log.log_warning(EXTENSION_NAME, message)
  end

  -- A required argument that is absent is the one case the rule above does not
  -- cover: without it there is no icon, so the output does change. The check
  -- is made here rather than read out of the validator's findings because the
  -- validator reports a nested argument fault under one `arguments` entry,
  -- which cannot tell a missing argument from a malformed one.
  --- @type table<integer, table>
  local missing = {}
  for index, argument in ipairs(entry.arguments or {}) do
    if argument.required == true and str.is_empty(positional[index]) then
      missing[#missing + 1] = argument
    end
  end

  if #missing > 0 then
    -- The only message about the missing argument: the schema's own `required`
    -- wording says the same thing, and reporting both would state one fault
    -- twice at two severities. Attribute warnings above still stand, and every
    -- other finding about this call is secondary to there being no icon.
    for _, argument in ipairs(missing) do
      --- The example comes from the schema so that each shortcode carries its
      --- own, rather than this message naming one shortcode for all of them.
      --- @type string
      local advice = ''
      local example = type(argument.examples) == 'table' and argument.examples[1] or nil
      if example ~= nil then
        advice = string.format(' For example: {{< %s %s >}}.', name, tostring(example))
      end
      log.log_error(EXTENSION_NAME, string.format(
        'The "%s" shortcode needs its "%s" argument.%s', name, argument.name, advice))
    end
    return
  end

  for _, message in ipairs(errors) do
    log.log_warning(EXTENSION_NAME, message)
  end
end

--- Render a resolved option for the string contract every caller expects.
--- A schema `inline: true` therefore reads as "true", which is what
--- `meta_mod.get_metadata_value` produces for the same value in metadata.
--- @param value any A value from the schema, of any scalar type
--- @return string
local function option_to_string(value)
  local kind = type(value)
  if kind == 'string' then
    return value
  end
  if kind == 'number' or kind == 'boolean' then
    return tostring(value)
  end
  return ''
end

--- Get a document-level option, ignoring shortcode attributes.
--- Resolution order: nested `extensions.iconify.<key>`, then the deprecated
--- top-level `iconify.<key>` (with a per-key deprecation warning), then the
--- default declared in `_schema.yml`.
---
--- The schema default is deliberately last. Placed any earlier it would mask
--- the deprecated form, because a default is always present once declared.
---
--- Presence is tested with `~= nil` rather than truthiness, so a deliberate
--- `inline: false` or `typst-cache-max-age: 0` is honoured instead of being
--- read as an absent key and replaced by its own default.
--- @param key string The option name to retrieve
--- @param meta table<string, any> Document metadata table
--- @return string The option value as a string
local function document_option(key, meta)
  --- @type table|nil
  local options = resolve_document_options(meta)

  if options ~= nil and options.provided[key] ~= nil then
    return option_to_string(options.merged[key])
  end

  local deprecated_value = check_deprecated_config(meta, key)
  if deprecated_value then
    return deprecated_value
  end

  if options ~= nil then
    return option_to_string(options.defaults[key])
  end

  return SCHEMA_UNAVAILABLE[key] or ''
end

--- Get an iconify option from arguments or metadata.
--- The shortcode attribute wins, then the document tiers in `document_option`.
--- @param x string The option name to retrieve
--- @param arg table<string, any> Arguments table containing options
--- @param meta table<string, any> Document metadata table
--- @return string The option value as a string
local function get_iconify_options(x, arg, meta)
  --- @type string
  local arg_value = attr_value(arg, x)

  if not str.is_empty(arg_value) then
    return arg_value
  end

  return document_option(x, meta)
end

--- Collect the Typst cache options for the typst module.
--- The module holds no default of its own, so both the value and the
--- last-resort fallback are read from `_schema.yml` here.
--- @param meta table<string, any> Document metadata
--- @return table<string, string>
local function typst_cache_options(meta)
  --- @type table|nil
  local options = resolve_document_options(meta)
  return {
    cache_dir = document_option('typst-cache', meta),
    cache_fallback = options
      and option_to_string(options.defaults['typst-cache'])
      or SCHEMA_UNAVAILABLE['typst-cache'],
    max_age_days = document_option('typst-cache-max-age', meta),
    max_entries = document_option('typst-cache-max-entries', meta),
  }
end

--- Render an Iconify icon as a Typst `#image`, delegating retrieval and
--- caching to the typst module. Geometric and colour transforms are baked
--- into the fetched SVG via the Iconify API; size is applied as the Typst
--- image height so it scales with the surrounding text.
--- @param icon string Resolved icon name
--- @param set string Resolved icon set
--- @param default_label string Fallback accessibility label
--- @param decorative boolean Whether the icon is marked decorative
--- @param kwargs table<string, any> Key-value options for the icon
--- @param meta table<string, any> Document metadata
--- @return any Pandoc RawInline (Typst), Str (fallback) or Null
local function render_typst(icon, set, default_label, decorative, kwargs, meta)
  --- @type string
  local size_raw = resolve_size_value(get_iconify_options('size', kwargs, meta))
  --- @type string|nil
  local size_value = typst.typst_length(size_raw)
  if size_raw ~= '' and size_value == nil then
    log.log_warning(
      EXTENSION_NAME,
      'Size "' .. size_raw .. '" uses a unit Typst does not support; ' ..
      'falling back to 1em for Typst output. ' ..
      'Use em, pt, cm, mm, in or % for Typst sizing.'
    )
  end

  --- Colour: explicit `color` option, otherwise parsed from a `style` value.
  --- @type string
  local colour = get_iconify_options('color', kwargs, meta)
  if str.is_empty(colour) then
    --- @type string
    local style = get_iconify_options('style', kwargs, meta)
    if not str.is_empty(style) then
      colour = str.trim(style:match('color%s*:%s*([^;]+)') or '')
    end
  end

  --- @type table<string, string>
  local params = {}
  if not str.is_empty(colour) then params.color = colour end
  --- @type string
  local flip = get_iconify_options('flip', kwargs, meta)
  if not str.is_empty(flip) then params.flip = flip end
  --- @type string
  local rotate = get_iconify_options('rotate', kwargs, meta)
  if not str.is_empty(rotate) then params.rotate = rotate end

  --- A decorative icon carries no `alt`, which the typst module omits when the
  --- value is empty.
  --- @type string
  local alt = ''
  if not decorative then
    alt = attr_value(kwargs, 'label')
    if str.is_empty(alt) then alt = attr_value(kwargs, 'title') end
    if str.is_empty(alt) then alt = default_label end
  end

  --- @type string
  local inline = get_iconify_options('inline', kwargs, meta)

  --- @type table<string, string>
  local cache_options = typst_cache_options(meta)

  --- @type any
  local result = typst.render({
    set = set,
    icon = icon,
    query = typst.build_query(params),
    size_value = size_value,
    inline = str.is_empty(inline) or inline ~= 'false',
    alt = alt,
    fallback = get_iconify_options('fallback', kwargs, meta),
    options = cache_options
  })

  -- Prune the cache once per render, after at least one icon has populated it.
  if not typst_cleanup_done then
    typst_cleanup_done = true
    typst.cleanup(cache_options)
  end

  return result
end

--- Render an Iconify icon as a Pandoc RawInline for HTML output.
--- Expects `args` to have been through `recover_kwargs` already, and does not
--- validate: each shortcode entry point checks its own call against the
--- schema entry that describes it.
--- @param args table<integer, any> Icon arguments (icon set and name)
--- @param kwargs table<string, any> Key-value options for the icon
--- @param meta table<string, any> Document metadata
--- @return any Pandoc RawInline for HTML or Pandoc Null for other formats
local function render_icon(args, kwargs, meta)

  -- Checked before the format gate below, so a call with no icon is handled
  -- the same way for every output format rather than only the two that render
  -- something. An empty first argument counts as no icon, which is what the
  -- schema's `required` check already decided, so the two agree.
  -- `validate_call` has reported this to the author; there is nothing to add
  -- here beyond not reading a first argument that is not there.
  if #args == 0 or str.is_empty(str.stringify(args[1])) then
    return pandoc.Null()
  end

  -- HTML (excluding epub which will not host the Web Component) renders the
  -- Web Component; Typst renders a cached SVG. Every other format renders
  -- nothing.
  --- @type boolean
  local is_html = quarto.doc.is_format('html:js')
  --- @type boolean
  local is_typst = quarto.doc.is_format('typst')
  if not is_html and not is_typst then
    return pandoc.Null()
  end

  --- @type string
  local icon = str.stringify(args[1])

  --- The icon set comes from the positional arguments, never from a shortcode
  --- attribute, so this reads the document tiers only. The fallback is the
  --- `set` default in `_schema.yml`.
  --- @type string
  local set = document_option('set', meta)

  if #args > 1 and string.find(str.stringify(args[2]), ':') then
    log.log_warning(
      EXTENSION_NAME,
      'Use "set:icon" or "set icon" syntax, not both! ' ..
      'Using "set:icon" syntax and discarding first argument!'
    )
    icon = str.stringify(args[2])
  end

  if string.find(icon, ':') then
    set = string.sub(icon, 1, string.find(icon, ':') - 1)
    icon = string.sub(icon, string.find(icon, ':') + 1)
  elseif #args > 1 then
    set = icon
    icon = str.stringify(args[2])
  end

  -- Validate icon and set names. Invalid names still render so that authors
  -- can see what went wrong in the output, but a warning is emitted.
  if not is_valid_iconify_name(set) then
    log.log_warning(
      EXTENSION_NAME,
      'Icon set name "' .. set .. '" is invalid. ' ..
      'Use lowercase letters, digits and single hyphens (e.g. "fa6-brands"). ' ..
      'The icon will likely fail to load.'
    )
  end
  if not is_valid_iconify_name(icon) then
    log.log_warning(
      EXTENSION_NAME,
      'Icon name "' .. icon .. '" is invalid. ' ..
      'Use lowercase letters, digits and single hyphens (e.g. "exploding-head"). ' ..
      'The icon will likely fail to load.'
    )
  end

  --- @type string
  local default_label = 'Icon ' .. icon .. ' from ' .. set .. ' Iconify.design set.'

  --- @type boolean
  local decorative = is_decorative(kwargs, true)
  if decorative and (not str.is_empty(attr_value(kwargs, 'label')) or
        not str.is_empty(attr_value(kwargs, 'title'))) then
    log.log_warning(
      EXTENSION_NAME,
      'Icon "' .. set .. ':' .. icon .. '" sets aria-hidden="true" together ' ..
      'with label or title. A decorative icon carries neither, so both are ' ..
      'discarded. Drop aria-hidden to keep them.'
    )
  end

  if is_typst then
    return render_typst(icon, set, default_label, decorative, kwargs, meta)
  end

  ensure_html_deps()

  --- @type string
  local attributes = html_attribute('icon', set .. ':' .. icon)

  --- @type string
  local size = resolve_size(get_iconify_options('size', kwargs, meta))
  --- @type string
  local style = get_iconify_options('style', kwargs, meta)

  if str.is_empty(style) and not str.is_empty(size) then
    attributes = attributes .. html_attribute('style', size)
  elseif not str.is_empty(style) and not str.is_empty(size) then
    attributes = attributes .. html_attribute('style', style .. ';' .. size)
  elseif not str.is_empty(style) then
    attributes = attributes .. html_attribute('style', style)
  end

  --- A decorative icon is hidden from assistive technology, so it carries
  --- `aria-hidden` in place of `role`, and neither `aria-label` nor `title`.
  --- @type string
  local role = ' role="img"'
  if decorative then
    role = ' aria-hidden="true"'
  else
    --- @type string
    local aria_label = attr_value(kwargs, 'label')
    if str.is_empty(aria_label) then
      aria_label = default_label
    end

    --- @type string
    local title = attr_value(kwargs, 'title')
    if str.is_empty(title) then
      title = default_label
    end

    attributes = attributes ..
        html_attribute('aria-label', aria_label) ..
        html_attribute('title', title)
  end

  --- @type string
  local width = get_iconify_options('width', kwargs, meta)
  if not str.is_empty(width) and str.is_empty(size) then
    attributes = attributes .. html_attribute('width', width)
  end
  --- @type string
  local height = get_iconify_options('height', kwargs, meta)
  if not str.is_empty(height) and str.is_empty(size) then
    attributes = attributes .. html_attribute('height', height)
  end
  --- @type string
  local flip = get_iconify_options('flip', kwargs, meta)
  if not str.is_empty(flip) then
    attributes = attributes .. html_attribute('flip', flip)
  end
  --- @type string
  local rotate = get_iconify_options('rotate', kwargs, meta)
  if not str.is_empty(rotate) then
    attributes = attributes .. html_attribute('rotate', rotate)
  end

  --- @type string
  local inline = get_iconify_options('inline', kwargs, meta)
  if str.is_empty(inline) or inline ~= 'false' then
    attributes = ' inline ' .. attributes
  end

  --- @type string
  local mode = get_iconify_options('mode', kwargs, meta)
  --- @type table<string, boolean>
  local valid_modes = { svg = true, style = true, bg = true, mask = true }
  if not str.is_empty(mode) and valid_modes[mode] then
    attributes = attributes .. html_attribute('mode', mode)
  end

  --- @type string
  local fallback = get_iconify_options('fallback', kwargs, meta)

  if not str.is_empty(fallback) then
    ensure_fallback_runtime()
    --- The fallback text is a sibling of the icon rather than a descendant,
    --- so hiding the icon alone would leave the revealed text announced.
    --- @type string
    local wrapper_hidden = ''
    if decorative then
      wrapper_hidden = ' aria-hidden="true"'
    end
    return pandoc.RawInline(
      'html',
      '<span class="iconify-icon-wrapper" data-iconify-fallback' .. wrapper_hidden .. '>' ..
      '<iconify-icon' .. role .. attributes .. '></iconify-icon>' ..
      --- The fallback is documented as text or an emoji, so it is escaped
      --- rather than trusted as markup.
      '<span class="iconify-icon-fallback" hidden>' .. str.escape_html(fallback) .. '</span>' ..
      '</span>'
    )
  end

  return pandoc.RawInline(
    'html',
    '<iconify-icon' .. role .. attributes .. '></iconify-icon>'
  )
end

--- The `iconify` shortcode: check the call, then render it.
--- @param args table<integer, any> Icon arguments (icon set and name)
--- @param kwargs table<string, any> Key-value options for the icon
--- @param meta table<string, any> Document metadata
--- @return any Pandoc RawInline for HTML or Pandoc Null for other formats
local function iconify(args, kwargs, meta)
  resolve_document_options(meta)
  args = recover_kwargs(args, kwargs)
  validate_call('iconify', args, kwargs)
  return render_icon(args, kwargs, meta)
end

--- Render Quarto icon using the iconify function with preset styling.
--- @param args table<integer, any> Icon arguments (the icon is a preset, so these are read only for attributes a metadata field left unparsed)
--- @param kwargs table<string, any>|nil Key-value options that might override default styling
--- @param meta table<string, any> Document metadata
--- @return any Pandoc RawInline for HTML or Pandoc Null for other formats
local function iconify_quarto(args, kwargs, meta)
  --- @type table<integer, string>
  local quarto_args = { 'simple-icons:quarto' }
  --- @type table<string, any>
  local quarto_kwargs = kwargs or {}
  resolve_document_options(meta)
  recover_kwargs(args, quarto_kwargs)
  validate_call('quarto', {}, quarto_kwargs)
  -- A decorative icon carries neither, and setting them here would re-introduce
  -- exactly what `aria-hidden` removes.
  if not is_decorative(quarto_kwargs, false) then
    quarto_kwargs['label'] = 'Quarto icon'
    quarto_kwargs['title'] = 'Quarto icon'
  end
  --- @type string
  local quarto_colour = 'color:#74aadb;'

  if not str.is_empty(quarto_kwargs['style']) then
    --- @type string
    local style = attr_value(quarto_kwargs, 'style')
    if string.match(style, 'color:[^;]+;') then
      quarto_kwargs['style'] = string.gsub(style, 'color:[^;]+;', quarto_colour)
    else
      quarto_kwargs['style'] = quarto_colour .. style
    end
  else
    quarto_kwargs['style'] = quarto_colour
  end
  return render_icon(quarto_args, quarto_kwargs, meta)
end

--- @type table<string, function>
return {
  ['iconify'] = iconify,
  ['quarto'] = iconify_quarto
}
