--- Extension Test - Layer C, generated smoke.
---
--- Synthesises documents from what `_schema.yml` already declares: the
--- options, shortcodes, element attributes, classes and formats an extension
--- contributes. An extension that ships a schema therefore gains coverage
--- without writing a single test.
---
--- What a pass means here is narrow and worth stating plainly. The document
--- was generated, it rendered, no error was logged, no promoted warning
--- appeared, and no shortcode text survived into the output. Nothing about
--- the content of the output is asserted. Authored assertions are v2.

local util = require('util')
local schema = require('schema')
local values = require('values')
local emit = require('emit')

local M = {}

--- Documents generated per extension before the run gives up.
---
--- A pathological schema degrades into a reported cap rather than a hang.
M.DEFAULT_CAP = 200

--- How a generated document has to name the extension so Quarto loads it.
---
--- Only a shortcode is resolved without being asked for. Every other kind of
--- contribution needs the document to name it, and a generated document that
--- does not is rendered with the extension absent: it passes while proving
--- nothing, which is the failure this whole layer exists to catch.
---
--- A contributed format is consumed as `<extension>-<base>`, not as the bare
--- base name, so `contributes.formats: {pdf: ...}` on an extension named
--- `letter` is reached as `letter-pdf`.
--- @param ext_name string
--- @param manifest table parsed `_extension.yml`
--- @return table wiring {formats, filters, plugins}
local function contribution_wiring(ext_name, manifest)
  local contributes = (manifest or {}).contributes or {}
  local wiring = { formats = {}, filters = {}, plugins = {} }

  if type(contributes.formats) == 'table' then
    for _, key in ipairs(schema.key_order(contributes.formats)) do
      if key ~= 'common' then
        wiring.formats[#wiring.formats + 1] = ext_name .. '-' .. key
      end
    end
  end

  if type(contributes.filters) == 'table' and #contributes.filters > 0 then
    wiring.filters[#wiring.filters + 1] = ext_name
  end

  if type(contributes['revealjs-plugins']) == 'table' and #contributes['revealjs-plugins'] > 0 then
    wiring.plugins[#wiring.plugins + 1] = ext_name
    wiring.formats[#wiring.formats + 1] = 'revealjs'
  end

  if #wiring.formats == 0 then
    wiring.formats[1] = 'html'
  end

  return wiring
end

--- Front matter shared by every generated document.
---
--- The wiring is repeated on every document rather than set once in the test
--- project, because each document is rendered on its own by explicit path.
--- @param title string
--- @param wiring table
--- @return table
local function front_matter(title, wiring)
  local front = { title = title }
  local rendered = {}
  for _, format in ipairs(wiring.formats) do
    rendered[format] = {}
  end
  front.format = rendered
  if #wiring.filters > 0 then
    front.filters = wiring.filters
  end
  if #wiring.plugins > 0 then
    front['revealjs-plugins'] = wiring.plugins
  end
  front.test = { formats = wiring.formats }
  return front
end

--- A generated document waiting to be written.
local function document(name, front, body, note, kind, extension)
  return {
    name = name,
    front = front,
    body = body,
    note = note,
    kind = kind,
    extension = extension,
  }
end

--- Invocations of every declared shortcode, for use as document filler.
--- @param loaded table
--- @return string[]
local function shortcode_samples(loaded)
  local samples = {}
  for _, name in ipairs(schema.key_order(loaded.shortcodes or {})) do
    local entry = loaded.shortcodes[name]
    local positional = {}
    for _, argument in ipairs((entry or {}).arguments or {}) do
      local value, ok = values.derive(argument)
      if ok then
        positional[#positional + 1] = value
      end
    end
    samples[#samples + 1] = emit.shortcode(name, positional)
  end
  return samples
end

--- Build the documents for one extension.
--- @param ext table {name, dir, schema}
--- @param manifest table parsed `_extension.yml`
--- @param cap integer
--- @return table[] documents, table[] skips
function M.plan(ext, manifest, cap)
  local loaded = ext.schema
  local documents, skips = {}, {}
  if type(loaded) ~= 'table' then
    return documents, skips
  end

  local wiring = contribution_wiring(ext.name, manifest)
  local filler = shortcode_samples(loaded)

  local function add(doc)
    if #documents >= cap then
      if #skips == 0 or skips[#skips].reason ~= 'generation-cap-reached' then
        skips[#skips + 1] = {
          id = 'smoke/' .. ext.name .. '/cap',
          reason = 'generation-cap-reached',
          message = string.format('generation stopped at %d documents for `%s`', cap, ext.name),
        }
      end
      return
    end
    documents[#documents + 1] = doc
  end

  -- Options at their declared defaults, with nothing set. This is where an
  -- extension that reads its defaults out of its own schema breaks when the
  -- schema changes underneath it.
  if next(loaded.options or {}) ~= nil then
    add(document(
      string.format('%s-options-defaults', ext.name),
      front_matter('Options at their defaults', wiring),
      filler,
      'Generated: every option left unset, exercising the defaults path.',
      'options', ext.name))

    local derived, undecidable = values.derive_map(loaded.options)
    for _, entry in ipairs(undecidable) do
      skips[#skips + 1] = {
        id = string.format('smoke/%s/options/%s', ext.name, entry.key),
        reason = entry.reason,
        message = entry.pattern
          and string.format('no value satisfies `options.%s` (pattern `%s`)', entry.key, entry.pattern)
          or string.format('no value satisfies `options.%s`', entry.key),
      }
    end
    if next(derived) ~= nil then
      local front = front_matter('Options fully set', wiring)
      front.extensions = { [ext.name] = derived }
      add(document(
        string.format('%s-options-full', ext.name),
        front, filler,
        'Generated: every option set to a value its own descriptor accepts.',
        'options', ext.name))
    end
  end

  -- One document per shortcode, minimal and full.
  for _, name in ipairs(schema.key_order(loaded.shortcodes or {})) do
    local entry = loaded.shortcodes[name] or {}

    local minimal_positional = {}
    local minimal_ok = true
    for _, argument in ipairs(entry.arguments or {}) do
      if argument.required == true then
        local value, ok = values.derive(argument)
        if ok then
          minimal_positional[#minimal_positional + 1] = value
        else
          minimal_ok = false
        end
      end
    end
    local minimal_attributes = {}
    for _, key in ipairs(entry.required or {}) do
      local descriptor = (entry.attributes or {})[key]
      if type(descriptor) == 'table' then
        local value, ok = values.derive(descriptor)
        if ok then
          minimal_attributes[key] = value
        else
          minimal_ok = false
        end
      end
    end

    if minimal_ok then
      add(document(
        string.format('%s-shortcode-%s-minimal', ext.name, tostring(name):gsub('[^%w]+', '-')),
        front_matter(string.format('Shortcode %s, required only', name), wiring),
        { emit.shortcode(name, minimal_positional, minimal_attributes) },
        string.format('Generated: `%s` with its required arguments and attributes only.', name),
        'shortcode', ext.name))
    else
      skips[#skips + 1] = {
        id = string.format('smoke/%s/shortcode/%s/minimal', ext.name, name),
        reason = 'required-field-undecidable',
        message = string.format('a required argument or attribute of `%s` has no derivable value', name),
      }
    end

    local full_positional = {}
    for _, argument in ipairs(entry.arguments or {}) do
      local value, ok = values.derive(argument)
      if ok then
        full_positional[#full_positional + 1] = value
      end
    end
    local full_attributes, undecidable = values.derive_map(entry.attributes, function(_, descriptor)
      return descriptor.deprecated == nil or descriptor.deprecated == false
    end)
    for _, item in ipairs(undecidable) do
      skips[#skips + 1] = {
        id = string.format('smoke/%s/shortcode/%s/%s', ext.name, name, item.key),
        reason = item.reason,
        message = string.format('no value satisfies `shortcodes.%s.attributes.%s`', name, item.key),
      }
    end
    if #full_positional > 0 or next(full_attributes) ~= nil then
      add(document(
        string.format('%s-shortcode-%s-full', ext.name, tostring(name):gsub('[^%w]+', '-')),
        front_matter(string.format('Shortcode %s, fully specified', name), wiring),
        { emit.shortcode(name, full_positional, full_attributes) },
        string.format('Generated: `%s` with every declared argument and attribute.', name),
        'shortcode', ext.name))
    end
  end

  -- Element attributes, one document per declared group.
  for _, group in ipairs(schema.key_order(loaded.attributes or {})) do
    local derived = values.derive_map(loaded.attributes[group])
    if next(derived) ~= nil then
      local body = {}
      local lowered = tostring(group):lower()
      local is_element = lowered == 'div' or lowered == 'span' or lowered == 'code'
        or lowered == 'codeblock' or lowered == 'header'

      if group == '_any' then
        body[#body + 1] = emit.div({}, derived, 'Div content.')
        body[#body + 1] = emit.span({}, derived, 'Span content.')
        body[#body + 1] = '# Heading {' .. emit.attributes(derived) .. '}'
      elseif is_element then
        if lowered == 'span' or lowered == 'code' then
          body[#body + 1] = emit.span({}, derived, 'Span content.')
        elseif lowered == 'header' then
          body[#body + 1] = '# Heading {' .. emit.attributes(derived) .. '}'
        else
          body[#body + 1] = emit.div({}, derived, 'Div content.')
        end
      else
        -- A group key that is neither `_any` nor an element name may be read
        -- as a class or as an ID prefix; the extension decides. Both are
        -- emitted, because an attribute nothing matches is inert markup.
        body[#body + 1] = emit.div({ group }, derived, 'Div content.')
        body[#body + 1] = emit.div({}, derived, 'Div content.', group .. '-example')
      end

      add(document(
        string.format('%s-attributes-%s', ext.name, tostring(group):gsub('[^%w]+', '-')),
        front_matter(string.format('Attributes for %s', tostring(group)), wiring),
        body,
        string.format('Generated: the `%s` attribute group.', tostring(group)),
        'attributes', ext.name))
    end
  end

  -- Contributed classes.
  local class_names = schema.key_order(loaded.classes or {})
  if #class_names > 0 then
    local body = {}
    for _, class in ipairs(class_names) do
      body[#body + 1] = emit.div({ class }, {}, string.format('Content in `.%s`.', class))
      body[#body + 1] = emit.span({ class }, {}, 'Inline content.')
    end
    add(document(
      string.format('%s-classes', ext.name),
      front_matter('Contributed classes', wiring),
      body,
      'Generated: one block and one inline element per contributed class.',
      'classes', ext.name))
  end

  -- Format-specific options, one document per declared format.
  for _, format in ipairs(schema.key_order(loaded.formats or {})) do
    local derived = values.derive_map(loaded.formats[format])
    -- A `formats:` key names the base format, and the extension is reached
    -- through its own name, so the document has to ask for `<ext>-<base>`
    -- whenever the manifest contributes that base.
    --- @type string
    local target = format
    for _, contributed in ipairs(wiring.formats) do
      if contributed == ext.name .. '-' .. format then
        target = contributed
      end
    end
    local front = front_matter(string.format('Format %s', format),
      { formats = { target }, filters = wiring.filters, plugins = wiring.plugins })
    if next(derived) ~= nil then
      front.extensions = { [ext.name] = derived }
    end
    add(document(
      string.format('%s-format-%s', ext.name, tostring(format):gsub('[^%w]+', '-')),
      front, filler,
      string.format('Generated: the `%s` format section.', format),
      'format', ext.name))
  end

  -- A contributed project type needs a whole nested project to exercise, so
  -- it is named as a gap rather than half-generated.
  for _, project in ipairs(loaded.projects or {}) do
    skips[#skips + 1] = {
      id = string.format('smoke/%s/project/%s', ext.name, tostring(project)),
      reason = 'projects-not-generated',
      message = string.format('the `%s` project type is not generated in this version', tostring(project)),
    }
  end

  return documents, skips
end

--- Write planned documents into the generated directory.
--- @param tests string
--- @param documents table[]
--- @return string dir, string[] written relative paths, string|nil error
function M.write(tests, documents)
  local dir = util.join(tests, 'generated')
  util.remove_tree(dir)
  local written = {}
  for _, doc in ipairs(documents) do
    local relative = 'generated/' .. doc.name .. '.qmd'
    local text = emit.document(doc.front, doc.body, doc.note)
    local ok, err = util.write_file(util.join(tests, relative), text)
    if not ok then
      return dir, written, tostring(err)
    end
    written[#written + 1] = relative
  end
  return dir, written, nil
end

--- Remove the generated directory.
--- @param tests string
function M.clean(tests)
  util.remove_tree(util.join(tests, 'generated'))
end

return M
