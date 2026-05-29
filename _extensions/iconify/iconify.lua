--- @module iconify
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil

--- Extension name constant
local EXTENSION_NAME = "iconify"

--- Load modules
local str = require(quarto.utils.resolve_path('_modules/string.lua'):gsub('%.lua$', ''))
local log = require(quarto.utils.resolve_path('_modules/logging.lua'):gsub('%.lua$', ''))
local meta_mod = require(quarto.utils.resolve_path('_modules/metadata.lua'):gsub('%.lua$', ''))

--- Per-key deprecation warning tracker. Each deprecated metadata key warns
--- at least once per render rather than once total. The companion filter
--- (`iconify-filter.lua`) is responsible for any per-document state reset
--- in batch renders; this shortcode keeps the tracker local to its own
--- module instance.
--- @type table<string, boolean>
local deprecation_warned_keys = {}

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

--- Validate and convert a size value to a CSS font-size declaration.
--- Returns an empty string when the value is empty or invalid, after emitting
--- a warning for the invalid case. This honours the README contract that
--- "When the size is invalid, no size changes are made."
--- @param size string|nil
--- @return string
local function resolve_size(size)
  if str.is_empty(size) then
    return ''
  end
  --- @type string|nil
  local mapped = SIZE_KEYWORDS[size]
  if mapped ~= nil then
    return 'font-size: ' .. mapped .. ';'
  end
  if is_css_length(size) then
    return 'font-size: ' .. size .. ';'
  end
  log.log_warning(
    EXTENSION_NAME,
    'Ignoring invalid size value "' .. size .. '". ' ..
    'Use a CSS length (e.g. "1.5em", "32px"), a literal size like "2x", ' ..
    'or a LaTeX-style keyword like "Huge". Size left unchanged.'
  )
  return ''
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

--- Get an iconify option from arguments or metadata.
--- Resolution order: positional/named kwargs first, then nested
--- `extensions.iconify.<key>`, then the deprecated top-level `iconify.<key>`
--- (with a per-key deprecation warning).
--- @param x string The option name to retrieve
--- @param arg table<string, any> Arguments table containing options
--- @param meta table<string, any> Document metadata table
--- @return string The option value as a string
local function get_iconify_options(x, arg, meta)
  --- @type string
  local arg_value = str.stringify(arg[x])

  if not str.is_empty(arg_value) then
    return arg_value
  end

  local meta_value = meta_mod.get_metadata_value(meta, 'iconify', x)
  if not str.is_empty(meta_value) then
    return meta_value
  end

  local deprecated_value = check_deprecated_config(meta, x)
  if deprecated_value then
    return deprecated_value
  end

  return arg_value
end

--- Render an Iconify icon as a Pandoc RawInline for HTML output.
--- @param args table<integer, any> Icon arguments (icon set and name)
--- @param kwargs table<string, any> Key-value options for the icon
--- @param meta table<string, any> Document metadata
--- @return any Pandoc RawInline for HTML or Pandoc Null for other formats
local function iconify(args, kwargs, meta)
  -- Detect HTML output (excluding epub which will not host the Web Component).
  if not quarto.doc.is_format('html:js') then
    return pandoc.Null()
  end

  ensure_html_deps()

  --- @type string
  local icon = str.stringify(args[1])
  --- @type string
  local set = 'octicon'

  -- Resolve the default icon set, preferring the nested metadata structure.
  local meta_set = meta_mod.get_metadata_value(meta, 'iconify', 'set')
  if not str.is_empty(meta_set) then
    set = meta_set
  else
    local deprecated_set = check_deprecated_config(meta, 'set')
    if deprecated_set then
      set = deprecated_set
    end
  end

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
  local attributes = ' icon="' .. set .. ':' .. icon .. '"'
  --- @type string
  local default_label = 'Icon ' .. icon .. ' from ' .. set .. ' Iconify.design set.'

  --- @type string
  local size = resolve_size(get_iconify_options('size', kwargs, meta))
  --- @type string
  local style = get_iconify_options('style', kwargs, meta)

  if str.is_empty(style) and not str.is_empty(size) then
    attributes = attributes .. ' style="' .. size .. '"'
  elseif not str.is_empty(style) and not str.is_empty(size) then
    attributes = attributes .. ' style="' .. style .. ';' .. size .. '"'
  elseif not str.is_empty(style) then
    attributes = attributes .. ' style="' .. style .. '"'
  end

  --- @type string
  local aria_label = str.stringify(kwargs['label'])
  if str.is_empty(aria_label) then
    aria_label = ' aria-label="' .. default_label .. '"'
  else
    aria_label = ' aria-label="' .. aria_label .. '"'
  end

  --- @type string
  local title = str.stringify(kwargs['title'])
  if str.is_empty(title) then
    title = ' title="' .. default_label .. '"'
  else
    title = ' title="' .. title .. '"'
  end

  attributes = attributes .. aria_label .. title

  --- @type string
  local width = get_iconify_options('width', kwargs, meta)
  if not str.is_empty(width) and str.is_empty(size) then
    attributes = attributes .. ' width="' .. width .. '"'
  end
  --- @type string
  local height = get_iconify_options('height', kwargs, meta)
  if not str.is_empty(height) and str.is_empty(size) then
    attributes = attributes .. ' height="' .. height .. '"'
  end
  --- @type string
  local flip = get_iconify_options('flip', kwargs, meta)
  if not str.is_empty(flip) then
    attributes = attributes .. ' flip="' .. flip .. '"'
  end
  --- @type string
  local rotate = get_iconify_options('rotate', kwargs, meta)
  if not str.is_empty(rotate) then
    attributes = attributes .. ' rotate="' .. rotate .. '"'
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
    attributes = attributes .. ' mode="' .. mode .. '"'
  end

  --- @type string
  local fallback = get_iconify_options('fallback', kwargs, meta)

  if not str.is_empty(fallback) then
    ensure_fallback_runtime()
    return pandoc.RawInline(
      'html',
      '<span class="iconify-icon-wrapper" data-iconify-fallback>' ..
      '<iconify-icon role="img"' .. attributes .. '></iconify-icon>' ..
      '<span class="iconify-icon-fallback" hidden>' .. fallback .. '</span>' ..
      '</span>'
    )
  end

  return pandoc.RawInline(
    'html',
    '<iconify-icon role="img"' .. attributes .. '></iconify-icon>'
  )
end

--- Render Quarto icon using the iconify function with preset styling.
--- @param args table<integer, any> Icon arguments (ignored as we're using a preset icon)
--- @param kwargs table<string, any>|nil Key-value options that might override default styling
--- @param meta table<string, any> Document metadata
--- @return any Pandoc RawInline for HTML or Pandoc Null for other formats
local function iconify_quarto(args, kwargs, meta)
  --- @type table<integer, string>
  local quarto_args = { 'simple-icons:quarto' }
  --- @type table<string, any>
  local quarto_kwargs = kwargs or {}
  quarto_kwargs['label'] = 'Quarto icon'
  quarto_kwargs['title'] = 'Quarto icon'
  --- @type string
  local quarto_colour = 'color:#74aadb;'

  if not str.is_empty(quarto_kwargs['style']) then
    --- @type string
    local style = str.stringify(quarto_kwargs['style'])
    if string.match(style, 'color:[^;]+;') then
      quarto_kwargs['style'] = string.gsub(style, 'color:[^;]+;', quarto_colour)
    else
      quarto_kwargs['style'] = quarto_colour .. style
    end
  else
    quarto_kwargs['style'] = quarto_colour
  end
  return iconify(quarto_args, quarto_kwargs, meta)
end

--- @type table<string, function>
return {
  ['iconify'] = iconify,
  ['quarto'] = iconify_quarto
}
