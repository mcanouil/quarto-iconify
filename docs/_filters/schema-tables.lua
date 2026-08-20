--- @module schema-tables
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
---
--- Builds the reference tables from the extension `_schema.yml`, which is the
--- single source of truth for every option this extension accepts and every
--- default it applies. The reference page marks where each table belongs and
--- this filter fills it in, so a default cannot be right in the schema and
--- wrong on the page.
---
--- The page marks a table with an empty div:
---
---     ::: {.schema-table table="document"}
---     :::
---
--- `table` takes `document`, `typst` or `attributes`.
---
--- This runs as a filter rather than as a pre-render step because Quarto
--- resolves an `{{< include >}}` while it scans the project, before any
--- pre-render script runs, so a generated partial does not exist yet. A filter
--- runs during Pandoc, which is late enough. The same ordering is why
--- sync-extension.sh exists; see _quarto.yml.

--- Locate this filter, so the schema is found relative to it rather than to
--- whatever directory Quarto happens to run Pandoc from.
local source = debug.getinfo(1, 'S').source:sub(2)
local filter_dir = source:match('(.*[/\\])') or './'
local root_dir = filter_dir .. '../../'

local schema_path = root_dir .. '_extensions/iconify/_schema.yml'

--- Loaded with `dofile` rather than `require`, because `require` reads a
--- module name and turns every `.` in it into a directory separator, which
--- destroys the `../..` this relative path needs.
local ok, schema = pcall(dofile, root_dir .. '_extensions/iconify/_modules/schema.lua')
if not ok or type(schema) ~= 'table' then
  io.stderr:write('[schema-tables] could not load the schema module: ' .. tostring(schema) .. '\n')
  return {}
end

local loaded, load_error = schema.load_schema(schema_path)
if load_error then
  io.stderr:write('[schema-tables] ' .. load_error .. '\n')
  return {}
end

--- Validating an empty configuration yields the declared defaults alone.
local _, _, _, defaults = schema.validate({}, loaded.options, { unknown = 'ignore' })

--- Escape the characters that would break out of a Markdown table cell.
--- @param text any
--- @return string
local function cell(text)
  return (tostring(text or ''):gsub('|', '\\|'))
end

--- Render a default for the Default column, in code style.
--- @param value any
--- @return string
local function default_cell(value)
  if value == nil then
    return ''
  end
  return '`' .. tostring(value) .. '`'
end

--- Build a Markdown table.
--- @param header table Column titles
--- @param rows table Array of row arrays
--- @param caption string Table caption, without its leading colon
--- @param widths string Quarto table attributes
--- @return string
local function table_markdown(header, rows, caption, widths)
  local out = {}
  out[#out + 1] = '| ' .. table.concat(header, ' | ') .. ' |'

  local rule = {}
  for _ = 1, #header do
    rule[#rule + 1] = '---'
  end
  out[#out + 1] = '| ' .. table.concat(rule, ' | ') .. ' |'

  for _, row in ipairs(rows) do
    out[#out + 1] = '| ' .. table.concat(row, ' | ') .. ' |'
  end

  out[#out + 1] = ''
  out[#out + 1] = ': ' .. caption .. ' ' .. widths
  return table.concat(out, '\n')
end

--- Build the document options table, or the Typst one.
--- Options are split by the `typst-` prefix. The v2 field descriptor sets
--- `additionalProperties: false`, so an annotation such as `x-group` would
--- make the schema invalid against its own meta-schema.
--- @param typst boolean Whether to take the `typst-` prefixed options
--- @return string
local function options_table(typst)
  local rows = {}
  for _, name in ipairs(schema.key_order(loaded.options)) do
    if (name:sub(1, 6) == 'typst-') == typst then
      rows[#rows + 1] = {
        '`' .. name .. '`',
        default_cell(defaults[name]),
        cell(loaded.options[name].description),
      }
    end
  end

  if typst then
    return table_markdown(
      { 'Option', 'Default', 'Description' }, rows,
      'The Typst SVG cache.', '{.striped .hover tbl-colwidths="[28,16,56]"}'
    )
  end
  return table_markdown(
    { 'Option', 'Default', 'Description' }, rows,
    'Document and project options.', '{.striped .hover tbl-colwidths="[20,14,66]"}'
  )
end

--- Build the shortcode attributes table.
--- @return string
local function attributes_table()
  local attributes = loaded.shortcodes
    and loaded.shortcodes.iconify
    and loaded.shortcodes.iconify.attributes
  if attributes == nil then
    return ''
  end

  local rows = {}
  for _, name in ipairs(schema.key_order(attributes)) do
    rows[#rows + 1] = {
      '`' .. name .. '`',
      cell(attributes[name].description),
    }
  end

  return table_markdown(
    { 'Attribute', 'Description' }, rows,
    'Attributes accepted on both shortcodes.', '{.striped .hover tbl-colwidths="[22,78]"}'
  )
end

--- @type table<string, function>
local TABLES = {
  document = function() return options_table(false) end,
  typst = function() return options_table(true) end,
  attributes = attributes_table,
}

--- Replace each marked div with the table it names.
--- Quarto's language-server plugin rewrites a filter function's doc comment,
--- adding `@param` and `@return` without checking for an existing annotation,
--- so declaring either here duplicates it.
function Div(el)
  if not el.classes:includes('schema-table') then
    return nil
  end

  local name = el.attributes['table']
  local build = name and TABLES[name]
  if build == nil then
    io.stderr:write(
      '[schema-tables] unknown table "' .. tostring(name) ..
      '"; use document, typst or attributes\n'
    )
    return nil
  end

  return pandoc.read(build(), 'markdown').blocks
end
