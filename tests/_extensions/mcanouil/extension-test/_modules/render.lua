--- Extension Test - Layer B, render.
---
--- Renders each test document to each of its formats and inspects what the
--- render leaves behind. Exit code alone is not enough: an extension that
--- fails to load logs a warning and still exits 0, which is precisely the
--- breakage a Quarto update causes and precisely what every existing check
--- in the ecosystem misses.

local util = require('util')
local stage = require('stage')
local frontmatter = require('frontmatter')

local M = {}

--- Warnings that fail a case despite Quarto exiting 0.
---
--- Measured: an extension that is not resolved produces
--- `WARNING ... Shortcode 'probe' not found` and `Output created`, exit 0.
--- A blanket "warnings never fail" rule would make this layer blind to the
--- one failure it exists to catch. Every other warning is recorded and does
--- not fail, because extensions warn legitimately all the time.
M.PROMOTED_WARNINGS = {
  { pattern = "Shortcode '[^']*' not found", reason = 'shortcode-not-found' },
  { pattern = 'Extension [^%s]* not found', reason = 'extension-not-found' },
  { pattern = "filter '[^']*' not found", reason = 'filter-not-found' },
}

--- Markers left in output when a shortcode did not expand.
---
--- HTML escapes the delimiters; Typst, LaTeX and markdown do not. Both forms
--- are checked because the same failure looks different per format.
M.UNEXPANDED_MARKERS = { '{{<', '{{&lt;' }

--- Documents that are never test inputs.
local function is_ignored(relative)
  return relative:match('^_')
    or relative:match('/_')
    or relative:match('^_extensions/')
    or relative:match('^generated/')
    or relative:match('^_results/')
    or relative:match('^_output/')
    or relative:match('^%.quarto/')
end

--- Collect `.qmd` documents under a directory, relative to it.
--- @param base string
--- @param prefix string|nil
--- @param found string[]|nil
--- @return string[]
local function collect(base, prefix, found)
  prefix = prefix or ''
  found = found or {}
  for _, name in ipairs(util.list_dir(base)) do
    local relative = prefix == '' and name or (prefix .. '/' .. name)
    local absolute = util.join(base, name)
    if util.is_dir(absolute) then
      if not is_ignored(relative .. '/') then
        collect(absolute, relative, found)
      end
    elseif name:match('%.qmd$') and not is_ignored(relative) then
      found[#found + 1] = relative
    end
  end
  return found
end

--- Decide what to render.
---
--- A repository with no authored test document still gets a working layer
--- from its own demo file, so `--init` alone is enough to be testing
--- something. `docs/` is never a candidate: it documents the extension rather
--- than exercising it, and it often stages the extension with a script this
--- runner knows nothing about.
--- @param root string
--- @param tests string
--- @return table[] documents {relative, absolute, origin}
function M.discover(root, tests)
  local documents = {}
  for _, relative in ipairs(collect(tests)) do
    documents[#documents + 1] = {
      relative = relative,
      absolute = util.join(tests, relative),
      origin = 'tests',
    }
  end
  if #documents > 0 then
    return documents
  end

  for _, name in ipairs({ 'example.qmd', 'template.qmd' }) do
    local absolute = util.join(root, name)
    if util.exists(absolute) then
      return { { relative = name, absolute = absolute, origin = 'demo' } }
    end
  end
  return {}
end

--- Formats Quarto reports for a document.
--- @param document string absolute path
--- @param cwd string directory to inspect from
--- @return string[] formats
--- @return string|nil error
function M.formats(document, cwd)
  local command = string.format('cd %s && quarto inspect %s',
    util.shell_quote(cwd), util.shell_quote(document))
  local code, output = util.capture(command)
  if code ~= 0 then
    return {}, 'quarto inspect failed: ' .. util.trim(output)
  end
  local ok, parsed = pcall(pandoc.json.decode, output, false)
  if not ok or type(parsed) ~= 'table' or type(parsed.formats) ~= 'table' then
    return {}, 'quarto inspect returned no formats'
  end
  return util.sorted_keys(parsed.formats), nil
end

--- Scan a render log for errors and promoted warnings.
--- @param log_path string
--- @return string[] errors, string[] warnings, table|nil promoted
function M.scan_log(log_path)
  local errors, warnings = {}, {}
  local promoted = nil
  local text = util.read_file(log_path)
  if not text then
    return errors, warnings, promoted
  end
  for _, line in ipairs(util.lines(text)) do
    if line:match('^ERROR') or line:match('ERROR:') then
      errors[#errors + 1] = util.trim(line)
    elseif line:match('WARNING') or line:match('^warning') then
      warnings[#warnings + 1] = util.trim(line)
      for _, rule in ipairs(M.PROMOTED_WARNINGS) do
        if line:match(rule.pattern) and not promoted then
          promoted = { reason = rule.reason, message = util.trim(line) }
        end
      end
    end
  end
  return errors, warnings, promoted
end

--- The most informative line of a failed render.
---
--- Quarto reports a Lua failure as a message followed by a stack trace, and
--- the trace is the least useful part. The frame naming a file inside the
--- extension under test is the most useful, because it points at the line the
--- author has to change, so it is preferred when present.
--- @param output string combined command output
--- @param errors string[] error lines already scanned from the log
--- @return string
function M.first_error(output, errors)
  if #errors > 0 then
    return errors[1]
  end
  local headline, frame
  for _, line in ipairs(util.lines(output)) do
    local trimmed = util.trim(line)
    if trimmed ~= '' and not headline
      and (trimmed:match('^[Ee]rror') or trimmed:match('^ERROR')) then
      headline = trimmed
    end
    if not frame and trimmed:match('_extensions/') and trimmed:match(':%d+:') then
      frame = trimmed
    end
  end
  if headline and frame then
    return headline .. ' (' .. frame .. ')'
  end
  return headline or frame or 'the render failed with no diagnostic output'
end

--- Whether an output file still holds unexpanded shortcode text.
--- @param path string
--- @return boolean
function M.has_unexpanded(path)
  local text = util.read_file(path)
  if not text then
    return false
  end
  for _, marker in ipairs(M.UNEXPANDED_MARKERS) do
    if text:find(marker, 1, true) then
      return true
    end
  end
  return false
end

--- Render one document to one format and judge the result.
--- @param context table {tests, log_dir, settings, document}
--- @param format string
--- @return table case
local function render_one(context, format)
  local document = context.document
  local settings = context.settings
  local layer = context.layer or 'render'
  local id = string.format('%s/%s/%s', layer, document.relative:gsub('%.qmd$', ''), format)
  -- The slug is lossy, so `a/b/html` and `a-b/html` would share a file.
  -- The sequence keeps every case's log distinct.
  context.sequence = (context.sequence or 0) + 1
  local slug = string.format('%03d-%s', context.sequence, id:gsub('[^%w]+', '-'))
  local log_path = util.join(context.log_dir, slug .. '.log')

  local command = string.format(
    'cd %s && %squarto render %s --to %s --log %s --log-level info',
    util.shell_quote(context.tests), util.timeout_prefix(settings.timeout),
    util.shell_quote(document.absolute), util.shell_quote(format),
    util.shell_quote(log_path))

  -- A previous format wrote into the same directory. Removing the output
  -- first means a missing file after the render is a fact, not a leftover.
  local expected = M.output_path(context.tests, document, format)
  if expected then
    os.remove(expected)
  end

  local code, output = util.capture(command)
  local errors, warnings, promoted = M.scan_log(log_path)

  local case = {
    id = id,
    layer = layer,
    target = {
      kind = document.origin,
      document = document.relative,
      format = format,
    },
    diagnostics = { errors = errors, warnings = warnings },
  }

  local function fail(stage_name, reason, message)
    case.status = 'fail'
    case.failure = { stage = stage_name, reason = reason, message = message, log = log_path }
  end

  local expects_failure = settings.expect == 'fail'

  -- A timeout is the harness giving up, not the failure the document
  -- declares, so `expect: fail` does not turn a stall into a pass.
  if code == 124 then
    fail('render', 'timeout', string.format('the render exceeded %s seconds', tostring(settings.timeout)))
    return case
  end

  if code ~= 0 then
    if expects_failure then
      case.status = 'pass'
      return case
    end
    fail('render', 'exit ' .. tostring(code), M.first_error(output, errors))
    return case
  end

  -- The render succeeded. Everything below is the difference between
  -- "Quarto exited 0" and "the extension actually did something".
  if promoted then
    if expects_failure then
      case.status = 'pass'
      return case
    end
    fail('assert', promoted.reason, promoted.message)
    return case
  end

  if settings.strict ~= false and #errors > 0 then
    if expects_failure then
      case.status = 'pass'
      return case
    end
    fail('log', 'error-logged', errors[1])
    return case
  end

  local output_path = M.output_path(context.tests, document, format)
  if not output_path then
    case.status = 'skip'
    case.failure = {
      stage = 'assert',
      reason = 'output-not-found',
      message = string.format('the render reported success but no `%s` output was found to check', format),
      log = log_path,
    }
    return case
  end
  if M.has_unexpanded(output_path) then
    if expects_failure then
      case.status = 'pass'
      return case
    end
    fail('assert', 'shortcode-not-expanded',
      'the output still holds shortcode text, so the shortcode did not expand')
    return case
  end

  if expects_failure then
    case.status = 'fail'
    case.failure = {
      stage = 'assert',
      reason = 'unexpected-pass',
      message = 'the case declares `expect: fail` but the render succeeded',
      log = log_path,
    }
    return case
  end

  case.status = 'pass'
  return case
end

--- Guess where a render put its output.
---
--- Only used for the unexpanded-shortcode scan, so a miss costs a check
--- rather than a false failure.
--- @param tests string
--- @param document table
--- @param format string
--- @return string|nil
function M.output_path(tests, document, format)
  local extensions = {
    html = 'html', revealjs = 'html', typst = 'pdf', pdf = 'pdf',
    docx = 'docx', gfm = 'md', markdown = 'md', commonmark = 'md',
    latex = 'tex', beamer = 'pdf', pptx = 'pptx', epub = 'epub',
  }
  -- A contributed format is `<extension>-<base>`, so the trailing base name
  -- decides the suffix. There is deliberately no fallback: guessing `.html`
  -- finds the previous format's output in the same directory, and scanning
  -- the wrong file gives a false pass or blames the wrong format.
  local base = format:match('([^%-]+)$') or format
  local suffix = extensions[format] or extensions[base]
  if not suffix then
    return nil
  end

  local relative = document.relative:gsub('%.qmd$', '') .. '.' .. suffix
  local candidates = {
    document.absolute:gsub('%.qmd$', '') .. '.' .. suffix,
    util.join(tests, '_output', relative),
    util.join(tests, '_site', relative),
  }
  for _, candidate in ipairs(candidates) do
    if util.exists(candidate) then
      return candidate
    end
  end
  return nil
end

--- Render a list of documents and judge each result.
---
--- Staging is the caller's responsibility, so the smoke layer can generate
--- documents into an already-staged project rather than staging twice.
--- @param options table
--- @param documents table[]
--- @param descriptors table `test:` descriptors
--- @param layer string which layer the cases belong to
--- @param emit function(case)
function M.execute(options, documents, descriptors, layer, emit)
  local log_dir = util.join(options.tests, '_results', 'logs')
  -- Quarto creates the parent of `--log` itself, but a run whose log cannot be
  -- written loses the promoted-warning check silently, so it is not left to
  -- undocumented behaviour.
  pcall(pandoc.system.make_directory, log_dir, true)
  local defaults = frontmatter.project_defaults(options.tests)
  local context = { tests = options.tests, log_dir = log_dir }

  for _, document in ipairs(documents) do
    local settings, warnings = frontmatter.read(document.absolute, descriptors, defaults)
    local base_id = layer .. '/' .. document.relative:gsub('%.qmd$', '')

    if settings.skip and settings.skip ~= false then
      emit({
        id = base_id,
        layer = layer,
        status = 'skip',
        target = { document = document.relative },
        diagnostics = { errors = {}, warnings = warnings },
        failure = {
          stage = 'discover',
          reason = 'skipped',
          message = type(settings.skip) == 'string' and settings.skip or 'the document declares `skip`',
        },
      })
      goto continue
    end

    do
      local available, inspect_err = M.formats(document.absolute, options.tests)
      if inspect_err then
        emit({
          id = base_id,
          layer = layer,
          status = 'fail',
          target = { document = document.relative },
          diagnostics = { errors = {}, warnings = warnings },
          failure = { stage = 'inspect', reason = 'inspect-failed', message = inspect_err },
        })
        goto continue
      end

      local targets = available
      if settings.formats then
        targets = {}
        for _, wanted in ipairs(settings.formats) do
          if util.contains(available, wanted) then
            targets[#targets + 1] = wanted
          else
            emit({
              id = base_id .. '/' .. wanted,
              layer = layer,
              status = 'fail',
              target = { document = document.relative, format = wanted },
              diagnostics = { errors = {}, warnings = warnings },
              failure = {
                stage = 'inspect',
                reason = 'format-not-available',
                message = string.format('the document declares `%s`, which Quarto does not report for it', wanted),
              },
            })
          end
        end
      end

      for _, format in ipairs(targets) do
        context.settings = settings
        context.document = document
        context.layer = layer
        local case = render_one(context, format)
        for _, warning in ipairs(warnings) do
          table.insert(case.diagnostics.warnings, warning)
        end
        emit(case)
      end
    end

    ::continue::
  end
end

--- Run the render layer.
--- @param options table
--- @param descriptors table `test:` descriptors
--- @param emit function(case)
function M.run(options, descriptors, emit)
  local documents = M.discover(options.root, options.tests)
  if #documents == 0 then
    emit({
      id = 'render/discover',
      layer = 'render',
      status = 'skip',
      failure = {
        stage = 'discover',
        reason = 'no-test-document',
        message = 'no `tests/*.qmd`, `example.qmd` or `template.qmd` to render',
      },
    })
    return
  end

  local staged, stage_err = stage.stage(options.root, options.tests)
  if stage_err then
    -- A part-copied extension left in the tree would be rendered by any other
    -- tool that looks at it before the next run cleans up.
    stage.unstage(options.tests)
    emit({
      id = 'render/stage',
      layer = 'render',
      status = 'fail',
      failure = { stage = 'stage', reason = 'staging-failed', message = stage_err },
    })
    return
  end
  if #staged.names == 0 then
    emit({
      id = 'render/stage',
      layer = 'render',
      status = 'skip',
      failure = {
        stage = 'stage',
        reason = 'nothing-to-stage',
        message = 'the repository ships no extension to stage',
      },
    })
    return
  end

  local missing = stage.missing_project(options.tests)
  if missing then
    stage.unstage(options.tests)
    emit({
      id = 'render/stage',
      layer = 'render',
      status = 'fail',
      failure = { stage = 'stage', reason = 'no-project-file', message = missing },
    })
    return
  end

  local ok, err = pcall(M.execute, options, documents, descriptors, 'render', emit)

  stage.unstage(options.tests)

  if not ok then
    emit({
      id = 'render/harness',
      layer = 'render',
      status = 'fail',
      failure = { stage = 'render', reason = 'harness-error', message = tostring(err) },
    })
  end
end

return M
