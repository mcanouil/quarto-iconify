--- Extension Test - Shared helpers for the test runner.
---
--- Every iteration helper here returns keys in a deterministic order. Lua
--- table order is not stable between runs, and a test report whose findings
--- reorder on every run cannot be diffed, which is how the reference
--- conformance sweep this runner grew out of came to hide regressions.

local M = {}

--- Join path segments with the platform separator.
--- @param ... string
--- @return string
function M.join(...)
  return pandoc.path.join({ ... })
end

--- Absolute directory holding the running script.
--- @return string
function M.script_dir()
  local self = arg and arg[0]
  if not self then
    local info = debug.getinfo(1, 'S')
    self = info and info.source and info.source:gsub('^@', '')
  end
  if not self then
    return pandoc.system.get_working_directory()
  end
  local dir = pandoc.path.directory(self)
  if pandoc.path.is_absolute(dir) then
    return dir
  end
  return pandoc.path.normalize(M.join(pandoc.system.get_working_directory(), dir))
end

--- Resolve a path against the working directory.
---
--- A relative path is only valid from the directory it was given in, and the
--- render layer inspects a document from inside the tests directory, so a
--- relative path there names a file that is not present.
--- @param path string
--- @return string
function M.absolute(path)
  if pandoc.path.is_absolute(path) then
    return pandoc.path.normalize(path)
  end
  return pandoc.path.normalize(M.join(pandoc.system.get_working_directory(), path))
end

--- The SHA-256 command available on this platform, if any.
---
--- `shasum` is present on macOS, `sha256sum` on most Linux images. The lookup
--- runs once: it is the same answer for every file in a run.
--- @return string|nil command prefix, ready for a quoted path
local sha256_command_cache = false
function M.sha256_command()
  if sha256_command_cache ~= false then
    return sha256_command_cache
  end
  for _, candidate in ipairs({ { 'shasum', 'shasum -a 256 ' }, { 'sha256sum', 'sha256sum ' } }) do
    local code = M.capture('command -v ' .. candidate[1])
    if code == 0 then
      sha256_command_cache = candidate[2]
      return candidate[2]
    end
  end
  sha256_command_cache = nil
  return nil
end

--- SHA-256 of a file, as lower-case hexadecimal.
---
--- The Pandoc that Quarto ships offers `sha1` and no SHA-256, so this shells
--- out. A caller must be able to tell three outcomes apart: a digest, no tool
--- to compute one with, and a path the tool cannot read. Reporting the last
--- as the second says the machine is at fault when the file is.
--- @param path string
--- @return string|nil digest
--- @return string|nil reason `no-tool` or `unreadable`
function M.sha256(path)
  local command = M.sha256_command()
  if not command then
    return nil, 'no-tool'
  end
  local code, output = M.capture(command .. M.shell_quote(path))
  if code == 0 then
    local digest = M.trim(output):match('^(%x+)')
    if digest then
      return digest:lower(), nil
    end
  end
  return nil, 'unreadable'
end

--- Whether a path exists and is readable.
--- @param path string
--- @return boolean
function M.exists(path)
  local handle = io.open(path, 'r')
  if handle then
    handle:close()
    return true
  end
  -- A directory refuses `io.open` on some platforms but lists fine.
  local ok = pcall(pandoc.system.list_directory, path)
  return ok
end

--- Whether a path is a directory.
--- @param path string
--- @return boolean
function M.is_dir(path)
  local ok = pcall(pandoc.system.list_directory, path)
  return ok
end

--- Read a whole file.
--- @param path string
--- @return string|nil contents, string|nil error
function M.read_file(path)
  local handle, err = io.open(path, 'rb')
  if not handle then
    return nil, err or ('cannot read ' .. path)
  end
  local contents = handle:read('a')
  handle:close()
  return contents, nil
end

--- Write a whole file, creating parent directories.
--- @param path string
--- @param contents string
--- @return boolean ok, string|nil error
function M.write_file(path, contents)
  local dir = pandoc.path.directory(path)
  if dir and dir ~= '' and dir ~= '.' then
    pcall(pandoc.system.make_directory, dir, true)
  end
  local handle, err = io.open(path, 'wb')
  if not handle then
    return false, err or ('cannot write ' .. path)
  end
  handle:write(contents)
  handle:close()
  return true, nil
end

--- Directory entries, sorted, without `.` and `..`.
--- @param path string
--- @return string[]
function M.list_dir(path)
  local ok, entries = pcall(pandoc.system.list_directory, path)
  if not ok or not entries then
    return {}
  end
  local names = {}
  for _, name in ipairs(entries) do
    if name ~= '.' and name ~= '..' then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

--- Recursively copy a directory.
--- @param src string
--- @param dest string
--- @return boolean ok, string|nil error
function M.copy_tree(src, dest)
  if not M.is_dir(src) then
    local contents, err = M.read_file(src)
    if not contents then
      return false, err
    end
    return M.write_file(dest, contents)
  end
  local ok, err = pcall(pandoc.system.make_directory, dest, true)
  if not ok then
    return false, tostring(err)
  end
  for _, name in ipairs(M.list_dir(src)) do
    local copied, copy_err = M.copy_tree(M.join(src, name), M.join(dest, name))
    if not copied then
      return false, copy_err
    end
  end
  return true, nil
end

--- Remove a directory tree, ignoring a missing path.
--- @param path string
function M.remove_tree(path)
  if not M.exists(path) then
    return
  end
  pcall(pandoc.system.remove_directory, path, true)
end

--- Table keys in a stable order.
--- @param map table
--- @return string[]
function M.sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

--- Quote a value for a POSIX shell.
--- @param value string
--- @return string
function M.shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

--- Run a command, capturing combined output.
--- Returns the exit code rather than raising, because every failure here is a
--- test result rather than a harness error.
--- @param command string
--- @return integer code, string output
function M.capture(command)
  local handle = io.popen(command .. ' 2>&1', 'r')
  if not handle then
    return 127, 'cannot spawn: ' .. command
  end
  local output = handle:read('a') or ''
  local ok, kind, code = handle:close()
  if ok then
    return 0, output
  end
  if kind == 'exit' or kind == 'signal' then
    return code or 1, output
  end
  return 1, output
end

--- The timeout command available on this platform, if any.
---
--- GNU coreutils supplies `timeout`, which Linux runners and the catalogue's
--- container both have. macOS ships neither unless coreutils is installed,
--- where it is `gtimeout`. A run without either is still correct, it just
--- cannot bound a hung render, so the absence is reported rather than fatal.
--- @return string|nil name
local timeout_command_cache = false
function M.timeout_command()
  if timeout_command_cache ~= false then
    return timeout_command_cache
  end
  for _, name in ipairs({ 'timeout', 'gtimeout' }) do
    local code = M.capture('command -v ' .. name)
    if code == 0 then
      timeout_command_cache = name
      return name
    end
  end
  timeout_command_cache = nil
  return nil
end

--- A command prefix bounding a run to `seconds`, empty when unavailable.
--- @param seconds number
--- @return string
function M.timeout_prefix(seconds)
  local command = M.timeout_command()
  if not command then
    return ''
  end
  return string.format('%s %d ', command, math.floor(tonumber(seconds) or 300))
end

--- Split text into lines, dropping a trailing empty line.
--- @param text string
--- @return string[]
function M.lines(text)
  local out = {}
  for line in tostring(text or ''):gmatch('([^\n]*)\n?') do
    out[#out + 1] = line
  end
  if #out > 0 and out[#out] == '' then
    table.remove(out)
  end
  return out
end

--- Trim surrounding whitespace.
--- @param value string
--- @return string
function M.trim(value)
  return (tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

--- A copy of a list of messages in a stable order.
---
--- The reference validator walks its descriptor and value maps with `pairs`,
--- and Lua seeds string hashes per process, so the same input yields the same
--- findings in a different order on every run. Sorting them here is what makes
--- a result diffable, and it is done at the point of consumption because the
--- validator is vendored upstream code.
--- @param messages string[]
--- @return string[]
function M.sorted_messages(messages)
  local copy = {}
  for index, message in ipairs(messages or {}) do
    copy[index] = message
  end
  table.sort(copy)
  return copy
end

--- Whether an array contains a value.
--- @param list table
--- @param needle any
--- @return boolean
function M.contains(list, needle)
  for _, item in ipairs(list or {}) do
    if item == needle then
      return true
    end
  end
  return false
end

return M
