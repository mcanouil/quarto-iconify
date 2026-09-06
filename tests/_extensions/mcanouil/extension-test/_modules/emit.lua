--- Extension Test - Turning derived values into Quarto source.
---
--- One distinction runs through this module. A document option is a real YAML
--- value, so a boolean is written `true`. A Pandoc attribute always arrives as
--- text, so the same boolean is written `"true"`. Schemas in the wild type the
--- two levels differently for exactly this reason, and collapsing them would
--- emit values the extension's own schema rejects.

local schema = require('schema')

local M = {}

--- Characters that force a YAML scalar to be quoted.
local NEEDS_QUOTE = '[:#{}%[%],&%*!|>\'"%%@`]'

--- Whether a string would parse as something other than a string.
local function looks_typed(value)
  return value:match('^%-?%d+%.?%d*$') ~= nil
    or value == 'true' or value == 'false'
    or value == 'null' or value == '~' or value == ''
    or value:match('^%s') ~= nil or value:match('%s$') ~= nil
end

--- Render a scalar as YAML.
--- @param value any
--- @return string
function M.scalar(value)
  local kind = type(value)
  if kind == 'boolean' then
    return tostring(value)
  elseif kind == 'number' then
    if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
      return string.format('%d', value)
    end
    return tostring(value)
  elseif kind == 'nil' then
    return 'null'
  end
  local text = tostring(value)
  if text:match(NEEDS_QUOTE) or looks_typed(text) then
    return '"' .. text:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
  end
  return text
end

--- Render a value as YAML at a given indentation.
--- @param value any
--- @param indent integer number of spaces
--- @return string
function M.yaml(value, indent)
  indent = indent or 0
  local pad = string.rep(' ', indent)

  if type(value) ~= 'table' then
    return M.scalar(value)
  end

  if #value > 0 then
    local lines = {}
    for _, item in ipairs(value) do
      if type(item) == 'table' then
        lines[#lines + 1] = pad .. '-\n' .. M.yaml(item, indent + 2)
      else
        lines[#lines + 1] = pad .. '- ' .. M.scalar(item)
      end
    end
    return table.concat(lines, '\n')
  end

  local lines = {}
  for _, key in ipairs(schema.key_order(value)) do
    local child = value[key]
    if type(child) == 'table' then
      local nested = M.yaml(child, indent + 2)
      if nested == '' then
        lines[#lines + 1] = pad .. key .. ': {}'
      else
        lines[#lines + 1] = pad .. key .. ':\n' .. nested
      end
    else
      lines[#lines + 1] = pad .. key .. ': ' .. M.scalar(child)
    end
  end
  return table.concat(lines, '\n')
end

--- Render a value as a Pandoc attribute, which is always text.
--- @param value any
--- @return string
function M.attribute_value(value)
  if type(value) == 'table' then
    local parts = {}
    for _, item in ipairs(value) do
      parts[#parts + 1] = tostring(item)
    end
    return table.concat(parts, ' ')
  end
  return tostring(value)
end

--- Render an attribute list, in declaration order.
--- @param attributes table
--- @param order string[]|nil
--- @return string
function M.attributes(attributes, order)
  local parts = {}
  for _, key in ipairs(order or schema.key_order(attributes)) do
    if attributes[key] ~= nil then
      local text = M.attribute_value(attributes[key]):gsub('"', '\\"')
      parts[#parts + 1] = string.format('%s="%s"', key, text)
    end
  end
  return table.concat(parts, ' ')
end

--- Render a shortcode call.
---
--- Emitted inside a paragraph, never inside a code block, where Quarto would
--- not expand it and the surviving-text check would report a false failure.
--- @param name string
--- @param positional any[]
--- @param attributes table|nil
--- @param order string[]|nil attribute order
--- @return string
function M.shortcode(name, positional, attributes, order)
  local parts = { name }
  for _, value in ipairs(positional or {}) do
    local text = M.attribute_value(value)
    if text == '' or text:match('[%s>"]') then
      parts[#parts + 1] = '"' .. text:gsub('"', '\\"') .. '"'
    else
      parts[#parts + 1] = text
    end
  end
  local rendered = M.attributes(attributes or {}, order)
  if rendered ~= '' then
    parts[#parts + 1] = rendered
  end
  return '{{< ' .. table.concat(parts, ' ') .. ' >}}'
end

--- Render a fenced Div carrying classes and attributes.
--- @param classes string[]
--- @param attributes table|nil
--- @param body string
--- @param identifier string|nil
--- @return string
function M.div(classes, attributes, body, identifier)
  local parts = {}
  if identifier then
    parts[#parts + 1] = '#' .. identifier
  end
  for _, class in ipairs(classes or {}) do
    parts[#parts + 1] = '.' .. class
  end
  local rendered = M.attributes(attributes or {})
  if rendered ~= '' then
    parts[#parts + 1] = rendered
  end
  return string.format('::: {%s}\n%s\n:::', table.concat(parts, ' '), body)
end

--- Render a bracketed Span.
--- @param classes string[]
--- @param attributes table|nil
--- @param body string
--- @param identifier string|nil
--- @return string
function M.span(classes, attributes, body, identifier)
  local parts = {}
  if identifier then
    parts[#parts + 1] = '#' .. identifier
  end
  for _, class in ipairs(classes or {}) do
    parts[#parts + 1] = '.' .. class
  end
  local rendered = M.attributes(attributes or {})
  if rendered ~= '' then
    parts[#parts + 1] = rendered
  end
  return string.format('[%s]{%s}', body, table.concat(parts, ' '))
end

--- Assemble a document from front matter and a body.
--- @param front table
--- @param body string[]
--- @param note string
--- @return string
function M.document(front, body, note)
  local lines = { '---' }
  local rendered = M.yaml(front, 0)
  if rendered ~= '' then
    lines[#lines + 1] = rendered
  end
  lines[#lines + 1] = '---'
  lines[#lines + 1] = ''
  -- A generated file found loose in a working tree should explain itself.
  lines[#lines + 1] = '<!-- ' .. note .. ' -->'
  lines[#lines + 1] = ''
  for _, chunk in ipairs(body) do
    lines[#lines + 1] = chunk
    lines[#lines + 1] = ''
  end
  return table.concat(lines, '\n')
end

return M
