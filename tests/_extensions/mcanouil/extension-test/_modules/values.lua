--- Extension Test - Deriving a concrete value from a field descriptor.
---
--- The governing invariant: every value this module hands back has been
--- validated against the descriptor it came from. Candidates are tried in
--- order and the first that validates wins; when none validates the
--- descriptor is undecidable and the caller skips it.
---
--- That one rule is what makes the smoke layer safe to point at schemas this
--- framework has never seen. A smoke failure is then always the extension's
--- fault and never the generator's, because the generator provably never
--- emits a value the extension's own declared contract rejects. It also means
--- the generator and the validator cannot drift, since they are the same code.

local schema = require('schema')

local M = {}

--- Strings tried when a descriptor constrains a value in a way the type
--- default does not satisfy, most often a `pattern`.
---
--- Reversing a regular expression is unsound, so the generator guesses from a
--- fixed corpus and lets the validator decide. A descriptor none of these
--- satisfies is reported as undecidable rather than guessed at.
--- The empty string is deliberately not a probe. The reference validator
--- accepts it against a `pattern` it does not match, treating it as an absent
--- value rather than a failing one, so using it here would let the generator
--- emit a value that satisfies the contract only by that leniency. A
--- descriptor nothing else satisfies is reported undecidable instead.
M.PROBES = {
  'test', 'a', 'x', '1', '10', 'true', 'false', '#336699', '1px', '1rem',
  '100%', '1s', '10ms', 'https://example.com', 'test@example.com',
  '2026-01-01', '2026-01-01T00:00:00Z', 'left', 'center', 'right',
}

--- Strings a `format` or `completion` hint suggests.
local HINTED = {
  uri = 'https://example.com',
  url = 'https://example.com',
  email = 'test@example.com',
  date = '2026-01-01',
  ['date-time'] = '2026-01-01T00:00:00Z',
  time = '00:00:00',
  color = '#336699',
  colour = '#336699',
  size = '1rem',
  directory = 'assets',
}

--- Whether a value satisfies its own descriptor.
--- @param value any
--- @param descriptor table
--- @return boolean
function M.validates(value, descriptor)
  local ok, valid = pcall(schema.validate,
    { probe = value }, { probe = descriptor }, { unknown = 'ignore' })
  return ok and valid == true
end

--- The declared types of a descriptor, always as a list.
--- @param descriptor table
--- @return string[]
local function types_of(descriptor)
  local declared = descriptor.type
  if type(declared) == 'table' then
    return declared
  end
  if declared == nil then
    return {}
  end
  return { declared }
end

--- A number satisfying the descriptor's numeric bounds.
--- @param descriptor table
--- @param integral boolean
--- @return number
local function derive_number(descriptor, integral)
  local value = 1
  if type(descriptor.minimum) == 'number' then
    value = descriptor.minimum
  elseif type(descriptor.exclusiveMinimum) == 'number' then
    value = descriptor.exclusiveMinimum + (integral and 1 or 0.1)
  end
  if type(descriptor.multipleOf) == 'number' and descriptor.multipleOf > 0 then
    local factor = math.ceil(value / descriptor.multipleOf)
    if factor == 0 then
      factor = 1
    end
    value = factor * descriptor.multipleOf
  end
  if type(descriptor.maximum) == 'number' and value > descriptor.maximum then
    value = descriptor.maximum
  elseif type(descriptor.exclusiveMaximum) == 'number' and value >= descriptor.exclusiveMaximum then
    value = descriptor.exclusiveMaximum - (integral and 1 or 0.1)
  end
  if integral then
    value = math.floor(value)
  end
  return value
end

--- A string satisfying the descriptor's length bounds and any hint.
--- @param descriptor table
--- @return string
local function derive_string(descriptor)
  local value = 'test'
  local hint = descriptor.format
  if type(descriptor.completion) == 'table' then
    hint = descriptor.completion.type or hint
    if descriptor.completion.type == 'file' then
      local extensions = descriptor.completion.extensions
      local suffix = (type(extensions) == 'table' and extensions[1]) or '.txt'
      value = 'test' .. suffix
      hint = nil
    end
  end
  if hint and HINTED[hint] then
    value = HINTED[hint]
  end
  local minimum = tonumber(descriptor.minLength)
  local maximum = tonumber(descriptor.maxLength)
  if minimum and #value < minimum then
    value = value .. string.rep('x', minimum - #value)
  end
  if maximum and #value > maximum then
    value = value:sub(1, maximum)
  end
  return value
end

--- Derive a value from a descriptor's declared type.
--- @param descriptor table
--- @param name string one declared type
--- @param depth integer
--- @return any value, boolean ok
local function derive_typed(descriptor, name, depth)
  if depth > 8 then
    return nil, false
  end
  if name == 'string' then
    return derive_string(descriptor), true
  elseif name == 'number' then
    return derive_number(descriptor, false), true
  elseif name == 'integer' then
    return derive_number(descriptor, true), true
  elseif name == 'boolean' then
    return true, true
  elseif name == 'content' then
    return '*test* content', true
  elseif name == 'null' then
    return nil, false
  elseif name == 'array' then
    local count = math.max(tonumber(descriptor.minItems) or 1, 1)
    local items = {}
    if type(descriptor.items) == 'table' then
      local item, ok = M.derive(descriptor.items, depth + 1)
      if not ok then
        return nil, false
      end
      for index = 1, count do
        items[index] = item
      end
    else
      for index = 1, count do
        items[index] = 'test'
      end
    end
    return items, true
  elseif name == 'object' then
    local object = {}
    if type(descriptor.properties) == 'table' then
      for _, key in ipairs(schema.key_order(descriptor.properties)) do
        local child = descriptor.properties[key]
        if type(child) == 'table' then
          local value, ok = M.derive(child, depth + 1)
          if ok then
            object[key] = value
          elseif child.required == true then
            return nil, false
          end
        end
      end
    elseif type(descriptor.additionalProperties) == 'table' then
      local value, ok = M.derive(descriptor.additionalProperties, depth + 1)
      if ok then
        object.key = value
      end
    end
    return object, true
  end
  return nil, false
end

--- Candidate values for a descriptor, in priority order.
--- @param descriptor table
--- @param depth integer
--- @return table[] list of {value, source}
local function candidates(descriptor, depth)
  local list = {}
  local function add(value, source, present)
    if present then
      list[#list + 1] = { value = value, source = source }
    end
  end

  -- A `const` is a hard constraint, so nothing may outrank it.
  add(descriptor.const, 'const', descriptor.const ~= nil)
  add(descriptor.default, 'default', descriptor.default ~= nil)
  if type(descriptor.enum) == 'table' and descriptor.enum[1] ~= nil then
    add(descriptor.enum[1], 'enum', true)
  end
  if type(descriptor.examples) == 'table' and descriptor.examples[1] ~= nil then
    add(descriptor.examples[1], 'example', true)
  end

  for _, name in ipairs(types_of(descriptor)) do
    local value, ok = derive_typed(descriptor, name, depth)
    add(value, 'type:' .. tostring(name), ok)
  end

  -- Last resort for a constraint the type default does not satisfy. Every
  -- probe is still validated, so a wrong guess is discarded rather than
  -- emitted.
  local declared = types_of(descriptor)
  local stringish = #declared == 0
  for _, name in ipairs(declared) do
    if name == 'string' or name == 'content' then
      stringish = true
    end
  end
  if stringish then
    for _, probe in ipairs(M.PROBES) do
      add(probe, 'probe', true)
    end
  end

  return list
end

--- Derive a value for a descriptor.
--- @param descriptor table
--- @param depth integer|nil
--- @return any value
--- @return boolean ok false when the descriptor is undecidable
--- @return string source which candidate won, or the reason it failed
function M.derive(descriptor, depth)
  depth = depth or 0
  if type(descriptor) ~= 'table' then
    return nil, false, 'not-a-descriptor'
  end

  for _, candidate in ipairs(candidates(descriptor, depth)) do
    if M.validates(candidate.value, descriptor) then
      return candidate.value, true, candidate.source
    end
  end

  return nil, false, 'no-value-derivable'
end

--- Every enum value that validates, for a one-factor-at-a-time sweep.
---
--- Capped because a large enum multiplies documents without adding signal,
--- and the cap is reported rather than silently applied.
--- @param descriptor table
--- @param limit integer|nil
--- @return any[] values, boolean capped
function M.enum_values(descriptor, limit)
  limit = limit or 8
  local values = {}
  if type(descriptor.enum) ~= 'table' then
    return values, false
  end
  for _, value in ipairs(descriptor.enum) do
    if #values >= limit then
      return values, true
    end
    if M.validates(value, descriptor) then
      values[#values + 1] = value
    end
  end
  return values, false
end

--- Derive values for a whole descriptor map.
--- @param map table descriptor map
--- @param filter function|nil predicate on (key, descriptor)
--- @return table values, table[] undecidable
function M.derive_map(map, filter)
  local values, undecidable = {}, {}
  for _, key in ipairs(schema.key_order(map or {})) do
    local descriptor = map[key]
    if type(descriptor) == 'table' and (not filter or filter(key, descriptor)) then
      local value, ok, source = M.derive(descriptor)
      if ok then
        values[key] = value
      else
        undecidable[#undecidable + 1] = { key = key, reason = source, pattern = descriptor.pattern }
      end
    end
  end
  return values, undecidable
end

return M
