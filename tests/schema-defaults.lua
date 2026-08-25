--- Checks that the shipped `_schema.yml` still resolves the defaults the
--- extension relies on.
---
--- `_schema.yml` is the only place these values are written, so a parser
--- regression or an edit to the file would otherwise remove every default
--- silently, and every icon would render with an empty set.
---
--- Run with the Pandoc that Quarto ships, from the repository root:
---
---     quarto pandoc lua tests/schema-defaults.lua

local root = (arg and arg[0] or 'tests/schema-defaults.lua'):match('(.*/)tests/') or './'
local schema = assert(dofile(root .. '_extensions/iconify/_modules/schema.lua'))

local loaded, load_error = schema.load_schema(root .. '_extensions/iconify/_schema.yml')
if load_error then
  io.stderr:write('FAIL: ' .. load_error .. '\n')
  io.stdout:flush()
  os.exit(1, true)
end

local _, _, _, defaults = schema.validate({}, loaded.options, { unknown = 'ignore' })

--- The defaults the Lua reads back, with the type each one must carry.
local EXPECTED = {
  { 'set', 'octicon', 'string' },
  { 'inline', true, 'boolean' },
  { 'typst-cache', '.quarto/iconify-svg', 'string' },
  { 'typst-cache-max-age', 30, 'number' },
  { 'typst-cache-max-entries', 0, 'number' },
}

local failed = 0

for _, expectation in ipairs(EXPECTED) do
  local name, value, kind = expectation[1], expectation[2], expectation[3]
  local actual = defaults[name]
  if actual ~= value or type(actual) ~= kind then
    io.stdout:write(string.format(
      'FAIL %s: expected %s (%s), got %s (%s)\n',
      name, tostring(value), kind, tostring(actual), type(actual)
    ))
    failed = failed + 1
  else
    io.stdout:write(string.format('ok   %s = %s (%s)\n', name, tostring(value), kind))
  end
end

--- Every option the shortcodes read must be declared, or a document that sets
--- it is reported as an unknown key while still working.
for _, name in ipairs({ 'size', 'width', 'height', 'flip', 'rotate', 'style',
                        'mode', 'color', 'fallback', 'preload' }) do
  if loaded.options[name] == nil then
    io.stdout:write('FAIL ' .. name .. ' is read by the extension but not declared\n')
    failed = failed + 1
  end
end

--- The `iconify` shortcode needs an icon to render, and the schema says so
--- with `required` on the first argument.
---
--- These checks cover the schema half only: that the flag is declared, and
--- that the validator counts both an absent and an empty argument as missing.
--- The Lua that acts on it, the guard in `render_icon` and the report in
--- `validate_call`, is not exercised here, because loading `iconify.lua`
--- needs the `quarto` runtime this suite deliberately does without. Removing
--- that Lua would leave these checks green, so it is covered by rendering a
--- document instead.
local extra = 0

local iconify_entry = loaded.shortcodes and loaded.shortcodes.iconify
local first_argument = iconify_entry and iconify_entry.arguments and iconify_entry.arguments[1]

extra = extra + 1
if first_argument and first_argument.required == true then
  io.stdout:write('ok   iconify argument 1 is required\n')
else
  io.stdout:write('FAIL iconify argument 1 is not declared as required\n')
  failed = failed + 1
end

--- A call with no argument, and a call whose argument is empty, must both be
--- reported. The schema treats an empty string as missing, and the Lua guard
--- reads the same way, so the two never disagree about what "no icon" means.
for _, case in ipairs({ { name = 'no argument', args = {} },
                        { name = 'empty argument', args = { '' } } }) do
  extra = extra + 1
  local valid, errors = schema.validate_shortcode('iconify', case.args, {}, iconify_entry)
  local reported = false
  for _, message in ipairs(errors or {}) do
    if message:find('required', 1, true) then
      reported = true
    end
  end
  if not valid and reported then
    io.stdout:write('ok   iconify with ' .. case.name .. ' is reported as missing\n')
  else
    io.stdout:write('FAIL iconify with ' .. case.name .. ' is not reported as missing\n')
    failed = failed + 1
  end
end

io.stdout:write(string.format('\n%d checks, %d failed\n', #EXPECTED + 10 + extra, failed))
io.stdout:flush()
os.exit(failed == 0 and 0 or 1, true)
