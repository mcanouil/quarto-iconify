--- Checks that a `style` attribute gives up its `color` declaration and no
--- other.
---
--- A search for `color:` anywhere in the string also matches inside
--- `background-color`, `border-color`, `outline-color` and the rest, which
--- painted the icon a colour the author never asked for.
---
--- Run with the Pandoc that Quarto ships, from the repository root:
---
---     quarto pandoc lua tests/style-colour.lua

local root = (arg and arg[0] or 'tests/style-colour.lua'):match('(.*/)tests/') or './'
local css = assert(dofile(root .. '_extensions/iconify/_modules/css.lua'))

--- Each case is the style value, the expected colour, and what it covers.
local CASES = {
  { 'color: firebrick', 'firebrick', 'the property on its own' },
  { 'color:firebrick', 'firebrick', 'no space after the colon' },
  { '  color : firebrick  ', 'firebrick', 'space around the name' },
  { 'COLOR: firebrick', 'firebrick', 'an upper-case property name' },
  { 'color: firebrick;', 'firebrick', 'a trailing semicolon' },
  { 'background-color: firebrick', '', 'background-color is not colour' },
  { 'border-color: firebrick', '', 'border-color is not colour' },
  { 'outline-color: firebrick', '', 'outline-color is not colour' },
  { 'text-decoration-color: firebrick', '', 'a long property name' },
  { 'background-color: firebrick; color: blue', 'blue', 'the real one after a decoy' },
  { 'color: blue; background-color: firebrick', 'blue', 'the real one before a decoy' },
  { 'color: red; color: blue', 'blue', 'the last declaration wins' },
  { 'color: red; color:', 'red', 'an empty value is invalid and ignored' },
  { 'color:', '', 'an empty value on its own' },
  { 'font-size: 2em', '', 'no colour at all' },
  { 'color: rgb(1, 2, 3)', 'rgb(1, 2, 3)', 'a function value' },
  { '', '', 'an empty string' },
}

local failed = 0

for _, case in ipairs(CASES) do
  local style, expected, description = case[1], case[2], case[3]
  local actual = css.declaration(style, 'color')
  if actual ~= expected then
    io.stdout:write(string.format(
      'FAIL %s: expected "%s", got "%s"\n',
      description,
      expected,
      actual
    ))
    failed = failed + 1
  end
end

-- A missing `style` attribute is its own case, because a nil inside the table
-- above would stop `ipairs` at that point.
if css.declaration(nil, 'color') ~= '' then
  io.stdout:write('FAIL no style at all: expected ""\n')
  failed = failed + 1
end

if failed > 0 then
  io.stdout:write(string.format('%d of %d cases failed\n', failed, #CASES + 1))
  io.stdout:flush()
  os.exit(1, true)
end

io.stdout:write(string.format("OK: %d cases passed\n", #CASES + 1))
io.stdout:flush()
