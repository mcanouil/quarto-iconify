--- MC Schema - Schema loading, validation, and formatting for Quarto extensions
--- @module schema
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @version 1.0.0

local M = {}

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

--- Normalise a key by replacing hyphens with underscores.
--- @param key string Key to normalise
--- @return string Normalised key
local function _normalise_key(key)
  return (key:gsub('-', '_'))
end

--- Convert a pandoc metadata value to a native Lua value.
--- Handles strings, numbers, booleans, pandoc Inlines/Blocks, and tables.
---
--- @param value any Pandoc metadata value
--- @return any Native Lua value
local function _convert_pandoc_value(value)
  if type(value) == 'string' then
    return value
  elseif type(value) == 'number' then
    return value
  elseif type(value) == 'boolean' then
    return value
  elseif value == nil then
    return nil
  end

  -- Handle pandoc Inlines or Blocks containers
  if value.t == 'Inlines' or value.t == 'Blocks' then
    local result = {}
    for _, item in ipairs(value) do
      table.insert(result, _convert_pandoc_value(item))
    end
    return result
  end

  -- Handle pandoc elements with a type tag (stringify them)
  if value.t then
    return pandoc.utils.stringify(value)
  end

  -- Handle regular tables (arrays and maps)
  if type(value) == 'table' then
    local result = {}
    for k, v in pairs(value) do
      result[k] = _convert_pandoc_value(v)
    end
    return result
  end

  return value
end

--- Recursively convert a parsed schema table, normalising all keys.
--- Applies hyphen-to-underscore normalisation at every nesting level.
---
--- @param raw_schema table Raw schema from YAML parsing
--- @param depth number|nil Current recursion depth (default 0)
--- @return table Converted schema with normalised keys
local function _convert_schema(raw_schema, depth)
  depth = depth or 0
  if depth > 10 then
    return raw_schema
  end

  local schema = {}
  for key, value in pairs(raw_schema) do
    local normalised_key = _normalise_key(tostring(key))
    if type(value) == 'table' then
      local pandoc_type = pandoc.utils.type(value)

      -- MetaInlines/MetaBlocks are leaf text values, not containers
      if pandoc_type == 'Inlines' or pandoc_type == 'Blocks' then
        schema[normalised_key] = pandoc.utils.stringify(value)
      elseif pandoc_type == 'List' then
        -- MetaList: process as a true array
        local arr = {}
        for i = 1, #value do
          local elem = value[i]
          local elem_type = type(elem) == 'table' and pandoc.utils.type(elem) or nil
          if elem_type == 'Inlines' or elem_type == 'Blocks' then
            arr[i] = pandoc.utils.stringify(elem)
          elseif type(elem) == 'table' and (elem_type == 'table' or elem_type == nil) then
            arr[i] = _convert_schema(elem, depth + 1)
          else
            arr[i] = _convert_pandoc_value(elem)
          end
        end
        schema[normalised_key] = arr
      else
        -- MetaMap or plain table: check if array-like
        local is_array = false
        local length = #value
        if length > 0 then
          is_array = true
          for i = 1, length do
            if value[i] == nil then
              is_array = false
              break
            end
          end
        end

        if is_array then
          local arr = {}
          for i = 1, length do
            local elem = value[i]
            if type(elem) == 'table' then
              arr[i] = _convert_schema(elem, depth + 1)
            else
              arr[i] = _convert_pandoc_value(elem)
            end
          end
          schema[normalised_key] = arr
        else
          schema[normalised_key] = _convert_schema(value, depth + 1)
        end
      end
    else
      schema[normalised_key] = _convert_pandoc_value(value)
    end
  end

  return schema
end

--- Parse a YAML file using pandoc and return a native Lua table.
---
--- @param filename string Path to the YAML file
--- @return table Parsed and converted Lua table
local function _parse_yaml(filename)
  local file_handle = io.open(filename, 'r')
  if not file_handle then
    error(string.format('Could not open schema file: %s', filename))
  end

  local content = file_handle:read('*a')
  file_handle:close()

  -- Wrap as YAML front matter for Pandoc versions that lack the 'yaml' input format
  local meta = pandoc.read('---\n' .. content .. '\n---\n', 'markdown').meta
  if not meta then
    error(string.format('Invalid YAML in schema file: %s', filename))
  end

  return _convert_schema(meta)
end

--- Translate a JS regex pattern to a Lua pattern.
--- Supports common constructs; logs a warning and returns nil for unsupported features.
---
--- @param regex string JS regex pattern
--- @return string|nil Lua pattern, or nil if translation is not possible
local function _js_regex_to_lua_pattern(regex)
  -- Check for unsupported JS regex features
  -- Alternation (unescaped pipe)
  local i = 1
  while i <= #regex do
    local ch = regex:sub(i, i)
    if ch == '\\' then
      i = i + 2
    elseif ch == '|' then
      quarto.log.warning(
        string.format('Unsupported JS regex feature "|" in pattern: %s', regex)
      )
      return nil
    else
      i = i + 1
    end
  end

  -- Lookahead (?=), (?!), (?<=), (?<!)
  if regex:match('%(%?[=!<]') then
    quarto.log.warning(
      string.format('Unsupported JS regex lookahead/lookbehind in pattern: %s', regex)
    )
    return nil
  end

  -- Backreferences \1 through \9
  if regex:match('\\[1-9]') then
    quarto.log.warning(
      string.format('Unsupported JS regex backreference in pattern: %s', regex)
    )
    return nil
  end

  -- Non-greedy quantifiers *?, +?, ??
  if regex:match('[%*%+%?]%?') then
    quarto.log.warning(
      string.format('Unsupported JS regex non-greedy quantifier in pattern: %s', regex)
    )
    return nil
  end

  -- Counted quantifiers {n}, {n,}, {n,m}
  if regex:match('[^\\]{%d') then
    quarto.log.warning(
      string.format('Unsupported JS regex counted quantifier {n,m} in pattern: %s', regex)
    )
    return nil
  end

  -- Perform substitutions for supported constructs
  local result = {}
  local pos = 1
  local len = #regex

  while pos <= len do
    local ch = regex:sub(pos, pos)

    if ch == '\\' and pos < len then
      local next_ch = regex:sub(pos + 1, pos + 1)
      if next_ch == 'd' then
        table.insert(result, '%d')
      elseif next_ch == 'D' then
        table.insert(result, '%D')
      elseif next_ch == 'w' then
        table.insert(result, '[%w_]')
      elseif next_ch == 'W' then
        table.insert(result, '[^%w_]')
      elseif next_ch == 's' then
        table.insert(result, '%s')
      elseif next_ch == 'S' then
        table.insert(result, '%S')
      elseif next_ch == '.' then
        table.insert(result, '%.')
      elseif next_ch == '(' then
        table.insert(result, '%(')
      elseif next_ch == ')' then
        table.insert(result, '%)')
      elseif next_ch == '[' then
        table.insert(result, '%[')
      elseif next_ch == ']' then
        table.insert(result, '%]')
      elseif next_ch == '{' then
        table.insert(result, '%{')
      elseif next_ch == '}' then
        table.insert(result, '%}')
      elseif next_ch == '+' then
        table.insert(result, '%+')
      elseif next_ch == '*' then
        table.insert(result, '%*')
      elseif next_ch == '?' then
        table.insert(result, '%?')
      elseif next_ch == '^' then
        table.insert(result, '%^')
      elseif next_ch == '$' then
        table.insert(result, '%$')
      elseif next_ch == '\\' then
        table.insert(result, '%%')
      else
        -- Unknown escape, pass through with Lua escape
        table.insert(result, '%' .. next_ch)
      end
      pos = pos + 2
    elseif ch == '\\' then
      -- Trailing backslash at end of string; treat as literal
      table.insert(result, '%%')
      pos = pos + 1
    elseif ch == '.' then
      -- Unescaped dot matches any character (except newline in JS)
      table.insert(result, '.')
      pos = pos + 1
    else
      table.insert(result, ch)
      pos = pos + 1
    end
  end

  return table.concat(result)
end

-- ============================================================================
-- PRIVATE VALIDATORS
-- ============================================================================

--- Validate that a value matches an expected type.
--- Supports: string, number, boolean, table, array, content.
---
--- @param value any Value to validate
--- @param expected_type string Expected type name
--- @return boolean True if value matches the expected type
--- Check whether a type spec (string or array of strings) includes the given type name.
--- @param type_spec string|table Type spec to check
--- @param name string Type name to look for
--- @return boolean True if the type spec includes the given name
local function _type_includes(type_spec, name)
  if type(type_spec) == 'table' then
    for _, t in ipairs(type_spec) do
      if t == name then
        return true
      end
    end
    return false
  end
  return type_spec == name
end

--- Format a type spec for display in error messages.
--- @param type_spec string|table Type spec to format
--- @return string Human-readable type string
local function _format_type(type_spec)
  if type(type_spec) == 'table' then
    return table.concat(type_spec, ' | ')
  end
  return tostring(type_spec)
end

local function _validate_type(value, expected_type)
  if type(expected_type) ~= 'string' then
    return false
  end

  if expected_type == 'content' then
    -- Content type accepts pandoc Inlines, Blocks, or string.
    -- Only presence matters (checked by required); accept anything non-nil.
    return value ~= nil
  end

  if expected_type == 'array' then
    if type(value) ~= 'table' then
      return false
    end
    local length = #value
    if length == 0 then
      return true
    end
    for i = 1, length do
      if value[i] == nil then
        return false
      end
    end
    return true
  end

  if expected_type == 'object' then
    return type(value) == 'table'
  end

  return type(value) == expected_type
end

--- Validate value against a type spec (string or array of strings).
--- Returns true if value matches any of the listed types.
--- @param value any Value to validate
--- @param type_spec string|table Expected type name or array of type names
--- @return boolean True if value matches any listed type
local function _validate_type_spec(value, type_spec)
  if type(type_spec) == 'table' then
    for _, t in ipairs(type_spec) do
      if _validate_type(value, t) then
        return true
      end
    end
    return false
  end
  return _validate_type(value, type_spec)
end

--- Validate that a value is one of the allowed enumerated values.
---
--- @param value any Value to validate
--- @param allowed_values table Array of allowed values
--- @param case_insensitive boolean|nil Case-insensitive comparison for strings
--- @return boolean True if value is in the allowed set
local function _validate_enum(value, allowed_values, case_insensitive)
  if not case_insensitive then
    for _, allowed in ipairs(allowed_values) do
      if value == allowed then
        return true
      end
    end
  else
    if type(value) == 'string' then
      local lower_value = value:lower()
      for _, allowed in ipairs(allowed_values) do
        if type(allowed) == 'string' and lower_value == allowed:lower() then
          return true
        end
      end
    end
  end
  return false
end

--- Validate that a string matches a pattern.
--- Translates the pattern from JS regex syntax first.
---
--- @param value string Value to validate
--- @param pattern string JS regex or exact string
--- @param exact boolean|nil If true, use exact string match
--- @return boolean True if value matches
local function _validate_pattern(value, pattern, exact)
  if exact then
    return value == pattern
  end

  local lua_pattern = _js_regex_to_lua_pattern(pattern)
  if lua_pattern == nil then
    -- Unsupported pattern; skip validation (accept any value)
    return true
  end

  local success, result = pcall(function()
    return value:match(lua_pattern) ~= nil
  end)
  return success and result or false
end

--- Validate that a number falls within a range.
---
--- @param value any Value to validate (non-numbers return false)
--- @param min any Minimum (inclusive), or nil for no lower bound
--- @param max any Maximum (inclusive), or nil for no upper bound
--- @return boolean True if value is within bounds
local function _validate_range(value, min, max)
  if type(value) ~= 'number' then
    return false
  end
  if min ~= nil and value < min then
    return false
  end
  if max ~= nil and value > max then
    return false
  end
  return true
end

--- Validate array length.
---
--- @param value table Array to validate
--- @param min_length integer|nil Minimum length (inclusive)
--- @param max_length integer|nil Maximum length (inclusive)
--- @return boolean True if length is within bounds
local function _validate_array_length(value, min_length, max_length)
  if type(value) ~= 'table' then
    return false
  end
  local length = #value
  if min_length ~= nil and length < min_length then
    return false
  end
  if max_length ~= nil and length > max_length then
    return false
  end
  return true
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Load and parse a schema file, returning a structured table.
--- The returned table contains keys: options, shortcodes, formats, projects,
--- element_attributes. Each key defaults to an empty table if absent.
---
--- @param filename string|nil Path to schema file (defaults to '_schema.yml')
--- @return table Schema with sections {options, shortcodes, formats, projects, element_attributes}
--- @usage local schema = M.load_schema('_schema.yml')
function M.load_schema(filename)
  local raw = _parse_yaml(filename or '_schema.yml')
  return {
    options = raw.options or {},
    shortcodes = raw.shortcodes or {},
    formats = raw.formats or {},
    projects = raw.projects or {},
    element_attributes = raw.element_attributes or {},
  }
end

--- Extract extension options from document metadata as a plain Lua table.
--- Reads from meta['extensions'][extension_name] and converts Pandoc MetaValues
--- to native Lua values with normalised (underscore) keys.
---
--- @param meta table Document metadata
--- @param extension_name string Extension name (e.g., 'collapse-output')
--- @return table Plain Lua table of option key-value pairs
function M.extract_meta_options(meta, extension_name)
  local ext_meta = meta['extensions'] and meta['extensions'][extension_name]
  if not ext_meta then return {} end

  local options = {}
  for key, value in pairs(ext_meta) do
    local normalised_key = _normalise_key(tostring(key))
    options[normalised_key] = _convert_pandoc_value(value)
  end
  return options
end

--- Validate extension options from document metadata.
--- Loads the schema, extracts options, validates, and logs errors/warnings.
---
--- @param meta table Document metadata
--- @param extension_name string Extension name
--- @param schema_path string Path to the schema file (caller must resolve)
--- @return table merged Validated options with defaults and normalisations applied
function M.validate_options(meta, extension_name, schema_path)
  local schema_data = M.load_schema(schema_path)

  if not schema_data.options or next(schema_data.options) == nil then
    return {}
  end

  local raw_options = M.extract_meta_options(meta, extension_name)
  local valid, errors, warnings, merged = M.validate(raw_options, schema_data.options)

  if #warnings > 0 then
    quarto.log.warning(M.format_warnings(warnings, extension_name))
  end
  if not valid then
    quarto.log.error(M.format_errors(errors, extension_name))
  end

  return merged
end

--- Validate a map of options against a field descriptor map.
--- Handles type checking, required fields, defaults, enums (with case-insensitive
--- support), patterns (with JS-to-Lua translation), ranges, array lengths, nested
--- items/properties, aliases, deprecation (with auto-forwarding), boolean
--- normalisation, and custom validation functions.
---
--- @param options table Options map to validate
--- @param schema table Field descriptor map
--- @return boolean valid True if all validations pass
--- @return table errors Array of error message strings
--- @return table warnings Array of warning message strings
--- @return table merged Options with defaults, aliases, and deprecation applied
--- @usage local valid, errors, warnings, merged = M.validate(options, schema)
function M.validate(options, schema)
  local errors = {}
  local warnings = {}
  local merged = {}

  -- Copy provided options into merged
  for k, v in pairs(options) do
    merged[k] = v
  end

  for field_name, spec in pairs(schema) do
    -- Alias resolution: if primary key is nil, check aliases
    if spec.aliases then
      for _, alias in ipairs(spec.aliases) do
        local normalised_alias = _normalise_key(alias)
        if merged[field_name] == nil and merged[normalised_alias] ~= nil then
          merged[field_name] = merged[normalised_alias]
          break
        end
      end
    end

    local value = merged[field_name]

    -- Boolean normalisation for type that includes boolean
    if _type_includes(spec.type, 'boolean') and type(value) == 'string' then
      local lower = value:lower()
      if lower == 'true' or lower == 'yes' then
        value = true
        merged[field_name] = true
      elseif lower == 'false' or lower == 'no' then
        value = false
        merged[field_name] = false
      end
    end

    -- Number normalisation for type that includes number
    if _type_includes(spec.type, 'number') and type(value) == 'string' then
      local num = tonumber(value)
      if num then
        value = num
        merged[field_name] = num
      end
    end

    -- Deprecation handling
    if spec.deprecated and value ~= nil and value ~= '' then
      if type(spec.deprecated) == 'table' then
        local msg = string.format('Option "%s" is deprecated.', field_name)
        if spec.deprecated.since then
          msg = string.format('Option "%s" is deprecated since %s.', field_name, spec.deprecated.since)
        end
        if spec.deprecated.message then
          msg = msg .. ' ' .. spec.deprecated.message
        end
        if spec.deprecated.replace_with then
          local replacement = _normalise_key(spec.deprecated.replace_with)
          msg = msg .. string.format(' Use "%s" instead.', replacement)
          -- Auto-forward value to replacement key if replacement is nil
          if merged[replacement] == nil then
            merged[replacement] = value
          end
          -- Remove deprecated key from merged
          merged[field_name] = nil
        end
        table.insert(warnings, msg)
      elseif type(spec.deprecated) == 'string' then
        table.insert(warnings, string.format('Option "%s" is deprecated. %s', field_name, spec.deprecated))
      else
        table.insert(warnings, string.format('Option "%s" is deprecated.', field_name))
      end
    end

    -- Re-read value after deprecation may have cleared it
    value = merged[field_name]

    -- Apply default if value is empty
    if (value == nil or value == '') and spec.default ~= nil then
      value = spec.default
      merged[field_name] = value
    end

    local is_empty = value == nil or value == ''

    -- Required check
    if spec.required and is_empty then
      table.insert(errors, string.format(
        'Option "%s" is required but was not provided.',
        field_name
      ))
    elseif not is_empty then
      -- Content type: only presence matters, skip further checks
      if _type_includes(spec.type, 'content') then
        -- No further validation for content type
      else
        -- Type validation
        if spec.type and not _validate_type_spec(value, spec.type) then
          table.insert(errors, string.format(
            'Option "%s" must be of type "%s", got "%s".',
            field_name, _format_type(spec.type), type(value)
          ))
        else
          -- Enum validation
          if spec.enum and not _validate_enum(value, spec.enum, spec.enum_case_insensitive) then
            table.insert(errors, string.format(
              'Option "%s" must be one of: %s.',
              field_name, table.concat(spec.enum, ', ')
            ))
          end

          -- Pattern validation
          if spec.pattern and type(value) == 'string' then
            if not _validate_pattern(value, spec.pattern, spec.pattern_exact) then
              table.insert(errors, string.format(
                'Option "%s" does not match required pattern: %s.',
                field_name, spec.pattern
              ))
            end
          end

          -- Range validation
          if (spec.min ~= nil or spec.max ~= nil) and not _validate_range(value, spec.min, spec.max) then
            table.insert(errors, string.format(
              'Option "%s" must be between %s and %s, got %s.',
              field_name,
              tostring(spec.min or 'any'),
              tostring(spec.max or 'any'),
              tostring(value)
            ))
          end

          -- Array length validation
          if (spec.min_length ~= nil or spec.max_length ~= nil)
            and not _validate_array_length(value, spec.min_length, spec.max_length) then
            table.insert(errors, string.format(
              'Option "%s" array length must be between %s and %s, got %d.',
              field_name,
              tostring(spec.min_length or 'any'),
              tostring(spec.max_length or 'any'),
              #value
            ))
          end

          -- Nested array items validation
          if _type_includes(spec.type, 'array') and spec.items and type(value) == 'table' then
            for idx, elem in ipairs(value) do
              local item_schema = { [field_name .. '[' .. idx .. ']'] = spec.items }
              local item_valid, item_errors, item_warnings = M.validate(
                { [field_name .. '[' .. idx .. ']'] = elem },
                item_schema
              )
              if not item_valid then
                for _, err in ipairs(item_errors) do
                  table.insert(errors, err)
                end
              end
              for _, warn in ipairs(item_warnings) do
                table.insert(warnings, warn)
              end
            end
          end

          -- Nested object properties validation
          if _type_includes(spec.type, 'object') and spec.properties and type(value) == 'table' then
            local sub_valid, sub_errors, sub_warnings, sub_merged = M.validate(value, spec.properties)
            if not sub_valid then
              for _, err in ipairs(sub_errors) do
                table.insert(errors, field_name .. '.' .. err)
              end
            end
            for _, warn in ipairs(sub_warnings) do
              table.insert(warnings, warn)
            end
            merged[field_name] = sub_merged
          end

          -- Custom validation (run after all other checks pass on this field)
          if spec.custom and type(spec.custom) == 'function' then
            local custom_valid, custom_error = spec.custom(value)
            if not custom_valid then
              table.insert(errors, string.format(
                'Option "%s" failed custom validation: %s.',
                field_name, custom_error or 'invalid value'
              ))
            end
          end
        end
      end
    end
  end

  return #errors == 0, errors, warnings, merged
end

--- Validate shortcode positional arguments against an argument descriptor array.
--- Each descriptor must have a `name` field. The returned `merged` table is
--- keyed by argument name rather than by position.
---
--- @param args table Array of positional argument values
--- @param argument_specs table Array of argument descriptors ({name, type, required, ...})
--- @return boolean valid True if all validations pass
--- @return table errors Array of error message strings
--- @return table warnings Array of warning message strings
--- @return table merged Map keyed by argument name
--- @usage local valid, errors, warnings, merged = M.validate_arguments(args, specs)
function M.validate_arguments(args, argument_specs)
  local errors = {}
  local warnings = {}
  local merged = {}

  for idx, spec in ipairs(argument_specs) do
    local value = args[idx]
    local name = spec.name or tostring(idx)

    -- Boolean normalisation
    if _type_includes(spec.type, 'boolean') and type(value) == 'string' then
      local lower = value:lower()
      if lower == 'true' or lower == 'yes' then
        value = true
      elseif lower == 'false' or lower == 'no' then
        value = false
      end
    end

    -- Number normalisation for type that includes number
    if _type_includes(spec.type, 'number') and type(value) == 'string' then
      local num = tonumber(value)
      if num then
        value = num
      end
    end

    -- Apply default
    if (value == nil or value == '') and spec.default ~= nil then
      value = spec.default
    end

    merged[name] = value

    local is_empty = value == nil or value == ''

    if spec.required and is_empty then
      table.insert(errors, string.format(
        'Argument "%s" (position %d) is required but was not provided.',
        name, idx
      ))
    elseif not is_empty and not _type_includes(spec.type, 'content') then
      if spec.type and not _validate_type_spec(value, spec.type) then
        table.insert(errors, string.format(
          'Argument "%s" (position %d) must be of type "%s", got "%s".',
          name, idx, _format_type(spec.type), type(value)
        ))
      else
        if spec.enum and not _validate_enum(value, spec.enum, spec.enum_case_insensitive) then
          table.insert(errors, string.format(
            'Argument "%s" (position %d) must be one of: %s.',
            name, idx, table.concat(spec.enum, ', ')
          ))
        end

        if spec.pattern and type(value) == 'string' then
          if not _validate_pattern(value, spec.pattern, spec.pattern_exact) then
            table.insert(errors, string.format(
              'Argument "%s" (position %d) does not match required pattern: %s.',
              name, idx, spec.pattern
            ))
          end
        end

        if (spec.min ~= nil or spec.max ~= nil) and not _validate_range(value, spec.min, spec.max) then
          table.insert(errors, string.format(
            'Argument "%s" (position %d) must be between %s and %s, got %s.',
            name, idx,
            tostring(spec.min or 'any'),
            tostring(spec.max or 'any'),
            tostring(value)
          ))
        end

        if spec.custom and type(spec.custom) == 'function' then
          local custom_valid, custom_error = spec.custom(value)
          if not custom_valid then
            table.insert(errors, string.format(
              'Argument "%s" (position %d) failed custom validation: %s.',
              name, idx, custom_error or 'invalid value'
            ))
          end
        end
      end
    end
  end

  -- Warn about extra arguments beyond the spec
  if #args > #argument_specs then
    table.insert(warnings, string.format(
      'Received %d arguments but only %d are defined. Extra arguments will be ignored.',
      #args, #argument_specs
    ))
  end

  return #errors == 0, errors, warnings, merged
end

--- Format an array of error messages as a readable string.
---
--- @param errors table Array of error message strings
--- @param extension_name string|nil Extension name for context
--- @return string Formatted error message, or empty string if no errors
--- @usage local msg = M.format_errors(errors, 'my-extension')
function M.format_errors(errors, extension_name)
  if #errors == 0 then
    return ''
  end

  local prefix = extension_name and ('Extension "' .. extension_name .. '": ') or ''
  local header = prefix .. 'Configuration validation failed:'
  local lines = {}

  for i, err in ipairs(errors) do
    table.insert(lines, '  ' .. i .. '. ' .. err)
  end

  return header .. '\n' .. table.concat(lines, '\n')
end

--- Format an array of warning messages as a readable string.
---
--- @param warnings table Array of warning message strings
--- @param extension_name string|nil Extension name for context
--- @return string Formatted warning message, or empty string if no warnings
--- @usage local msg = M.format_warnings(warnings, 'my-extension')
function M.format_warnings(warnings, extension_name)
  if #warnings == 0 then
    return ''
  end

  local prefix = extension_name and ('Extension "' .. extension_name .. '": ') or ''
  local header = prefix .. 'Configuration warnings:'
  local lines = {}

  for i, warn in ipairs(warnings) do
    table.insert(lines, '  ' .. i .. '. ' .. warn)
  end

  return header .. '\n' .. table.concat(lines, '\n')
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

return M
