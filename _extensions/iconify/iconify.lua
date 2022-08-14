local function ensureHtmlDeps()
  quarto.doc.addHtmlDependency({
    name = 'iconify',
    version = '1.0.0-beta.2',
    scripts = {"iconify-icon.min.js"}
  })
end

local function isEmpty(s)
  return s == nil or s == ''
end

local function isValidSize(size)
  if isEmpty(size) then
    return ''
  end
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

return {
  ["iconify"] = function(args, kwargs)
    -- detect html (excluding epub which won't handle fa)
    if quarto.doc.isFormat("html:js") then
      ensureHtmlDeps()
      local set = "fluent-emoji"
      local icon = pandoc.utils.stringify(args[1])
      if #args > 1 then
        set = icon
        icon = pandoc.utils.stringify(args[2])
      end

      local attributes = ' icon="' .. set .. ':' .. icon .. '"'
      local label = '"Icon ' .. icon .. ' from ' .. set .. ' Iconify.design set."'

      local size = isValidSize(pandoc.utils.stringify(kwargs["size"]))
      if not isEmpty(size) then
        attributes = attributes .. ' style="' .. size .. '"'
      end

      local aria_label = pandoc.utils.stringify(kwargs["label"])
      if isEmpty(aria_label) then
        aria_label =  ' aria-label="' .. label .. '"'
      else 
        attributes = attributes .. aria_label
      end
      local title = pandoc.utils.stringify(kwargs["title"])
      if isEmpty(title) then
        title =  ' title="' .. label .. '"'
      else 
        attributes = attributes .. title
      end
      -- local style = pandoc.utils.stringify(kwargs["style"])
      -- if not isEmpty(style) then
      --   local attributes = attributes .. ' style="' .. style .. '"'
      -- end
      local width = pandoc.utils.stringify(kwargs["width"])
      if not isEmpty(width) and isEmpty(size) then
        attributes = attributes .. ' width="' .. width .. '"'
      end
      local height = pandoc.utils.stringify(kwargs["height"])
      if not isEmpty(height) and isEmpty(size)  then
        attributes = attributes .. ' height="' .. height .. '"'
      end
      local flip = pandoc.utils.stringify(kwargs["flip"])
      if not isEmpty(flip) then
        attributes = attributes .. ' flip="' .. flip.. '"'
      end
      local rotate = pandoc.utils.stringify(kwargs["rotate"])
      if not isEmpty(rotate) then
        attributes = attributes .. ' rotate="' .. rotate .. '"'
      end

      return pandoc.RawInline(
        'html',
        '<iconify-icon inline' .. attributes .. '></iconify-icon>'
      )
    else
      return pandoc.Null()
    end
  end
}
