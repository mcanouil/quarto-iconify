--- MC Schema Check - Runtime schema checks for Quarto extensions
--- @module "schema-check"
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @version 2.2.0
---
--- Holds the wiring that every extension would otherwise copy: read the schema
--- once, check the document configuration against it, check one shortcode call
--- against it, and report what it finds through `logging`.
---
--- The schema is `_schema.yml` beside the entry point that runs. An extension
--- whose entry points sit in a subdirectory names its own path instead, with
--- `'../_schema.yml'` for one level down.
---
--- The validator arrives as an argument rather than through `require`. A
--- vendored copy of this module then knows nothing about where the validator
--- was vendored, so the two sources stay independent. The validator must
--- provide `load_schema`, `validate`, `validate_shortcode` and
--- `extract_meta_options`.
---
--- Nothing here stops a render. A schema is configuration, and a fault in the
--- configuration must not remove the document.

local M = {}

--- Load a sibling module from the same directory as this file.
--- @param filename string The sibling module filename (e.g., 'string.lua')
--- @return table The loaded module
local function load_sibling(filename)
  local source = debug.getinfo(1, 'S').source:sub(2)
  local dir = source:match('(.*[/\\])') or ''
  return require((dir .. filename):gsub('%.lua$', ''))
end

--- Load required modules
local log = load_sibling('logging.lua')
local str = load_sibling('string.lua')

-- ============================================================================
-- SEVERITY
-- ============================================================================

--- The level each kind of finding is reported at. This is the only place a
--- severity is decided, so a later change to what an extension must correct is
--- a change to this table and nothing else.
---
--- The current policy reports and never stops a render. A finding is a warning,
--- with two exceptions. An unreadable schema is an error, because no check runs
--- after it. A missing required argument is an error, because the shortcode
--- renders nothing without it, which is the one finding that changes the
--- document.
---
--- A rejected document option keeps the error level it has today: it names a
--- value the extension cannot use, and the author has to correct it.
--- @type table<string, string>
local SEVERITY = {
  schema = 'error',
  option_error = 'error',
  option_warning = 'warning',
  call_error = 'warning',
  call_warning = 'warning',
  missing_argument = 'error',
}

--- The reporting function for each level.
--- @type table<string, function>
local REPORTERS = {
  error = log.log_error,
  warning = log.log_warning,
}

-- A level with no reporter is the mistake a change to `SEVERITY` makes, and it
-- is caught here, at load, rather than at the one render that reaches that kind
-- of finding.
for kind, level in pairs(SEVERITY) do
  assert(REPORTERS[level] ~= nil,
    string.format('schema-check: "%s" maps to the unknown level "%s"', kind, tostring(level)))
end

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

--- Read an attribute value with a surrounding quote pair removed.
--- Quarto's body parser strips those quotes before the value reaches the
--- shortcode, but the parser it uses for a text or attribute string hands the
--- raw token over instead, so `aria-hidden='true'` arrives as the five
--- character string `'true'`. Stripping here is what makes a quoted and an
--- unquoted value check as the same thing.
--- @param kwargs table<string, any> Key-value options for the call
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

--- Copy a value, and every table inside it, all the way down.
--- The copy exists so that a caller writing into what it received cannot
--- change what every later reader of the same checker sees.
---
--- The depth comes from the schema format, not from the schemas written so
--- far. The vocabulary allows `type: array` and `type: object`, and the
--- validator compiles a declared `default` by coercing it against that type
--- and returning it untouched once it already matches. Any option declaring a
--- collection type with a literal default therefore resolves to a Lua table,
--- at whatever depth the schema nests it, so a copy one level deep would hand
--- two callers the same inner table and leave the fault one level down.
---
--- A table already copied on this walk is reused rather than copied again,
--- which keeps shared structure shared and makes a cycle terminate. A schema
--- file cannot express a cycle, because the validator's parser refuses anchors
--- and aliases, but the validator is injected and what it returns is not this
--- module's to assume.
--- @param value any The value to copy
--- @param seen table|nil Tables already copied on this walk
--- @return any
local function deep_copy(value, seen)
  if type(value) ~= 'table' then
    return value
  end
  seen = seen or {}
  if seen[value] ~= nil then
    return seen[value]
  end
  --- @type table
  local copy = {}
  seen[value] = copy
  for key, item in pairs(value) do
    copy[key] = deep_copy(item, seen)
  end
  return copy
end

--- Flatten a call's named options to plain strings for the validator.
--- @param kwargs table<string, any> Key-value options for the call
--- @return table<string, string>
local function plain_kwargs(kwargs)
  --- @type table<string, string>
  local plain = {}
  for key in pairs(kwargs) do
    plain[tostring(key)] = attr_value(kwargs, key)
  end
  return plain
end

-- ============================================================================
-- CHECKER
-- ============================================================================

--- @class Checker
--- @field validator table The validator the caller injected
--- @field extension string The extension name every message carries
--- @field schema table|nil The parsed schema, nil when it could not be read
--- @field defaults table<string, any> The defaults the schema declares
--- @field resolved table|nil The three tables the configuration resolves to
--- @field options_checked boolean Whether the configuration was already checked
local Checker = {}
Checker.__index = Checker

--- Report one finding at the level its kind is mapped to.
--- A kind with no entry in `SEVERITY` is a fault in this module, and it says so
--- rather than reporting the finding at a level nobody chose. It is reported
--- rather than raised, because a fault here must not remove a document.
--- @param kind string A key of `SEVERITY`
--- @param message string The message to report
--- @return nil
function Checker:_report(kind, message)
  --- @type string|nil
  local level = SEVERITY[kind]
  if level == nil then
    log.log_error(self.extension, string.format(
      'schema-check has no severity for "%s": %s', tostring(kind), message))
    return
  end
  REPORTERS[level](self.extension, message)
end

--- Check the document configuration and return what it resolves to. The check
--- runs once, so an extension can ask on every shortcode without repeating the
--- messages.
---
--- The defaults come first, because that is what most extensions want, and
--- because the schema is the one place they are written. They come from a
--- second pass over an empty table, which yields the declared defaults alone.
---
--- The second return holds three tables, because they answer different
--- questions:
---   provided  what the document actually set, which is the only way to tell
---             a deliberate `false` or `0` from an absent key,
---   merged    the same values with coercion and defaults applied,
---   defaults  the schema defaults on their own.
--- It is nil when there is nothing to resolve against, so an extension can
--- tell an unreadable schema from a document that set nothing.
---
--- The defaults are a fresh copy on every call, so a caller may treat them as
--- its own. The tables inside the second return are the checker's, and every
--- later reader of the same checker sees them, so they must not be written to.
--- @param meta table<string, any> Document metadata
--- @return table<string, any> defaults A copy of the defaults, empty when there is no schema
--- @return table|nil resolved {provided, merged, defaults}, nil when there is no schema
function Checker:options(meta)
  if self.options_checked then
    return deep_copy(self.defaults), self.resolved
  end
  self.options_checked = true

  --- @type table|nil
  local loaded = self.schema
  -- The validator is injected from an independent source, so the shape of what
  -- it returns is not this module's to assume. `call` makes the same allowance
  -- for `shortcodes` one field over.
  if loaded == nil or next(loaded.options or {}) == nil then
    return deep_copy(self.defaults), self.resolved
  end

  --- @type table<string, any>
  local provided = self.validator.extract_meta_options(meta, self.extension)
  local valid, errors, warnings, merged = self.validator.validate(provided, loaded.options)

  for _, message in ipairs(warnings) do
    self:_report('option_warning', message)
  end
  if not valid then
    for _, message in ipairs(errors) do
      self:_report('option_error', message)
    end
  end

  local _, _, _, defaults = self.validator.validate({}, loaded.options, { unknown = 'ignore' })
  self.defaults = defaults or {}
  self.resolved = { provided = provided, merged = merged, defaults = self.defaults }

  return deep_copy(self.defaults), self.resolved
end

--- Check one shortcode call against its entry in the schema.
--- This reports only. Nothing about the rendered output changes, so an
--- unrecognised attribute is surfaced rather than dropped.
--- @param name string Shortcode name
--- @param args table<integer, any> Positional arguments
--- @param kwargs table<string, any> Key-value options for the call
--- @return nil
function Checker:call(name, args, kwargs)
  --- @type table|nil
  local loaded = self.schema
  if loaded == nil then return end

  --- @type table|nil
  local entry = loaded.shortcodes and loaded.shortcodes[name]
  if entry == nil then return end

  args = args or {}
  kwargs = kwargs or {}

  --- @type table<integer, string>
  local positional = {}
  for index, value in ipairs(args) do
    positional[index] = str.stringify(value)
  end

  local _, errors, warnings = self.validator.validate_shortcode(
    name, positional, plain_kwargs(kwargs), entry)

  for _, message in ipairs(warnings) do
    self:_report('call_warning', message)
  end

  -- A required argument that is absent is read here rather than out of the
  -- validator's findings, because the validator reports a nested argument
  -- fault under one `arguments` entry, which cannot tell a missing argument
  -- from a malformed one.
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
    -- other finding about this call is secondary to there being no output.
    for _, argument in ipairs(missing) do
      --- The example comes from the schema, so that each shortcode carries its
      --- own rather than this message naming one shortcode for all of them.
      --- @type string
      local advice = ''
      local example = type(argument.examples) == 'table' and argument.examples[1] or nil
      if example ~= nil then
        advice = string.format(' For example: {{< %s %s >}}.', name, tostring(example))
      end
      self:_report('missing_argument', string.format(
        'The "%s" shortcode needs its "%s" argument.%s', name, argument.name, advice))
    end
    return
  end

  for _, message in ipairs(errors) do
    self:_report('call_error', message)
  end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Build a checker for one extension, reading its schema once.
--- A schema that cannot be read is reported, and the checker it returns does
--- nothing: `options` gives an empty table and `call` gives no message.
---
--- The path is resolved with `quarto.utils.resolve_path`, which answers
--- relative to the entry point that is running rather than to the extension
--- directory. An entry point in a subdirectory therefore has to say where the
--- schema is, and the checker it builds belongs at file scope, so that the
--- schema is read once for the render and not once for each call.
--- @param validator table The validator, with `load_schema`, `validate`,
---   `validate_shortcode` and `extract_meta_options`
--- @param extension_name string The extension name every message carries
--- @param schema_path string|nil The schema to read, relative to the entry
---   point that is running. Defaults to `_schema.yml`.
--- @return Checker
--- @usage local checker = M.new(validator, 'iconify', '../_schema.yml')
function M.new(validator, extension_name, schema_path)
  --- @type Checker
  local checker = setmetatable({
    validator = validator,
    extension = extension_name,
    schema = nil,
    defaults = {},
    resolved = nil,
    options_checked = false,
  }, Checker)

  -- The default is chosen here rather than in the signature, so a caller that
  -- passes two arguments reads the same file it read before this argument
  -- existed.
  local loaded, err = validator.load_schema(
    quarto.utils.resolve_path(schema_path or '_schema.yml'))
  if err then
    checker:_report('schema', err)
  else
    checker.schema = loaded
  end

  return checker
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

return M
