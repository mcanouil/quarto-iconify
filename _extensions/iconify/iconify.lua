--[[
# MIT License
#
# Copyright (c) 2025 Mickaël Canouil
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
]]

--- @type function
local stringify = pandoc.utils.stringify

--- Ensure Iconify HTML dependencies are included.
--- @return nil
local function ensure_html_deps()
  quarto.doc.add_html_dependency({
    name = 'iconify',
    version = '3.0.0',
    scripts = { 'iconify-icon.min.js' }
  })
end

--- Check if a string is empty or nil.
--- @param s string|nil
--- @return boolean
local function is_empty(s)
  return s == nil or s == ''
end

--- Validate and convert size keyword to CSS font-size.
--- @param size string|nil
--- @return string
local function is_valid_size(size)
  if is_empty(size) then
    return ''
  end
  --- @type table<string, string>
  local size_table = {
    ["tiny"]         = "0.5em",
    ["scriptsize"]   = "0.7em",
    ["footnotesize"] = "0.8em",
    ["small"]        = "0.9em",
    ["normalsize"]   = "1em",
    ["large"]        = "1.2em",
    ["Large"]        = "1.5em",
    ["LARGE"]        = "1.75em",
    ["huge"]         = "2em",
    ["Huge"]         = "2.5em",
    ["1x"]           = "1em",
    ["2x"]           = "2em",
    ["3x"]           = "3em",
    ["4x"]           = "4em",
    ["5x"]           = "5em",
    ["6x"]           = "6em",
    ["7x"]           = "7em",
    ["8x"]           = "8em",
    ["9x"]           = "9em",
    ["10x"]          = "10em",
    ["2xs"]          = "0.625em",
    ["xs"]           = "0.75em",
    ["sm"]           = "0.875em",
    ["lg"]           = "1.25em",
    ["xl"]           = "1.5em",
    ["2xl"]          = "2em"
  }
  for key, value in pairs(size_table) do
    if key == size then
      return 'font-size: ' .. value .. ';'
    end
  end
  return 'font-size: ' .. size .. ';'
end

--- Get iconify option from arguments or metadata.
--- @param x string The option name to retrieve
--- @param arg table<string, any> Arguments table containing options
--- @param meta table<string, any> Document metadata table
--- @return string The option value as a string
local function get_iconify_options(x, arg, meta)
  --- @type string
  local arg_value = stringify(arg[x])
  if is_empty(meta['iconify']) or not is_empty(arg_value) then
    return arg_value
  end
  if not is_empty(meta['iconify'][x]) then
    return stringify(meta['iconify'][x])
  end
  return arg_value
end

--- Render an Iconify icon as a Pandoc RawInline for HTML output.
--- @param args table<integer, any> Icon arguments (icon set and name)
--- @param kwargs table<string, any> Key-value options for the icon
--- @param meta table<string, any> Document metadata
--- @return any Pandoc RawInline for HTML or Pandoc Null for other formats
function iconify(args, kwargs, meta)
  -- detect html (excluding epub which won't handle fa)
  if quarto.doc.is_format("html:js") then
    ensure_html_deps()
    --- @type string
    local icon = stringify(args[1])
    --- @type string
    local set = 'octicon'
    if not is_empty(meta['iconify']) and not is_empty(meta['iconify']['set']) then
      set = stringify(meta['iconify']['set'])
    end

    if #args > 1 and string.find(stringify(args[2]), ':') then
      quarto.log.warning(
        'Use "set:icon" or "set icon" syntax, not both! ' ..
        'Using "set:icon" syntax and discarding first argument!'
      )
      icon = stringify(args[2])
    end

    if string.find(icon, ":") then
      set = string.sub(icon, 1, string.find(icon, ":") - 1)
      icon = string.sub(icon, string.find(icon, ":") + 1)
    elseif #args > 1 then
      set = icon
      icon = stringify(args[2])
    end

    --- @type string
    local attributes = ' icon="' .. set .. ':' .. icon .. '"'
    --- @type string
    local default_label = 'Icon ' .. icon .. ' from ' .. set .. ' Iconify.design set.'

    --- @type string
    local size = is_valid_size(get_iconify_options("size", kwargs, meta))
    --- @type string
    local style = get_iconify_options("style", kwargs, meta)

    if is_empty(style) and not is_empty(size) then
      attributes = attributes .. ' style="' .. size .. '"'
    elseif not is_empty(style) and not is_empty(size) then
      attributes = attributes .. ' style="' .. style .. ';' .. size .. '"'
    elseif not is_empty(style) then
      attributes = attributes .. ' style="' .. style .. '"'
    end

    --- @type string
    local aria_label = stringify(kwargs["label"])
    if is_empty(aria_label) then
      aria_label =  ' aria-label="' .. default_label .. '"'
    else
      aria_label =  ' aria-label="' .. aria_label .. '"'
    end

    --- @type string
    local title = stringify(kwargs["title"])
    if is_empty(title) then
      title =  ' title="' .. default_label .. '"'
    else
      title =  ' title="' .. title .. '"'
    end

    attributes = attributes .. aria_label .. title

    --- @type string
    local width = get_iconify_options("width", kwargs, meta)
    if not is_empty(width) and is_empty(size) then
      attributes = attributes .. ' width="' .. width .. '"'
    end
    --- @type string
    local height = get_iconify_options("height", kwargs, meta)
    if not is_empty(height) and is_empty(size)  then
      attributes = attributes .. ' height="' .. height .. '"'
    end
    --- @type string
    local flip = get_iconify_options("flip", kwargs, meta)
    if not is_empty(flip) then
      attributes = attributes .. ' flip="' .. flip.. '"'
    end
    --- @type string
    local rotate = get_iconify_options("rotate", kwargs, meta)
    if not is_empty(rotate) then
      attributes = attributes .. ' rotate="' .. rotate .. '"'
    end

    --- @type string
    local inline = get_iconify_options("inline", kwargs, meta)
    if is_empty(inline) or inline ~= "false" then
      attributes = ' inline ' .. attributes
    end

    --- @type string
    local mode = get_iconify_options("mode", kwargs, meta)
    --- @type table<string, boolean>
    local valid_modes = { svg = true, style = true, bg = true, mask = true }
    if not is_empty(mode) and valid_modes[mode] then
      attributes = attributes .. ' mode="' .. mode .. '"'
    end

    return pandoc.RawInline(
      'html',
      '<iconify-icon role="img"' .. attributes .. '></iconify-icon>'
    )
  else
    return pandoc.Null()
  end
end

--- Render Quarto icon using the iconify function with preset styling.
--- @param args table<integer, any> Icon arguments (ignored as we're using a preset icon)
--- @param kwargs table<string, any>|nil Key-value options that might override default styling
--- @param meta table<string, any> Document metadata
--- @return any Pandoc RawInline for HTML or Pandoc Null for other formats
function iconify_quarto(args, kwargs, meta)
  --- @type table<integer, string>
  local quarto_args = { "simple-icons:quarto" }
  --- @type table<string, any>
  local quarto_kwargs = kwargs or {}
  quarto_kwargs["label"] = "Quarto icon"
  quarto_kwargs["title"] = "Quarto icon"
  --- @type string
  local quarto_colour = "color:#74aadb;"
  
  if not is_empty(quarto_kwargs["style"]) then
    --- @type string
    local style = stringify(quarto_kwargs["style"])
    if string.match(style, "color:[^;]+;") then
      quarto_kwargs["style"] = string.gsub(style, "color:[^;]+;", quarto_colour)
    else
      quarto_kwargs["style"] = quarto_colour .. style
    end
  else
    quarto_kwargs["style"] = quarto_colour
  end
  return iconify(quarto_args, quarto_kwargs, meta)
end

--- @type table<string, function>
return {
  ["iconify"] = iconify,
  ["quarto"] = iconify_quarto
}
