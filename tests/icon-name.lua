--- Checks that an icon set or icon name is accepted only when it is a safe
--- single path segment.
---
--- The name goes into the Iconify API path and into the Typst cache file
--- name. A value that carries a slash, a dot segment or a control character
--- therefore reaches the filesystem, and `../` writes the cached SVG outside
--- the cache directory.
---
--- Run with the Pandoc that Quarto ships, from the repository root:
---
---     quarto pandoc lua tests/icon-name.lua

local root = (arg and arg[0] or 'tests/icon-name.lua'):match('(.*/)tests/') or './'
local name = assert(dofile(root .. '_extensions/iconify/_modules/name.lua'))

--- Each case is the value, whether it is valid, and what it covers.
local CASES = {
  { 'octicon', true, 'a plain set name' },
  { 'fa6-brands', true, 'a single hyphen' },
  { 'exploding-head', true, 'a hyphenated icon name' },
  { 'mdi-light', true, 'a hyphen before a word' },
  { 'ic', true, 'a two-letter set' },
  { 'a', true, 'a single letter' },
  { '0', true, 'a single digit' },
  { 'fa6', true, 'a trailing digit' },
  { '', false, 'an empty string' },
  { 'fa6--brands', false, 'a double hyphen' },
  { '-octicon', false, 'a leading hyphen' },
  { 'octicon-', false, 'a trailing hyphen' },
  { 'Octicon', false, 'an upper-case letter' },
  { 'octicon icon', false, 'a space' },
  { 'octi_con', false, 'an underscore' },
  { '../../etc/passwd', false, 'a traversal path' },
  { '..', false, 'a dot segment on its own' },
  { 'octicon/mark', false, 'a slash' },
  { 'octicon.svg', false, 'a dot' },
  { 'octicon?x=1', false, 'a query separator' },
  { 'octicon#mark', false, 'a fragment separator' },
  { 'user@evil.example', false, 'a userinfo separator' },
  { 'octicon:mark', false, 'a colon' },
  { 'octicon%2Fmark', false, 'a percent escape' },
  { 'octicon\nmark', false, 'a newline' },
  { 'octicon\tmark', false, 'a tab' },
  { "octicon'mark", false, 'a single quote' },
}

local failed = 0

for _, case in ipairs(CASES) do
  local value, expected, description = case[1], case[2], case[3]
  local actual = name.is_valid(value)
  if actual ~= expected then
    io.stdout:write(string.format(
      'FAIL %s: expected %s, got %s\n',
      description,
      tostring(expected),
      tostring(actual)
    ))
    failed = failed + 1
  end
end

-- A missing name is its own case, because a nil inside the table above would
-- stop `ipairs` at that point.
if name.is_valid(nil) ~= false then
  io.stdout:write('FAIL no name at all: expected false\n')
  failed = failed + 1
end

if failed > 0 then
  io.stdout:write(string.format('%d of %d cases failed\n', failed, #CASES + 1))
  io.stdout:flush()
  os.exit(1, true)
end

io.stdout:write(string.format('OK: %d cases passed\n', #CASES + 1))
io.stdout:flush()
