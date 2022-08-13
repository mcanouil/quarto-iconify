local function ensureHtmlDeps()
  quarto.doc.addHtmlDependency({
    name = 'iconify',
    version = '2.2.1',
    scripts = {"iconify.min.js"}
  })
end

return {
  ["iconify"] = function(args, kwargs)

    local set = "fluent-emoji"
    local icon = pandoc.utils.stringify(args[1])
    if #args > 1 then
      set = icon
      icon = pandoc.utils.stringify(args[2])
    end
    
    -- detect html (excluding epub which won't handle fa)
    if quarto.doc.isFormat("html:js") then
      ensureHtmlDeps()
      data_icon = ' data-icon="' .. set .. ':' .. icon .. '"'
      -- alt_text = ' aria-label="Icon ' .. icon .. ' from ' .. set .. ' set imported with Iconify"'

      return pandoc.RawInline(
        'html',
        '<span class="iconify-inline"' .. data_icon .. '"></span>'
      )
    else
      return pandoc.Null()
    end
  end
}
