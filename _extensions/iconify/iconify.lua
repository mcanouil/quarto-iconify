local function ensureHtmlDeps()
  quarto.doc.addHtmlDependency({
    name = 'iconify',
    version = '2.2.1',
    scripts = {"iconify.min.js"},
    stylesheets = {"size.css"}
  })
end

local function isEmpty(s)
  return s == nil or s == ''
end

local function isValidSize(size)
  local validSizes = {
    "tiny", "scriptsize", "footnotesize", "small", "normalsize",
    "large", "Large", "LARGE", "huge", "Huge",
    "1x", "2x", "3x", "4x", "5x", "6x", "7x", "8x", "9x", "10x",
    "2xs", "xs", "sm", "lg", "xl", "2xl"
  }
  for _, v in ipairs(validSizes) do
    if v == size then
      return " iconify-" .. size
    end
  end
  return ""
end

return {
  ["iconify"] = function(args, kwargs)

    local set = "fluent-emoji"
    local icon = pandoc.utils.stringify(args[1])
    if #args > 1 then
      set = icon
      icon = pandoc.utils.stringify(args[2])
    end
    local size = isValidSize(pandoc.utils.stringify(kwargs["size"]))
    -- detect html (excluding epub which won't handle fa)
    if quarto.doc.isFormat("html:js") then
      ensureHtmlDeps()

      data_icon = ' data-icon="' .. set .. ':' .. icon .. '"'
      -- alt_text = ' aria-label="Icon ' .. icon .. ' from ' .. set .. ' set imported with Iconify"'
  
      if isEmpty(size) then
        return pandoc.RawInline(
          'html',
          '<span class="iconify-inline"' .. data_icon .. '"></span>'
        )
      else
        return pandoc.RawInline(
          'html',
          '<span class="iconify-inline' .. size .. '"' .. data_icon .. '"></span>'
        )
      end
    else
      return pandoc.Null()
    end
  end
}
