--[[
# MIT License
#
# Copyright (c) 2025 Mickaël Canouil
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
]]

--- MC Utils - Common utility functions for Quarto Lua filters and shortcodes
--- @module utils
--- @author Mickaël Canouil
--- @version 1.0.0

local utils_module = {}

-- ============================================================================
-- STRING UTILITIES
-- ============================================================================

--- Pandoc utility function for converting values to strings
--- @type function
utils_module.stringify = pandoc.utils.stringify

--- Check if a string is empty or nil.
--- Utility function to determine if a value is empty or nil,
--- which is useful for parameter validation throughout the module.
--- @param s string|nil|table The value to check for emptiness
--- @return boolean True if the value is nil or empty, false otherwise
--- @usage local result = utils_module.is_empty("") -- returns true
--- @usage local result = utils_module.is_empty(nil) -- returns true
--- @usage local result = utils_module.is_empty("hello") -- returns false
function utils_module.is_empty(s)
  return s == nil or s == ''
end

--- Escape special pattern characters in a string for Lua pattern matching
--- @param s string The string to escape
--- @return string The escaped string
--- @usage local escaped = utils_module.escape_pattern("user/repo#123")
function utils_module.escape_pattern(s)
  local escaped = s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return escaped
end

--- Split a string by a separator
--- @param str string The string to split
--- @param sep string The separator pattern
--- @return table Array of string fields
--- @usage local parts = utils_module.split("a.b.c", ".")
function utils_module.split(str, sep)
  local fields = {}
  local pattern = string.format("([^%s]+)", sep)
  str:gsub(pattern, function(c) fields[#fields + 1] = c end)
  return fields
end

--- Escape special LaTeX characters in text.
--- @param text string The text to escape
--- @return string The escaped text safe for LaTeX
function utils_module.escape_latex(text)
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
function utils_module.escape_typst(text)
  text = string.gsub(text, "%#", "\\#")
  return text
end

--- Escape special Lua pattern characters for use in string.gsub.
--- @param text string The text containing characters to escape
--- @return string The escaped text safe for Lua patterns
function utils_module.escape_lua_pattern(text)
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

--- Escape text for different formats.
--- @param text string The text to escape
--- @param format string The format to escape for (e.g., "latex", "typst", "lua")
--- @return string The escaped text
function utils_module.escape_text(text, format)
  local escape_functions = {
    latex = utils_module.escape_latex,
    typst = utils_module.escape_typst,
    lua = utils_module.escape_lua_pattern
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
function utils_module.ascii_id(text)
  local id = text:lower():gsub("[^a-z0-9 ]", ""):gsub(" +", "-")
  return id
end

-- ============================================================================
-- METADATA UTILITIES
-- ============================================================================

--- Extract metadata value from document meta using nested structure
--- Supports the extensions.{extension-name}.{key} pattern
--- @param meta table The document metadata table
--- @param extension_name string The extension name (e.g., "github", "iconify")
--- @param key string The metadata key to retrieve
--- @return string|nil The metadata value as a string, or nil if not found
--- @usage local repo = utils_module.get_metadata_value(meta, "github", "repository-name")
function utils_module.get_metadata_value(meta, extension_name, key)
  if meta['extensions'] and meta['extensions'][extension_name] and meta['extensions'][extension_name][key] then
    return utils_module.stringify(meta['extensions'][extension_name][key])
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
function utils_module.check_deprecated_config(meta, extension_name, key, deprecation_warning_shown)
  -- Handle array-based configuration (when key is nil)
  if key == nil then
    if not utils_module.is_empty(meta[extension_name]) then
      if not deprecation_warning_shown then
        utils_module.log_warning(
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

  -- Handle key-value configuration (original behavior)
  if not utils_module.is_empty(meta[extension_name]) and not utils_module.is_empty(meta[extension_name][key]) then
    if not deprecation_warning_shown then
      utils_module.log_warning(
        extension_name,
        'Top-level "' .. extension_name .. '" configuration is deprecated. ' ..
        'Please use:\n' ..
        'extensions:\n' ..
        '  ' .. extension_name .. ':\n' ..
        '    ' .. key .. ': value'
      )
      deprecation_warning_shown = true
    end
    return utils_module.stringify(meta[extension_name][key]), deprecation_warning_shown
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
function utils_module.create_link(text, uri)
  if not utils_module.is_empty(uri) and not utils_module.is_empty(text) then
    return pandoc.Link({ pandoc.Str(text --[[@as string]]) }, uri --[[@as string]])
  end
  return nil
end

--- Helper to build Pandoc attributes
--- @param id string|nil Element ID
--- @param classes table|nil List of CSS classes
--- @param attributes table|nil Key-value attributes
--- @return pandoc.Attr Pandoc Attr object
function utils_module.attr(id, classes, attributes)
  return pandoc.Attr(id or '', classes or {}, attributes or {})
end

--- Check if a class list contains a specific class name
--- @param classes table|nil List of CSS classes
--- @param name string The class name to search for
--- @return boolean True if the class is found, false otherwise
function utils_module.has_class(classes, name)
  if not classes then return false end
  for _, cls in ipairs(classes) do
    if cls == name then return true end
  end
  return false
end

--- Add a class to the class list if it doesn't already exist
--- @param classes table List of CSS classes
--- @param name string The class name to add
function utils_module.add_class(classes, name)
  if not utils_module.has_class(classes, name) then
    classes:insert(name)
  end
end

--- Retrieve the current Quarto output format.
--- @return string The output format ("pptx", "html", "latex", "typst", "docx", or "unknown")
--- @return string The language of the output format
function utils_module.get_quarto_format()
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
function utils_module.is_object_empty(obj)
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
function utils_module.is_type_simple(obj)
  return pandoc.utils.type(obj) == "string" or pandoc.utils.type(obj) == "number" or pandoc.utils.type(obj) == "boolean"
end

--- Check if an object is a function or userdata
--- @param obj any The object to check
--- @return boolean true if the object is a function or userdata
function utils_module.is_function_userdata(obj)
  return pandoc.utils.type(obj) == "function" or pandoc.utils.type(obj) == "userdata"
end

--- Get nested value from object using field path
--- @param fields table Array of field names to traverse
--- @param obj table The object to extract value from
--- @return any The value at the nested path
--- @usage local val = utils_module.get_value({"a", "b", "c"}, obj)
function utils_module.get_value(fields, obj)
  local value = obj
  for _, field in ipairs(fields) do
    value = value[field]
  end
  return value
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
function utils_module.raw_header(level, text, id, classes, attributes)
  local attr_str = ''
  if id and id ~= '' then attr_str = attr_str .. ' id="' .. id .. '"' end
  if classes and #classes > 0 then attr_str = attr_str .. ' class="' .. table.concat(classes, ' ') .. '"' end
  if attributes then
    for k, v in pairs(attributes) do
      attr_str = attr_str .. ' ' .. k .. '="' .. v .. '"'
    end
  end
  return string.format('<h%d%s>%s</h%d>', level, attr_str, text or '', level)
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
--- @usage utils_module.ensure_html_dependency({name = 'my-lib', version = '1.0.0', scripts = {'lib.js'}})
function utils_module.ensure_html_dependency(config)
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
function utils_module.reset_dependencies()
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
--- @usage local duration = utils_module.get_option_with_fallbacks({extension = 'animate', key = 'duration', args = kwargs, meta = meta, default = '3s'})
function utils_module.get_option_with_fallbacks(spec)
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
    local arg_value = utils_module.stringify(args[key])
    if not utils_module.is_empty(arg_value) then
      return arg_value
    end
  end

  -- Priority 2: Check metadata extensions.{extension}.{key}
  if meta then
    local meta_value = utils_module.get_metadata_value(meta, extension, key)
    if not utils_module.is_empty(meta_value) then
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
--- @usage local opts = utils_module.get_options({extension = 'animate', keys = {'duration', 'delay'}, args = kwargs, meta = meta, defaults = {duration = '3s', delay = '2s'}})
function utils_module.get_options(spec)
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
    result[key] = utils_module.get_option_with_fallbacks({
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
--- @usage utils_module.log_error("external", "Could not open file 'example.md'.")
function utils_module.log_error(extension_name, message)
  quarto.log.error("[" .. extension_name .. "] " .. message)
end

--- Format and log a warning message with extension prefix.
--- Provides standardised warning messages with consistent formatting across extensions.
--- Format: [extension-name] Message with details.
---
--- @param extension_name string The name of the extension (e.g., "external", "lua-env")
--- @param message string The warning message to display
--- @usage utils_module.log_warning("lua-env", "No variable name provided.")
function utils_module.log_warning(extension_name, message)
  quarto.log.warning("[" .. extension_name .. "] " .. message)
end

--- Format and log an output message with extension prefix.
--- Provides standardised informational messages with consistent formatting across extensions.
--- Format: [extension-name] Message with details.
---
--- @param extension_name string The name of the extension (e.g., "lua-env")
--- @param message string The informational message to display
--- @usage utils_module.log_output("lua-env", "Exported metadata to: output.json")
function utils_module.log_output(extension_name, message)
  quarto.log.output("[" .. extension_name .. "] " .. message)
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

return utils_module
