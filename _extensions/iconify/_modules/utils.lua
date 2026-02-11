--- MC Utils - Common utility functions for Quarto Lua filters and shortcodes
--- @module utils
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @version 1.0.0

local M = {}

-- ============================================================================
-- STRING UTILITIES
-- ============================================================================

--- Pandoc utility function for converting values to strings
--- @type function
M.stringify = pandoc.utils.stringify

--- Check if a string is empty or nil.
--- Utility function to determine if a value is empty or nil,
--- which is useful for parameter validation throughout the module.
--- @param s string|nil|table The value to check for emptiness
--- @return boolean True if the value is nil or empty, false otherwise
--- @usage local result = M.is_empty("") -- returns true
--- @usage local result = M.is_empty(nil) -- returns true
--- @usage local result = M.is_empty("hello") -- returns false
function M.is_empty(s)
  return s == nil or s == ''
end

--- Escape special pattern characters in a string for Lua pattern matching
--- @param s string The string to escape
--- @return string The escaped string
--- @usage local escaped = M.escape_pattern("user/repo#123")
function M.escape_pattern(s)
  local escaped = s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return escaped
end

--- Split a string by a separator
--- @param str string The string to split
--- @param sep string The separator pattern
--- @return table Array of string fields
--- @usage local parts = M.split("a.b.c", ".")
function M.split(str, sep)
  local fields = {}
  local pattern = string.format("([^%s]+)", sep)
  str:gsub(pattern, function(c) fields[#fields + 1] = c end)
  return fields
end

--- Trim leading and trailing whitespace from a string
--- @param str string The string to trim
--- @return string The trimmed string
--- @usage local trimmed = M.trim("  hello world  ") -- returns "hello world"
function M.trim(str)
  if str == nil then return '' end
  return str:match('^%s*(.-)%s*$')
end

--- Convert any value to a string, handling Pandoc objects and empty values.
--- Returns nil for empty or nil values, otherwise returns a string representation.
--- @param val any The value to convert
--- @return string|nil The string value or nil if empty
--- @usage local str = M.to_string(kwargs.value)
function M.to_string(val)
  if not val then return nil end
  if type(val) == 'string' then
    return val ~= '' and val or nil
  end
  -- Handle Pandoc objects
  if pandoc and pandoc.utils and pandoc.utils.stringify then
    local str = pandoc.utils.stringify(val)
    return str ~= '' and str or nil
  end
  local str = tostring(val)
  return str ~= '' and str or nil
end

--- Escape special LaTeX characters in text.
--- @param text string The text to escape
--- @return string The escaped text safe for LaTeX
function M.escape_latex(text)
  text = string.gsub(text, "\\", "\\textbackslash{}")
  text = string.gsub(text, "%{", "\\{")
  text = string.gsub(text, "%}", "\\}")
  text = string.gsub(text, "%$", "\\$")
  text = string.gsub(text, "%&", "\\&")
  text = string.gsub(text, "%%", "\\%%")
  text = string.gsub(text, "%#", "\\#")
  text = string.gsub(text, "%^", "\\textasciicircum{}")
  text = string.gsub(text, "%_", "\\_")
  text = string.gsub(text, "~", "\\textasciitilde{}")
  return text
end

--- Escape special Typst characters in text.
--- @param text string The text to escape
--- @return string The escaped text safe for Typst
function M.escape_typst(text)
  text = string.gsub(text, "%#", "\\#")
  return text
end

--- Escape special Lua pattern characters for use in string.gsub.
--- @param text string The text containing characters to escape
--- @return string The escaped text safe for Lua patterns
function M.escape_lua_pattern(text)
  text = string.gsub(text, "%%", "%%%%")
  text = string.gsub(text, "%^", "%%^")
  text = string.gsub(text, "%$", "%%$")
  text = string.gsub(text, "%(", "%%(")
  text = string.gsub(text, "%)", "%%)")
  text = string.gsub(text, "%.", "%%.")
  text = string.gsub(text, "%[", "%%[")
  text = string.gsub(text, "%]", "%%]")
  text = string.gsub(text, "%*", "%%*")
  text = string.gsub(text, "%+", "%%+")
  text = string.gsub(text, "%-", "%%-")
  text = string.gsub(text, "%?", "%%?")
  return text
end

--- Escape special HTML characters in text.
--- Escapes &, <, >, ", and ' to prevent XSS and ensure valid HTML.
--- @param text string The text to escape
--- @return string Escaped text safe for use in HTML
--- @usage local escaped = M.escape_html('Hello <World>')
function M.escape_html(text)
  if text == nil then return '' end
  if type(text) ~= 'string' then text = tostring(text) end
  local result = text
      :gsub('&', '&amp;')
      :gsub('<', '&lt;')
      :gsub('>', '&gt;')
      :gsub('"', '&quot;')
      :gsub("'", '&#39;')
  return result
end

--- Escape special HTML attribute characters.
--- Escapes characters that could break attribute values.
--- @param value string The attribute value to escape
--- @return string Escaped value safe for use in HTML attributes
--- @usage local escaped = M.escape_attribute('Hello "World"')
function M.escape_attribute(value)
  if value == nil then return '' end
  if type(value) ~= 'string' then value = tostring(value) end
  local result = value
      :gsub('&', '&amp;')
      :gsub('"', '&quot;')
      :gsub('<', '&lt;')
      :gsub('>', '&gt;')
  return result
end

--- Escape text for different formats.
--- @param text string The text to escape
--- @param format string The format to escape for (e.g., "latex", "typst", "lua")
--- @return string The escaped text
function M.escape_text(text, format)
  local escape_functions = {
    latex = M.escape_latex,
    typst = M.escape_typst,
    lua = M.escape_lua_pattern
  }

  local escape = escape_functions[format]
  if escape then
    return escape(text)
  else
    error("Unsupported escape format: " .. format)
  end
end

--- Converts a string to a valid HTML id by lowercasing and replacing spaces.
--- @param text string The text to convert
--- @return string The HTML id
function M.ascii_id(text)
  local id = text:lower():gsub("[^a-z0-9 ]", ""):gsub(" +", "-")
  return id
end

-- ============================================================================
-- METADATA UTILITIES
-- ============================================================================

--- Get configuration from extensions.mcanouil namespace.
--- @param meta table Document metadata
--- @param key string The key to retrieve
--- @return any The value or nil
--- @usage local value = M.get_mcanouil_config(meta, 'section-outline')
function M.get_mcanouil_config(meta, key)
  local mcanouil_ext = meta.extensions and meta.extensions.mcanouil
  if not mcanouil_ext then return nil end
  return mcanouil_ext[key]
end

--- Get a section config table from extensions.mcanouil.{section}.
--- @param meta table Document metadata
--- @param section string The section name (e.g., 'code-window', 'typst-markdown')
--- @return table|nil The section config table or nil
--- @usage local config = M.get_mcanouil_section(meta, 'code-window')
function M.get_mcanouil_section(meta, section)
  local mcanouil_ext = meta.extensions and meta.extensions.mcanouil
  if not mcanouil_ext then return nil end
  return mcanouil_ext[section]
end

--- Extract metadata value from document meta using nested structure.
--- Supports the extensions.{extension-name}.{key} pattern.
--- @param meta table The document metadata table
--- @param extension_name string The extension name (e.g., "github", "iconify")
--- @param key string The metadata key to retrieve
--- @return string|nil The metadata value as a string, or nil if not found
--- @usage local repo = M.get_metadata_value(meta, "github", "repository-name")
function M.get_metadata_value(meta, extension_name, key)
  if meta['extensions'] and meta['extensions'][extension_name] and meta['extensions'][extension_name][key] then
    return M.stringify(meta['extensions'][extension_name][key])
  end
  return nil
end

--- Check for deprecated top-level configuration and emit warning
--- @param meta table The document metadata table
--- @param extension_name string The extension name
--- @param key string|nil The configuration key being accessed (nil to check entire extension config)
--- @param deprecation_warning_shown boolean Flag to track if warning has been shown
--- @return any|nil The value from deprecated config, or nil if not found
--- @return boolean Updated deprecation warning flag
function M.check_deprecated_config(meta, extension_name, key, deprecation_warning_shown)
  -- Handle array-based configuration (when key is nil)
  if key == nil then
    if not M.is_empty(meta[extension_name]) then
      if not deprecation_warning_shown then
        M.log_warning(
          extension_name,
          'Top-level "' .. extension_name .. '" configuration is deprecated. ' ..
          'Please use:\n' ..
          'extensions:\n' ..
          '  ' .. extension_name .. ':\n' ..
          '    - (configuration array)'
        )
        deprecation_warning_shown = true
      end
      return meta[extension_name], deprecation_warning_shown
    end
    return nil, deprecation_warning_shown
  end

  -- Handle key-value configuration (original behaviour)
  if not M.is_empty(meta[extension_name]) and not M.is_empty(meta[extension_name][key]) then
    if not deprecation_warning_shown then
      M.log_warning(
        extension_name,
        'Top-level "' .. extension_name .. '" configuration is deprecated. ' ..
        'Please use:\n' ..
        'extensions:\n' ..
        '  ' .. extension_name .. ':\n' ..
        '    ' .. key .. ': value'
      )
      deprecation_warning_shown = true
    end
    return M.stringify(meta[extension_name][key]), deprecation_warning_shown
  end
  return nil, deprecation_warning_shown
end

-- ============================================================================
-- PANDOC/QUARTO FORMAT UTILITIES
-- ============================================================================

--- Create a Pandoc Link element
--- @param text string|nil The link text
--- @param uri string|nil The URI to link to
--- @return pandoc.Link|nil A Pandoc Link element or nil if text or uri is empty
function M.create_link(text, uri)
  if not M.is_empty(uri) and not M.is_empty(text) then
    return pandoc.Link({ pandoc.Str(text --[[@as string]]) }, uri --[[@as string]])
  end
  return nil
end

--- Helper to build Pandoc attributes
--- @param id string|nil Element ID
--- @param classes table|nil List of CSS classes
--- @param attributes table|nil Key-value attributes
--- @return pandoc.Attr Pandoc Attr object
function M.attr(id, classes, attributes)
  return pandoc.Attr(id or '', classes or {}, attributes or {})
end

--- Check if a class list contains a specific class name
--- @param classes table|nil List of CSS classes
--- @param name string The class name to search for
--- @return boolean True if the class is found, false otherwise
function M.has_class(classes, name)
  if not classes then return false end
  for _, cls in ipairs(classes) do
    if cls == name then return true end
  end
  return false
end

--- Add a class to the class list if it doesn't already exist
--- @param classes table List of CSS classes
--- @param name string The class name to add
function M.add_class(classes, name)
  if not M.has_class(classes, name) then
    table.insert(classes, name)
  end
end

--- Retrieve the current Quarto output format.
--- @return string The output format ("pptx", "html", "latex", "typst", "docx", or "unknown")
--- @return string The language of the output format
function M.get_quarto_format()
  if quarto.doc.is_format("html:js") then
    return "html", "html"
  elseif quarto.doc.is_format("latex") then
    return "latex", "latex"
  elseif quarto.doc.is_format("typst") then
    return "typst", "typst"
  elseif quarto.doc.is_format("docx") then
    return "docx", "openxml"
  elseif quarto.doc.is_format("pptx") then
    return "pptx", "openxml"
  else
    return "unknown", "unknown"
  end
end

-- ============================================================================
-- OBJECT/TABLE UTILITIES
-- ============================================================================

--- Check if an object (including tables and lists) is empty or nil
--- @param obj any The object to check
--- @return boolean true if the object is nil, empty string, or empty table/list
function M.is_object_empty(obj)
  local function length(x)
    local count = 0
    if x ~= nil then
      for _ in pairs(x) do
        count = count + 1
      end
    end
    return count
  end
  if pandoc.utils.type(obj) == "table" or pandoc.utils.type(obj) == "List" then
    return obj == nil or obj == '' or length(obj) == 0
  else
    return obj == nil or obj == ''
  end
end

--- Check if an object is a simple type (string, number, or boolean)
--- @param obj any The object to check
--- @return boolean true if the object is a string, number, or boolean
function M.is_type_simple(obj)
  return pandoc.utils.type(obj) == "string" or pandoc.utils.type(obj) == "number" or pandoc.utils.type(obj) == "boolean"
end

--- Check if an object is a function or userdata
--- @param obj any The object to check
--- @return boolean true if the object is a function or userdata
function M.is_function_userdata(obj)
  return pandoc.utils.type(obj) == "function" or pandoc.utils.type(obj) == "userdata"
end

--- Get nested value from object using field path
--- @param fields table Array of field names to traverse
--- @param obj table The object to extract value from
--- @return any The value at the nested path
--- @usage local val = M.get_value({"a", "b", "c"}, obj)
function M.get_value(fields, obj)
  local value = obj
  for _, field in ipairs(fields) do
    value = value[field]
  end
  return value
end

--- Convert Pandoc AttributeList to plain table for easier processing.
--- @param element table Element with attributes field (Div, Span, Table, Image)
--- @return table Plain table with attribute key-value pairs
function M.attributes_to_table(element)
  local attrs = {}
  for k, v in pairs(element.attributes) do
    attrs[k] = v
  end
  return attrs
end

-- ============================================================================
-- HTML RAW GENERATION UTILITIES
-- ============================================================================

--- Generates a raw HTML header element.
--- @param level integer The header level (e.g., 2 for <h2>)
--- @param text string|nil The header text
--- @param id string The id attribute for the header
--- @param classes table List of classes for the header
--- @param attributes table|nil Additional HTML attributes
--- @return string Raw HTML string for the header
function M.raw_header(level, text, id, classes, attributes)
  local attr_str = ''
  if id and id ~= '' then
    attr_str = attr_str .. ' id="' .. M.escape_attribute(id) .. '"'
  end
  if classes and #classes > 0 then
    local escaped_classes = {}
    for i, cls in ipairs(classes) do
      escaped_classes[i] = M.escape_attribute(cls)
    end
    attr_str = attr_str .. ' class="' .. table.concat(escaped_classes, ' ') .. '"'
  end
  if attributes then
    for k, v in pairs(attributes) do
      attr_str = attr_str .. ' ' .. M.escape_attribute(k) .. '="' .. M.escape_attribute(v) .. '"'
    end
  end
  return string.format('<h%d%s>%s</h%d>', level, attr_str, M.escape_html(text or ''), level)
end

-- ============================================================================
-- HTML DEPENDENCY UTILITIES
-- ============================================================================

--- Managed HTML dependency tracker
--- Tracks which dependencies have been added to prevent duplication
--- @type table<string, boolean>
local dependency_tracker = {}

--- Ensure HTML dependency is added only once per document.
--- Prevents duplicate dependency injection by tracking dependencies by name.
--- Returns true if dependency was added, false if already present.
---
--- @param config table Dependency configuration with fields: name (required), version, scripts, stylesheets, head
--- @return boolean True if dependency was added, false if already added
--- @usage M.ensure_html_dependency({name = 'my-lib', version = '1.0.0', scripts = {'lib.js'}})
function M.ensure_html_dependency(config)
  if not config or not config.name then
    error("HTML dependency configuration must include a 'name' field")
  end

  --- @type string Unique key for this dependency
  local dep_key = config.name

  -- Check if already added
  if dependency_tracker[dep_key] then
    return false
  end

  -- Add the dependency
  quarto.doc.add_html_dependency(config)

  -- Mark as added
  dependency_tracker[dep_key] = true
  return true
end

--- Reset dependency tracker.
--- Useful for testing or when processing multiple independent documents.
--- In normal usage, this should not be called as dependencies persist per document.
---
--- @return nil
function M.reset_dependencies()
  dependency_tracker = {}
end

-- ============================================================================
-- ENHANCED METADATA/CONFIGURATION UTILITIES
-- ============================================================================

--- Get option value with fallback hierarchy: args → extensions.{extension}.{key} → defaults.
--- Provides a standardised way to read configuration values with multiple fallback levels.
--- Priority: 1. Named arguments (kwargs), 2. Document metadata, 3. Default values.
---
--- @param spec table Configuration spec with fields: extension (string), key (string), args (table|nil), meta (table|nil), default (any|nil)
--- @return any The resolved option value (type depends on what's stored in config)
--- @usage local duration = M.get_option_with_fallbacks({extension = 'animate', key = 'duration', args = kwargs, meta = meta, default = '3s'})
function M.get_option_with_fallbacks(spec)
  -- Validate required fields
  if not spec.extension or not spec.key then
    error("Configuration spec must include 'extension' and 'key' fields")
  end

  --- @type string The extension name
  local extension = spec.extension
  --- @type string The configuration key
  local key = spec.key
  --- @type table|nil Named arguments table
  local args = spec.args
  --- @type table|nil Document metadata
  local meta = spec.meta
  --- @type any Default value if not found elsewhere
  local default = spec.default

  -- Priority 1: Check named arguments (kwargs)
  if args and args[key] then
    local arg_value = M.stringify(args[key])
    if not M.is_empty(arg_value) then
      return arg_value
    end
  end

  -- Priority 2: Check metadata extensions.{extension}.{key}
  if meta then
    local meta_value = M.get_metadata_value(meta, extension, key)
    if not M.is_empty(meta_value) then
      return meta_value
    end
  end

  -- Priority 3: Return default value
  return default
end

--- Get multiple option values at once with fallback hierarchy.
--- Batch version of get_option_with_fallbacks for retrieving multiple configuration values.
--- Returns a table mapping each key to its resolved value.
---
--- @param spec table Configuration spec with fields: extension (string), keys (table<integer, string>), args (table|nil), meta (table|nil), defaults (table<string, any>|nil)
--- @return table<string, any> Table mapping each key to its resolved value
--- @usage local opts = M.get_options({extension = 'animate', keys = {'duration', 'delay'}, args = kwargs, meta = meta, defaults = {duration = '3s', delay = '2s'}})
function M.get_options(spec)
  -- Validate required fields
  if not spec.extension or not spec.keys then
    error("Configuration spec must include 'extension' and 'keys' fields")
  end

  --- @type table<string, any> Result table
  local result = {}

  --- @type table Default values table
  local defaults = spec.defaults or {}

  -- Get each key using the single-option fallback logic
  for _, key in ipairs(spec.keys) do
    result[key] = M.get_option_with_fallbacks({
      extension = spec.extension,
      key = key,
      args = spec.args,
      meta = spec.meta,
      default = defaults[key]
    })
  end

  return result
end

-- ============================================================================
-- LOGGING UTILITIES
-- ============================================================================

--- Format and log an error message with extension prefix.
--- Provides standardised error messages with consistent formatting across extensions.
--- Format: [extension-name] Message with details.
---
--- @param extension_name string The name of the extension (e.g., "external", "lua-env")
--- @param message string The error message to display
--- @usage M.log_error("external", "Could not open file 'example.md'.")
function M.log_error(extension_name, message)
  quarto.log.error("[" .. extension_name .. "] " .. message)
end

--- Format and log a warning message with extension prefix.
--- Provides standardised warning messages with consistent formatting across extensions.
--- Format: [extension-name] Message with details.
---
--- @param extension_name string The name of the extension (e.g., "external", "lua-env")
--- @param message string The warning message to display
--- @usage M.log_warning("lua-env", "No variable name provided.")
function M.log_warning(extension_name, message)
  quarto.log.warning("[" .. extension_name .. "] " .. message)
end

--- Format and log an output message with extension prefix.
--- Provides standardised informational messages with consistent formatting across extensions.
--- Format: [extension-name] Message with details.
---
--- @param extension_name string The name of the extension (e.g., "lua-env")
--- @param message string The informational message to display
--- @usage M.log_output("lua-env", "Exported metadata to: output.json")
function M.log_output(extension_name, message)
  quarto.log.output("[" .. extension_name .. "] " .. message)
end

-- ============================================================================
-- PATH UTILITIES
-- ============================================================================

--- Resolve a path relative to the project directory.
--- If the path starts with `/`, it is treated as relative to the project directory.
--- If `quarto.project.directory` is available, it is prepended to the path.
--- If `quarto.project.directory` is nil, the leading `/` is removed.
--- @param path string The path to resolve (may start with `/`)
--- @return string The resolved path
--- @usage local resolved = M.resolve_project_path("/config.yml")
--- @usage local resolved = M.resolve_project_path("config.yml")
function M.resolve_project_path(path)
  if M.is_empty(path) then
    return path
  end

  if path:sub(1, 1) == "/" then
    if quarto.project.directory then
      -- Prepend project directory to absolute path
      return quarto.project.directory .. path
    else
      -- Remove leading `/` if no project directory
      return path:sub(2)
    end
  else
    return path
  end
end

-- ============================================================================
-- COLOUR UTILITIES
-- ============================================================================

--- Get colour value from attributes table, accepting both British and American spellings.
--- Checks for 'colour' first (British, primary), then falls back to 'color' (American).
--- @param attrs table Attributes table (kwargs or element.attributes)
--- @param default string|nil Default value if neither spelling is found
--- @return string|nil Colour value or default
--- @usage local colour = M.get_colour(kwargs, 'info')
function M.get_colour(attrs, default)
  if attrs == nil then
    return default
  end
  local value = attrs.colour or attrs.color
  if M.is_empty(value) then
    return default
  end
  return M.stringify(value)
end

--- Check if a colour value is a custom colour (hex, rgb, hsl, etc.).
--- Used to determine whether to apply a semantic class or inline style.
--- @param colour string|nil The colour value to check
--- @return boolean True if it's a custom colour value
--- @usage local is_custom = M.is_custom_colour('#ff6600') -- returns true
function M.is_custom_colour(colour)
  if not colour then return false end
  local str = colour:lower()
  return str:match('^#') or str:match('^rgb') or str:match('^hsl')
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

return M
