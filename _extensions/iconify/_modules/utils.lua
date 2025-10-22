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
  str:gsub(pattern, function(c) fields[#fields+1] = c end)
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
--- @param key string The configuration key being accessed
--- @param deprecation_warning_shown boolean Flag to track if warning has been shown
--- @return string|nil The value from deprecated config, or nil if not found
--- @return boolean Updated deprecation warning flag
function utils_module.check_deprecated_config(meta, extension_name, key, deprecation_warning_shown)
  if not utils_module.is_empty(meta[extension_name]) and not utils_module.is_empty(meta[extension_name][key]) then
    if not deprecation_warning_shown then
      quarto.log.warning(
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
    return pandoc.Link({pandoc.Str(text --[[@as string]])}, uri --[[@as string]])
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
-- MODULE EXPORT
-- ============================================================================

return utils_module
