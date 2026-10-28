--- Extension Test - The assertions of a `_quarto.tests` format entry.
---
--- Each function returns entries for `case.assertions`. Patterns are the
--- regular expressions of q2 and quarto-cli, translated to Lua patterns by the
--- vendored validator. A pattern the translator refuses is a skip, because the
--- gap is in this runner and not in the extension.

local util = require('util')
local schema = require('schema')
local log = require('log')

local M = {}

local Q2_WARNING = 'q2 call test fails a document with %s'

--- Whether a value is a list of strings. An empty table counts as one.
local function is_string_list(value)
  if type(value) ~= 'table' then
    return false
  end
  for key, item in pairs(value) do
    if type(key) ~= 'number' or type(item) ~= 'string' then
      return false
    end
  end
  return true
end

--- Whether a compiled branch is anchored at a line start or end.
---
--- A final `$` is escaped only when an odd run of `%` precedes it, because a
--- literal `%` compiles to `%%`.
local function anchored(branch)
  if branch:sub(1, 1) == '^' then
    return true
  end
  if branch:sub(-1) ~= '$' then
    return false
  end
  local percents = #(branch:sub(1, -2):match('%%*$'))
  return percents % 2 == 0
end

--- A compiled branch whose `.` stops at a line break.
---
--- Lua's `.` matches a newline, and the `.` of q2 and quarto-cli does not, so
--- each bare `.` outside a character class becomes `[^\n]`.
local function line_bounded(branch)
  local out, index, in_class = {}, 1, false
  while index <= #branch do
    local char = branch:sub(index, index)
    if char == '%' then
      out[#out + 1] = branch:sub(index, index + 1)
      index = index + 2
    else
      if in_class then
        if char == ']' then
          in_class = false
        end
        out[#out + 1] = char
      elseif char == '[' then
        in_class = true
        out[#out + 1] = char
        -- A `]` right after `[` or `[^` is a literal member of the class.
        local after = branch:sub(index + 1, index + 1)
        if after == '^' then
          out[#out + 1] = after
          index = index + 1
          after = branch:sub(index + 1, index + 1)
        end
        if after == ']' then
          out[#out + 1] = after
          index = index + 1
        end
      elseif char == '.' then
        out[#out + 1] = '[^\n]'
      else
        out[#out + 1] = char
      end
      index = index + 1
    end
  end
  return table.concat(out)
end

--- One failed entry that stands for the whole assertion.
local function fail_entry(kind, message)
  return { { id = kind, kind = kind, status = 'fail', message = message } }
end

--- One invalid entry for an assertion with the wrong shape.
local function invalid(kind, message)
  return fail_entry(kind, 'assertion-invalid: ' .. message)
end

--- Whether compiled branches match a text.
---
--- q2 and quarto-cli match file patterns with the multiline flag, so an
--- anchored branch is tried against each line when `by_line` is set.
--- @param text string
--- @param branches string[]
--- @param by_line boolean
--- @return boolean
function M.matches(text, branches, by_line)
  local split
  for _, compiled in ipairs(branches) do
    local branch = line_bounded(compiled)
    if by_line and anchored(branch) then
      split = split or util.lines(text)
      for _, line in ipairs(split) do
        if line:find(branch) then
          return true
        end
      end
    elseif text:find(branch) then
      return true
    end
  end
  return false
end

--- Evaluate `[[must match...], [must not match...]]` against a text.
--- @param kind string the assertion key
--- @param value any
--- @param text string
--- @param by_line boolean
--- @param label string the file named in a message
--- @return table[] entries
function M.pattern_pair(kind, value, text, by_line, label)
  if type(value) ~= 'table' or #value < 1 or #value > 2
    or not is_string_list(value[1]) or (value[2] ~= nil and not is_string_list(value[2])) then
    return invalid(kind, 'expects [[patterns that must match], [patterns that must not match]]')
  end
  local entries = {}
  for _, list in ipairs({ { 'match', value[1] }, { 'noMatch', value[2] or {} } }) do
    local name, patterns = list[1], list[2]
    for index, pattern in ipairs(patterns) do
      local entry = { id = string.format('%s/%s/%d', kind, name, index), kind = kind, expected = pattern }
      local branches, reason = schema._compile_pattern(pattern)
      if not branches then
        entry.status, entry.message = 'skip', 'pattern-unsupported: ' .. tostring(reason)
      else
        local found = M.matches(text, branches, by_line)
        if (name == 'match') == found then
          entry.status = 'pass'
        else
          entry.status = 'fail'
          entry.message = string.format('%s in %s', found and 'found' or 'not found', label)
        end
      end
      entries[#entries + 1] = entry
    end
  end
  if #entries == 0 then
    return invalid(kind, 'names no pattern to match or to refuse')
  end
  return entries
end

local function file_regex(value, ctx)
  local text = util.read_file(ctx.output_path) or ''
  return M.pattern_pair('ensureFileRegexMatches', value, text, true, ctx.output_label)
end

local function typst_regex(value, ctx)
  local kind = 'ensureTypstFileRegexMatches'
  if not ctx.typ_path then
    return fail_entry(kind, string.format('needs a `typst` format, not `%s`', tostring(ctx.format)))
  end
  if ctx.typ_preexisting then
    return fail_entry(kind, string.format(
      '%s already existed before the render, so it cannot show what the render kept; move it, and set keep-typ: true',
      tostring(ctx.typ_label)))
  end
  local text = util.read_file(ctx.typ_path)
  if not text then
    return fail_entry(kind, 'set keep-typ: true')
  end
  return M.pattern_pair(kind, value, text, true, ctx.typ_label)
end

local function docx_regex(value, ctx)
  local kind = 'ensureDocxRegexMatches'
  local xml
  local bytes = util.read_file(ctx.output_path)
  if bytes then
    local ok, archive = pcall(pandoc.zip.Archive, bytes)
    if ok and archive then
      for _, entry in ipairs(archive.entries) do
        if entry.path == 'word/document.xml' then
          xml = entry:contents()
          break
        end
      end
    end
  end
  local entries
  if not xml then
    entries = fail_entry(kind, 'no word/document.xml in ' .. tostring(ctx.output_label))
  else
    entries = M.pattern_pair(kind, value, xml, false, ctx.output_label)
  end
  for _, entry in ipairs(entries) do
    entry.warnings = { string.format(Q2_WARNING, kind) }
  end
  return entries
end

--- The entries of a `printsMessage` value: one mapping, or a list of them.
--- @return table[]|nil the entries, or nil when the value has neither shape
local function message_list(value)
  if type(value) == 'table' and value.level ~= nil then
    return { value }
  end
  if type(value) ~= 'table' or #value == 0 then
    return nil
  end
  return value
end

--- The level of a valid `printsMessage` entry.
--- @return string|nil the normalised level, or nil when the entry is invalid
local function message_level(item)
  if type(item) ~= 'table' then
    return nil
  end
  local level = log.normalise_level(item.level)
  local count = item.count
  local count_valid = count == nil
    or (type(count) == 'number' and math.tointeger(count) and count >= 1 and not item.negate)
  if not level or type(item.regex) ~= 'string'
    or (item.negate ~= nil and type(item.negate) ~= 'boolean') or not count_valid then
    return nil
  end
  return level
end

local function prints_message(value, ctx)
  local kind = 'printsMessage'
  local list = message_list(value)
  if not list then
    return invalid(kind, 'expects {level, regex, negate, count} or a list of them')
  end
  local entries = {}
  for index, item in ipairs(list) do
    local entry = { id = string.format('%s/%d', kind, index), kind = kind }
    local level = message_level(item)
    if not level then
      entry.status = 'fail'
      entry.message = 'assertion-invalid: expects {level: DEBUG, INFO, WARN, or ERROR, regex: a string, negate: a boolean, count: a whole number of 1 or more, not with negate}'
    else
      entry.expected = level .. ' ' .. item.regex
      local branches, reason = schema._compile_pattern(item.regex)
      if level == 'DEBUG' then
        entry.status, entry.message = 'skip', 'the log is written at level info, so DEBUG messages are not recorded'
      elseif not branches then
        entry.status, entry.message = 'skip', 'pattern-unsupported: ' .. tostring(reason)
      else
        local found = 0
        for _, line in ipairs(ctx.lines) do
          if line.level == level and M.matches(line.message, branches, false) then
            found = found + 1
          end
        end
        if item.count then
          if found == item.count then
            entry.status = 'pass'
          else
            entry.status = 'fail'
            entry.message = string.format('expected %d %s line(s) matching %s, found %d',
              item.count, level, item.regex, found)
          end
        elseif (item.negate and found == 0) or (not item.negate and found > 0) then
          entry.status = 'pass'
        else
          entry.status = 'fail'
          entry.message = string.format('%s %s message matching %s',
            item.negate and 'found a' or 'missing a', level, item.regex)
        end
      end
    end
    entries[#entries + 1] = entry
  end
  return entries
end

local function file_exists(value, ctx)
  local kind = 'fileExists'
  if type(value) ~= 'table' then
    return invalid(kind, 'expects {outputPath: <path>, supportPath: <path>}')
  end
  local entries = {}
  for _, key in ipairs(util.sorted_keys(value)) do
    local base
    if key == 'outputPath' then
      base = ctx.output_dir
    elseif key == 'supportPath' then
      base = ctx.support_dir
    end
    if not base or type(value[key]) ~= 'string' then
      return invalid(kind, 'expects {outputPath: <path>, supportPath: <path>}')
    end
    local path = util.join(base, value[key])
    local entry = { id = kind .. '/' .. key, kind = kind, expected = value[key] }
    if not util.exists(path) then
      entry.status, entry.message = 'fail', 'missing: ' .. path
    elseif util.is_dir(path) then
      entry.status, entry.message = 'fail', 'not a regular file: ' .. path
    else
      entry.status = 'pass'
    end
    entries[#entries + 1] = entry
  end
  if #entries == 0 then
    return invalid(kind, 'names no path to look for')
  end
  return entries
end

local RUNNERS = {
  ensureFileRegexMatches = file_regex,
  ensureTypstFileRegexMatches = typst_regex,
  ensureDocxRegexMatches = docx_regex,
  printsMessage = prints_message,
  fileExists = file_exists,
}

--- The entry of a key this runner knows and does not execute.
local function not_executed(key, q2_rejects)
  return { {
    id = key, kind = key, status = 'skip',
    message = string.format('this runner does not execute `%s`', key),
    warnings = q2_rejects and { string.format(Q2_WARNING, key) } or nil,
  } }
end

--- Evaluate every assertion of a format entry.
--- @param assertions table[] from `frontmatter.spec`
--- @param ctx table {lines, output_path, output_label, output_dir, support_dir, typ_path, typ_label, typ_preexisting, format}
--- @param log_only boolean true under `shouldError`, where only `printsMessage` runs
--- @return table[] entries
--- @return string[] notes warnings for the case
function M.evaluate(assertions, ctx, log_only)
  local entries, notes, skipped_files = {}, {}, false
  for _, item in ipairs(assertions) do
    local produced
    if item.class == 'known' then
      produced = not_executed(item.key, item.q2_rejects)
    elseif log_only and item.key ~= 'printsMessage' then
      skipped_files = true
    elseif RUNNERS[item.key] then
      produced = RUNNERS[item.key](item.value, ctx)
    else
      -- A key the table calls executed with no runner here is a gap in this
      -- runner, so it is a skip, never a crash of the whole layer.
      produced = not_executed(item.key, item.q2_rejects)
    end
    for _, entry in ipairs(produced or {}) do
      entries[#entries + 1] = entry
    end
  end
  if skipped_files then
    notes[#notes + 1] = 'file assertions do not run under `shouldError`'
  end
  return entries, notes
end

--- The failure message of a case, from its entries.
--- @param entries table[]
--- @return string|nil
function M.failure(entries)
  local failed, first = 0, nil
  for _, entry in ipairs(entries) do
    if entry.status == 'fail' then
      failed = failed + 1
      first = first or entry
    end
  end
  if failed == 0 then
    return nil
  end
  local expected = first.expected and (' "' .. first.expected .. '"') or ''
  return string.format('%s%s %s (%d of %d assertions failed)',
    first.id, expected, first.message or 'failed', failed, #entries)
end

--- The logged warnings that no expected `printsMessage` entry matches.
---
--- Under `warnings: exhaustive`, each warning must be expected. An entry
--- expects a warning when its level is WARN and it is not negated. An entry
--- that `prints_message` finds invalid, or with a regex the translator
--- refuses, expects nothing. Such entries are returned as notes, so that the
--- failure can name them.
--- @param assertions table[] the assertions of one format entry
--- @param warnings string[] messages of the log lines at WARN
--- @return string[] the unexpected messages, in log order
--- @return string[] notes on the non-negated entries that expect nothing
function M.unexpected_warnings(assertions, warnings)
  local patterns, unusable = {}, {}
  for _, item in ipairs(assertions) do
    if item.key == 'printsMessage' then
      -- A value of neither shape is one invalid entry.
      for _, entry in ipairs(message_list(item.value) or { false }) do
        local level = message_level(entry)
        if not level then
          unusable[#unusable + 1] = 'an invalid printsMessage entry expects nothing'
        elseif level == 'WARN' and not entry.negate then
          local branches, reason = schema._compile_pattern(entry.regex)
          if branches then
            patterns[#patterns + 1] = branches
          else
            unusable[#unusable + 1] = string.format('`%s` expects nothing: pattern-unsupported: %s',
              entry.regex, tostring(reason))
          end
        end
      end
    end
  end
  local unexpected = {}
  for _, message in ipairs(warnings) do
    local matched = false
    for _, branches in ipairs(patterns) do
      if M.matches(message, branches, false) then
        matched = true
        break
      end
    end
    if not matched then
      unexpected[#unexpected + 1] = message
    end
  end
  return unexpected, unusable
end

return M
