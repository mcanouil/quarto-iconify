--- Extension Test - Reading the `_quarto.tests` block of a document.
---
--- The block comes from `quarto inspect` (`cli.inspect`), which keeps a format
--- key with no value. Every key other than `run` names a format. A format in
--- `tests/_quarto.yml` is refused by `project_problem`, so the merged block
--- that `quarto inspect` reports is the block of the document.

local util = require('util')
local schema = require('schema')
local vocabulary = require('vocabulary')

local M = {}

--- The options of the runner when a document declares none.
M.DEFAULTS = { timeout = 300, description = '' }

--- The keys of `_quarto.tests.run` that q2 reads, and the runner's own.
local RUN_KEYS = {
  skip = true, ci = true, os = true, not_os = true,
  requires_js = true, requires = true, ['extension-test'] = true,
}

--- Keys under `_quarto.tests.run` that neither q2 nor the runner reads.
---
--- q2 ignores them, so they do not fail the document; they are named in the
--- case warnings, because a typo such as `not-os` otherwise does nothing.
--- @param run table
--- @return string[] warnings
function M.unknown_run_keys(run)
  local out = {}
  for _, key in ipairs(util.sorted_keys(run or {})) do
    if not RUN_KEYS[key] then
      out[#out + 1] = string.format('`_quarto.tests.run.%s` is not a key that q2 or this runner reads, and it is ignored', key)
    end
  end
  return out
end

--- Commands that show an engine runtime is present.
local ENGINE_COMMANDS = { knitr = 'Rscript', jupyter = 'jupyter' }

--- Whether a decoded value is absent.
local function is_null(value)
  return value == nil or value == pandoc.json.null
end

--- Whether a decoded value is a mapping. An empty table counts as one.
local function is_map(value)
  if type(value) ~= 'table' then
    return false
  end
  for key in pairs(value) do
    if type(key) ~= 'string' then
      return false
    end
  end
  return true
end

--- A string or a list of strings, as a list.
local function as_list(value)
  if type(value) == 'string' then
    return { value }
  end
  if type(value) == 'table' then
    return value
  end
  return {}
end

--- Read one format entry.
--- @param name string
--- @param value table
--- @return table entry
local function format_entry(name, value)
  local entry = { name = name, assertions = {} }
  local policies = {}
  for _, key in ipairs(util.sorted_keys(value)) do
    local kind = vocabulary.classify(key)
    if kind.class == 'unknown' then
      entry.problem = entry.problem or {
        reason = 'unknown-assertion',
        key = key,
        message = string.format(
          'unknown key `%s` under `_quarto.tests.%s`; the valid keys are %s. This runner tracks the q2 keys of commit %s, so a key q2 added later is unknown here until the runner is updated.',
          key, name, table.concat(vocabulary.known_keys(), ', '), vocabulary.Q2_COMMIT),
      }
    elseif vocabulary.is_policy(key) then
      policies[#policies + 1] = key
    else
      entry.assertions[#entry.assertions + 1] = {
        key = key, value = value[key], class = kind.class, q2_rejects = kind.q2_rejects,
      }
    end
  end
  if #policies > 1 then
    entry.problem = entry.problem or {
      reason = 'policy-conflict',
      message = string.format('`_quarto.tests.%s` sets more than one of %s',
        name, table.concat(policies, ', ')),
    }
  end
  entry.policy = policies[1] or 'noErrorsOrWarnings'
  return entry
end

--- Turn a `_quarto.tests` block into a test specification.
--- @param tests any the block as `quarto inspect` reports it
--- @return table spec {run, has_format_keys, formats}
--- @return string|nil problem why the block cannot be read
function M.spec(tests)
  local spec = { run = {}, has_format_keys = false, formats = {} }
  if is_null(tests) then
    return spec, nil
  end
  if not is_map(tests) then
    return spec, '`_quarto.tests` must be a mapping'
  end
  if not is_null(tests.run) then
    if not is_map(tests.run) then
      return spec, '`_quarto.tests.run` must be a mapping'
    end
    spec.run = tests.run
  end
  for _, name in ipairs(util.sorted_keys(tests)) do
    if name ~= 'run' then
      local value = tests[name]
      if is_null(value) then
        value = {}
      end
      if not is_map(value) then
        return spec, string.format('`_quarto.tests.%s` must be a mapping', name)
      end
      spec.has_format_keys = true
      spec.formats[#spec.formats + 1] = format_entry(name, value)
    end
  end
  return spec, nil
end

--- The settings with a whole `timeout` as an integer.
---
--- JSON numbers decode as floats, so a `timeout: 6` arrives as `6.0` and
--- would print as `6.0` in a message. A value with no integer form, such as
--- `1e308`, stays as it is.
--- @param settings table
--- @return table settings
local function whole_timeout(settings)
  if math.type(settings.timeout) == 'float' then
    settings.timeout = math.tointeger(settings.timeout) or settings.timeout
  end
  return settings
end

--- Validate the options of the runner.
--- @param run table `_quarto.tests.run`
--- @param descriptors table the options of `test-schema.yml`
--- @param stem string the file stem of the document
--- @return table settings {timeout, name, description}
--- @return string|nil problem
function M.options(run, descriptors, stem)
  local settings = { timeout = M.DEFAULTS.timeout, description = M.DEFAULTS.description, name = stem }
  local declared = (run or {})['extension-test']
  if is_null(declared) then
    return settings, nil
  end
  if not is_map(declared) then
    return settings, '`_quarto.tests.run.extension-test` must be a mapping'
  end
  -- Without descriptors, `run.lua` has already warned that the schema could
  -- not be read. Every option would then read as unknown, so the declared
  -- values are kept as they are.
  if next(descriptors or {}) == nil then
    for key, value in pairs(declared) do
      settings[key] = value
    end
    return whole_timeout(settings), nil
  end
  local _, errors, _, coerced = schema.validate(declared, descriptors, { unknown = 'error' })
  if errors and #errors > 0 then
    return settings, table.concat(util.sorted_messages(errors), ' ')
  end
  for key, value in pairs(coerced or declared) do
    settings[key] = value
  end
  return whole_timeout(settings), nil
end

--- The operating system, with the names q2 uses.
--- @return string `darwin`, `linux`, `windows`, or `unknown`
function M.current_os()
  local name = pandoc.system.os
  if name == 'darwin' or name == 'linux' then
    return name
  end
  if name == 'mingw32' or name == 'windows' then
    return 'windows'
  end
  return 'unknown'
end

--- The real environment, read once per run.
local environment_probe

--- The probe of the real environment, with each command looked up once.
--- @return table {ci, os, has_command}
local function real_probe()
  if not environment_probe then
    local environment = pandoc.system.environment()
    local found = {}
    environment_probe = {
      ci = environment.CI ~= nil or environment.GITHUB_ACTIONS ~= nil,
      os = M.current_os(),
      has_command = function(name)
        if found[name] == nil then
          found[name] = (util.capture('command -v ' .. util.shell_quote(name))) == 0
        end
        return found[name]
      end,
    }
  end
  return environment_probe
end

--- Why a document is skipped, from `_quarto.tests.run`.
---
--- The checks and their order are those of q2 `RunConfig::should_skip`.
--- @param run table
--- @param probe table|nil {ci, os, has_command}; the real environment when nil
--- @return string|nil reason
function M.skip_reason(run, probe)
  probe = probe or real_probe()
  if run.skip == true then
    return 'skip: true'
  end
  if type(run.skip) == 'string' then
    return run.skip
  end
  if run.ci == false and probe.ci then
    return 'tests.run.ci is false'
  end
  if not is_null(run.os) and not util.contains(as_list(run.os), probe.os) then
    return 'tests.run.os does not include ' .. probe.os
  end
  if not is_null(run.not_os) and util.contains(as_list(run.not_os), probe.os) then
    return 'tests.run.not_os includes ' .. probe.os
  end
  if run.requires_js == true then
    return 'tests.run.requires_js: true (this runner does not execute JavaScript)'
  end
  for _, engine in ipairs(as_list(run.requires)) do
    local command = ENGINE_COMMANDS[engine]
    if not command then
      return string.format('tests.run.requires names `%s`, an engine this runner does not know', tostring(engine))
    end
    if not probe.has_command(command) then
      return string.format('tests.run.requires names `%s`, whose runtime is not available', tostring(engine))
    end
  end
  return nil
end

--- The top-level `output-file` of a document, read from its front matter.
---
--- `quarto inspect` reports a top-level `output-file` and one set inside a
--- format block the same way, so only the document itself tells them apart.
--- @param path string
--- @return string|nil
function M.document_output_file(path)
  local text = util.read_file(path)
  if not text then
    return nil
  end
  local body = text:gsub('^\239\187\191', '')
  local block = body:match('^%-%-%-\r?\n(.-)\r?\n%-%-%-%s*\r?\n')
    or body:match('^%-%-%-\r?\n(.-)\r?\n%.%.%.%s*\r?\n')
  if not block then
    return nil
  end
  local ok, parsed = pcall(schema._parse_yaml_text, block)
  local value = ok and type(parsed) == 'table' and parsed['output-file'] or nil
  if type(value) == 'string' and value ~= '' then
    return value
  end
  return nil
end

--- What the tests project sets under `_quarto.tests` that it may not.
---
--- Only `_quarto.tests.run.extension-test` is allowed there, because q2 reads
--- the document alone and never sees a project value. The block is the one
--- Quarto resolves (`cli.project_tests`), so a key with no value counts.
--- @param block any `_quarto.tests` of the project
--- @return string|nil message
function M.project_problem(block)
  if type(block) ~= 'table' then
    return nil
  end
  local extra = {}
  for _, key in ipairs(util.sorted_keys(block)) do
    if key ~= 'run' then
      extra[#extra + 1] = '`_quarto.tests.' .. key .. '`'
    elseif type(block.run) == 'table' then
      for _, run_key in ipairs(util.sorted_keys(block.run)) do
        if run_key ~= 'extension-test' then
          extra[#extra + 1] = '`_quarto.tests.run.' .. run_key .. '`'
        end
      end
    end
  end
  if #extra == 0 then
    return nil
  end
  return string.format(
    'The tests project sets %s. Only `_quarto.tests.run.extension-test` can be set there, because q2 reads the document alone.',
    table.concat(extra, ', '))
end

return M
