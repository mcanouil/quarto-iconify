--- Extension Test - Reading the `test:` block from a document.
---
--- The vocabulary is additive only. The catalogue sweep runs one pinned
--- framework version against repositories that pinned an older one, so a key
--- this version does not recognise is reported as a warning and ignored,
--- never as a failure.

local util = require('util')
local schema = require('schema')

local M = {}

--- Defaults applied when a document declares nothing.
M.DEFAULTS = {
  schema = 1,
  expect = 'pass',
  strict = true,
  timeout = 300,
  skip = false,
}

--- Extract the YAML front matter of a document.
---
--- Only a block opened by `---` on the first non-empty line counts, which is
--- what Quarto itself accepts.
--- @param text string
--- @return string|nil yaml
local function front_matter_text(text)
  local body = text:gsub('^\239\187\191', '')
  local block = body:match('^%-%-%-\r?\n(.-)\r?\n%-%-%-%s*\r?\n')
    or body:match('^%-%-%-\r?\n(.-)\r?\n%.%.%.%s*\r?\n')
  return block
end

--- Read and validate a document's `test:` block.
--- @param path string document path
--- @param descriptors table descriptors from test-schema.yml
--- @param defaults table|nil project-level defaults from tests/_quarto.yml
--- @return table settings
--- @return string[] warnings
function M.read(path, descriptors, defaults)
  local warnings = {}
  local text, read_err = util.read_file(path)
  if not text then
    return M.DEFAULTS, { tostring(read_err) }
  end

  local block = front_matter_text(text)
  local declared = {}
  if block then
    local ok, parsed = pcall(schema._parse_yaml_text, block)
    if ok and type(parsed) == 'table' and type(parsed.test) == 'table' then
      declared = parsed.test
    elseif ok and type(parsed) == 'table' and parsed.test ~= nil then
      warnings[#warnings + 1] = 'the `test:` key is not a mapping and was ignored'
    end
  end

  -- Project-level defaults lose to the document, key by key.
  local merged = {}
  for key, value in pairs(defaults or {}) do
    merged[key] = value
  end
  for key, value in pairs(declared) do
    merged[key] = value
  end

  local _, errors, validation_warnings, coerced =
    schema.validate(merged, descriptors, { unknown = 'warn' })
  -- Reported, not fatal: a `test:` block this version cannot read must not
  -- stop the catalogue sweep from testing the extension at all. Sorted so a
  -- document with several problems reports them in the same order every run.
  for _, message in ipairs(util.sorted_messages(errors)) do
    warnings[#warnings + 1] = message
  end
  for _, message in ipairs(util.sorted_messages(validation_warnings)) do
    warnings[#warnings + 1] = message
  end

  local settings = {}
  for key, value in pairs(M.DEFAULTS) do
    settings[key] = value
  end
  for key, value in pairs(coerced or merged) do
    settings[key] = value
  end

  if type(settings.formats) == 'string' then
    settings.formats = { settings.formats }
  end
  settings.name = settings.name or pandoc.path.filename(path):gsub('%.qmd$', '')

  return settings, warnings
end

--- Read project-level `test:` defaults from a tests project file.
--- @param tests string tests directory
--- @return table defaults
function M.project_defaults(tests)
  for _, name in ipairs({ '_quarto.yml', '_quarto.yaml' }) do
    local path = util.join(tests, name)
    if util.exists(path) then
      local text = util.read_file(path)
      if text then
        local ok, parsed = pcall(schema._parse_yaml_text, text)
        if ok and type(parsed) == 'table' and type(parsed.test) == 'table' then
          return parsed.test
        end
      end
      return {}
    end
  end
  return {}
end

return M
