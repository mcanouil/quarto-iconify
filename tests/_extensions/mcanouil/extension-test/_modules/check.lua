--- Extension Test - The check hook.
---
--- A `check` command is repository code and has the same trust as the Lua
--- filters of the extension. The runner reads TAP from its standard output
--- only, so a `not ok` line on standard error is never a test result.

local util = require('util')

local M = {}

--- The directive of a TAP line: a `#` followed by `skip` or `todo` in any case.
---
--- A colon may follow the word, as in `# SKIP: reason`, as TAP::Parser reads it.
--- @param text string the line after its number and dash
--- @return string description, string|nil directive, string reason
local function split_directive(text)
  local from = 1
  while true do
    local at = text:find('#', from, true)
    if not at then
      return util.trim(text), nil, ''
    end
    local word, rest = text:sub(at + 1):match('^%s*(%a+)(.*)$')
    local name = word and word:upper()
    if (name == 'SKIP' or name == 'TODO') and (rest == '' or rest:match('^[%s:]')) then
      return util.trim(text:sub(1, at - 1)), name, util.trim((rest:gsub('^:', '')))
    end
    from = at + 1
  end
end

--- Read one top-level TAP line.
--- @param line string
--- @return table|nil record {ok, description, directive, reason}, or {bail, reason} for `Bail out!`
local function parse_line(line)
  -- A command that writes CRLF leaves `\r` at the end of each line, and a
  -- bare `not ok\r` would otherwise be dropped and read as a pass.
  line = line:gsub('\r$', '')
  local bail_reason = line:match('^Bail out!(.*)$')
  if bail_reason then
    return { bail = true, reason = util.trim(bail_reason) }
  end
  local ok, rest = true, line:match('^ok$') and '' or line:match('^ok (.*)$')
  if not rest then
    ok, rest = false, line:match('^not ok$') and '' or line:match('^not ok (.*)$')
  end
  if not rest then
    return nil
  end
  rest = rest:gsub('^%s*%d+', ''):gsub('^%s*%-', '')
  local description, directive, reason = split_directive(rest)
  return { ok = ok, description = description, directive = directive, reason = reason }
end

--- The top-level TAP lines of a text, in order.
---
--- Plan lines, comments, indented subtest lines, and other text are not TAP
--- lines, and neither is a line such as `okay` that only starts with `ok`.
--- A `Bail out!` line is the last record, with `bail` set, because the
--- command gave up and the lines after it are not results.
--- @param text string
--- @return table[] records from `parse_line`
function M.parse_tap(text)
  local records = {}
  for _, line in ipairs(util.lines(text)) do
    local record = parse_line(line)
    if record then
      records[#records + 1] = record
      if record.bail then
        break
      end
    end
  end
  return records
end

--- The entry that one TAP line gives.
--- @param record table
--- @param position integer
--- @return table entry
local function tap_entry(record, position)
  local entry = { id = 'check/' .. position, kind = 'check' }
  if record.description ~= '' then
    entry.expected = record.description
  end
  if record.bail then
    entry.expected, entry.status = 'no Bail out!', 'fail'
    entry.message = record.reason ~= '' and record.reason or 'Bail out!'
  elseif record.directive == 'SKIP' then
    entry.status, entry.message = 'skip', util.trim('SKIP ' .. record.reason)
  elseif not record.ok and record.directive == 'TODO' then
    entry.status, entry.message = 'skip', util.trim('TODO ' .. record.reason)
  elseif record.ok then
    entry.status = 'pass'
  else
    entry.status, entry.message = 'fail', 'not ok'
  end
  return entry
end

--- The last non-empty line of a text, or nil.
--- @param text string
--- @return string|nil
local function last_line(text)
  local lines = util.lines(text)
  for index = #lines, 1, -1 do
    local line = util.trim(lines[index])
    if line ~= '' then
      return line
    end
  end
  return nil
end

--- The single entry that stands for a check without TAP lines, or one that did not run to its end.
--- @param status string `pass`, `fail`, or `skip`
--- @param message string|nil
--- @return table entry
local function summary_entry(status, message)
  return { id = 'check', kind = 'check', expected = 'exit 0', status = status, message = message }
end

--- Grade a finished check command.
--- @param code integer exit code of the command
--- @param stdout string
--- @param stderr string
--- @param limited boolean true when a time limit was applied
--- @param timeout number the time limit in seconds
--- @param elapsed number seconds the command ran
--- @return table result {status, entries, message}
function M.grade(code, stdout, stderr, limited, timeout, elapsed)
  if util.timed_out(code, limited and timeout or nil, elapsed) then
    local message = 'the check exceeded ' .. timeout .. ' seconds'
    return { status = 'timeout', message = message, entries = { summary_entry('fail', message) } }
  end
  if code == 77 then
    return {
      status = 'skip',
      entries = { summary_entry('skip', 'exit 77: the check does not apply to this case') },
    }
  end

  local entries, failed_message = {}, nil
  local failed = code ~= 0
  for position, record in ipairs(M.parse_tap(stdout)) do
    local entry = tap_entry(record, position)
    entries[#entries + 1] = entry
    if record.bail then
      failed, failed_message = true, entry.message
    elseif entry.status == 'fail' then
      failed = true
      failed_message = failed_message
        or (record.description ~= '' and record.description or ('not ok on TAP line ' .. position))
    end
  end
  if #entries == 0 then
    entries[1] = code ~= 0 and summary_entry('fail', 'exit ' .. code) or summary_entry('pass')
  end

  if not failed then
    return { status = 'pass', entries = entries }
  end
  return {
    status = 'fail',
    entries = entries,
    message = failed_message or last_line(stderr) or ('the check exited ' .. code),
  }
end

--- The shell line that runs a check command.
---
--- `util.capture` appends `2>&1` to the whole line, so the redirections sit
--- inside a brace group. Without it that suffix would come after the
--- standard error redirection and send standard error into the standard
--- output file. Standard input is `/dev/null`, so a command that reads it
--- ends instead of waiting for the runner's input.
--- @param tests string the tests directory, the working directory of the command
--- @param command string the `check` value, run through `sh -c`
--- @param env table<string, string> variables for the command
--- @param stdout_path string
--- @param stderr_path string
--- @param timeout number the time limit in seconds
--- @return string
function M.command(tests, command, env, stdout_path, stderr_path, timeout)
  local assignments = {}
  for _, name in ipairs(util.sorted_keys(env)) do
    assignments[#assignments + 1] = name .. '=' .. util.shell_quote(env[name]) .. ' '
  end
  return 'cd ' .. util.shell_quote(tests) .. ' && { ' .. table.concat(assignments)
    .. util.timeout_prefix(timeout) .. 'sh -c ' .. util.shell_quote(command)
    .. ' < /dev/null > ' .. util.shell_quote(stdout_path)
    .. ' 2> ' .. util.shell_quote(stderr_path) .. '; }'
end

--- Run a check command, grade it, and keep its output in a log.
--- @param spec table {tests, command, env, timeout, log_path}
--- @return table result the `grade` result plus `log`
function M.run(spec)
  local stdout_path, stderr_path = spec.log_path .. '.stdout', spec.log_path .. '.stderr'
  for _, path in ipairs({ spec.log_path, stdout_path, stderr_path }) do
    os.remove(path)
  end
  pcall(pandoc.system.make_directory, pandoc.path.directory(spec.log_path), true)

  local started = os.time()
  local code = util.capture(M.command(spec.tests, spec.command, spec.env, stdout_path, stderr_path, spec.timeout))
  local elapsed = os.time() - started
  local stdout, stderr = util.read_file(stdout_path) or '', util.read_file(stderr_path) or ''
  local result = M.grade(code, stdout, stderr, util.timeout_command() ~= nil, spec.timeout, elapsed)

  util.write_file(spec.log_path, table.concat({
    '$ ' .. spec.command, 'exit ' .. code, '', '# stdout', stdout, '', '# stderr', stderr, '',
  }, '\n'))
  os.remove(stdout_path)
  os.remove(stderr_path)
  result.log = spec.log_path
  return result
end

return M
