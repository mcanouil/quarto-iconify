--- Extension Test - Layer B, render.
---
--- Renders each test document to each of its formats and inspects what the
--- render leaves behind. Exit code alone is not enough: an extension that
--- fails to load logs a warning and still exits 0, which is precisely the
--- breakage a Quarto update causes. The `_quarto.tests` block of a document
--- chooses the formats, the log rule, and the assertions.

local util = require('util')
local stage = require('stage')
local frontmatter = require('frontmatter')
local cli = require('cli')
local log = require('log')
local assertions = require('assert')
local check = require('check')
local vocabulary = require('vocabulary')

local M = {}

--- Warnings that fail a case despite Quarto exiting 0.
---
--- Measured: an extension that is not resolved produces
--- `WARNING ... Shortcode 'probe' not found` and `Output created`, exit 0.
--- These fail a case under every policy, including `noErrors`, where other
--- warnings are allowed, because they mean the extension never ran.
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
    or relative:match('^node_modules/')
    or relative:match('/node_modules/')
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
--- @return table[] documents {relative, absolute, origin, default_policy, ignores_exhaustive}
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
      -- The demo documents the extension rather than testing it, so, as for
      -- a generated document, warnings are allowed and `exhaustive` does not
      -- apply.
      return { {
        relative = name, absolute = absolute, origin = 'demo',
        default_policy = 'noErrors', ignores_exhaustive = true,
      } }
    end
  end
  return {}
end

--- Why `q2 call test` cannot judge a document, or nil when it can.
--- @param options table
--- @param document table from `M.discover`
--- @param descriptors table `run.extension-test` descriptors
--- @return string|nil reason
local function q2_reason(options, document, descriptors)
  if document.origin == 'demo' then
    return 'the demo document is outside the tests project'
  end
  local info, inspect_err = cli.inspect(document.absolute, options.tests)
  if not info then
    return inspect_err
  end
  local spec, problem = frontmatter.spec(info.tests)
  if problem then
    return 'front-matter-invalid: ' .. problem
  end
  local stem = pandoc.path.filename(document.relative):gsub('%.qmd$', '')
  local settings, options_err = frontmatter.options(spec.run, descriptors, stem)
  if options_err then
    return '`run.extension-test` does not validate: ' .. options_err
  end
  return vocabulary.q2_selection(spec, settings).reason
end

--- Decide which discovered documents `q2 call test` can judge.
---
--- The front matter is read as `M.execute` reads it, from the staged project,
--- but nothing is rendered. `run.skip` is not a reason here, because q2 reads
--- `run` itself.
--- @param options table
--- @param descriptors table `run.extension-test` descriptors
--- @return table[] records {relative, absolute, included, reason}, in discovery order
function M.q2_documents(options, descriptors)
  local records = {}
  for _, document in ipairs(M.discover(options.root, options.tests)) do
    local reason = q2_reason(options, document, descriptors)
    records[#records + 1] = {
      relative = document.relative,
      absolute = document.absolute,
      included = reason == nil,
      reason = reason,
    }
  end
  return records
end

--- The first promoted warning among the log lines.
--- @param lines table[] from `log.read`
--- @return table|nil {reason, message}
function M.promoted(lines)
  for _, line in ipairs(lines) do
    if line.level == 'WARN' then
      for _, rule in ipairs(M.PROMOTED_WARNINGS) do
        if line.message:match(rule.pattern) then
          return { reason = rule.reason, message = line.message }
        end
      end
    end
  end
  return nil
end

--- Why the log fails the rule of a format, if it does.
---
--- Only what Quarto logged is judged. A note the runner adds to the case,
--- such as the one for an incomplete log record, is never passed in here.
--- @param policy string `noErrorsOrWarnings` or `noErrors`
--- @param errors string[] messages of the log lines at ERROR
--- @param warnings string[] messages of the log lines at WARN
--- @return string|nil reason
--- @return string|nil message
function M.log_failure(policy, errors, warnings)
  if #errors > 0 then
    return 'error-logged', errors[1]
  end
  if policy == 'noErrorsOrWarnings' and #warnings > 0 then
    return 'warning-logged', warnings[1]
  end
  return nil, nil
end

--- Where quarto-cli writes a kept `.typ` file: beside the input, named after
--- it, also when `output-file` or `output-dir` is set (measured).
--- @param document table
--- @return string
function M.kept_typ_path(document)
  return (document.absolute:gsub('%.qmd$', '.typ'))
end

--- The message of a failed render that left no error to quote.
M.NO_DIAGNOSTIC = 'the render failed with no diagnostic output'

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
  return headline or frame or M.NO_DIAGNOSTIC
end

--- Remove the regions of an output that quote code.
---
--- An extension documents itself by showing its own shortcode syntax, in a
--- fenced block or an inline span. Both reach the output as literal text that
--- looks exactly like a shortcode which failed to expand, so they are removed
--- before the scan. Quarto's `{{{< … >}}}` escape is not handled: it renders
--- to a literal `{{<` wherever it is written, and the same text in running
--- prose is indistinguishable from the failure this scan exists to find.
--- @param text string
--- @return string
local function without_code(text)
  -- HTML first, because a rendered code block is `<pre>` or `<code>` by then
  -- and the fence characters are long gone.
  text = text:gsub('<pre.-</pre>', ' ')
  text = text:gsub('<code.-</code>', ' ')
  -- Markdown and Typst outputs keep their fences and spans. Both are matched
  -- on a run of backticks closed by a run of the same length, because Pandoc
  -- widens the run when the quoted content holds backticks of its own, and a
  -- pattern fixed at three strips half of a wider one. Under-stripping here
  -- fails a case rather than missing one, so it is worth the care.
  -- The leading newline lets the pattern match a fence that opens the file.
  text = ('\n' .. text):gsub('\n(```+)[^\n]*\n.-\n%1', '\n')
  text = text:gsub('(`+)[^\n]-%1', ' ')
  return text
end

--- Whether an output file still holds unexpanded shortcode text.
---
--- A heuristic, and the secondary net: Quarto reports an unresolved shortcode
--- as a warning, which `PROMOTED_WARNINGS` fails on directly. A miss here
--- therefore costs a check rather than the whole layer.
--- @param path string
--- @return boolean
function M.has_unexpanded(path)
  local text = util.read_file(path)
  if not text then
    return false
  end
  text = without_code(text)
  for _, marker in ipairs(M.UNEXPANDED_MARKERS) do
    if text:find(marker, 1, true) then
      return true
    end
  end
  return false
end

--- Render one document to one format and judge the result.
---
--- The checks run in a fixed order, and the first one that fails gives the
--- reason of the case. Under `shouldError`, only the timeout check, the
--- `shouldError` check, and the `printsMessage` entries apply.
--- @param context table {tests, log_dir, settings, exhaustive, check, document, layer, output_files, output_dir, fallback_output_file}
--- @param target table a format entry from `frontmatter.spec`
--- @return table case
local function render_and_grade(context, target, typ)
  local document = context.document
  local settings = context.settings
  local layer = context.layer or 'render'
  local format = target.name
  local id = string.format('%s/%s/%s', layer, document.relative:gsub('%.qmd$', ''), format)
  -- The slug is lossy, so `a/b/html` and `a-b/html` would share a file.
  -- The sequence keeps every case's log distinct.
  context.sequence = (context.sequence or 0) + 1
  local slug = string.format('%03d-%s', context.sequence, id:gsub('[^%w]+', '-'))
  local log_path = util.join(context.log_dir, slug .. '.log')
  local console_path = util.join(context.log_dir, slug .. '.output.log')
  os.remove(log_path)
  os.remove(console_path)

  local output_file = context.output_files[format] or context.fallback_output_file
  -- A previous format wrote into the same directory. Every candidate is
  -- removed rather than the first one that exists, because a stale copy left
  -- in any of them would let a render that wrote nothing be read as a pass.
  for _, path in ipairs(M.output_candidates(context.tests, document, format, output_file,
    context.output_dir) or {}) do
    os.remove(path)
  end
  local output_is_typ = type(output_file) == 'string' and output_file:match('%.typ$') ~= nil
  -- A `.typ` file that is already there is not the render's to remove: it
  -- may be hand-written. Only one the render kept is removed, after grading.
  local typ_path = M.kept_typ_path(document)
  local typ_preexisting = false
  local base = format:match('([^%-]+)$') or format
  local is_typst = base == 'typst' or output_is_typ
  if base == 'typst' and not output_is_typ then
    typ_preexisting = util.exists(typ_path)
    typ.path, typ.remove = typ_path, not typ_preexisting
  end

  local started = os.time()
  local code, output = util.capture(cli.render_command(context.tests, document.absolute, format,
    log_path, settings.timeout))
  local elapsed = os.time() - started
  local lines, incomplete, log_missing = log.read(log_path)
  local errors, logged_warnings = log.messages_at(lines, 'ERROR'), log.messages_at(lines, 'WARN')
  -- The diagnostics hold the logged warnings and the notes of the runner.
  -- The log rule reads `logged_warnings` alone.
  local warnings = table.move(logged_warnings, 1, #logged_warnings, 1, {})
  if incomplete then
    warnings[#warnings + 1] = 'a log record could not be read and was ignored'
  end

  local case = {
    id = id,
    layer = layer,
    target = { kind = document.origin, document = document.relative, format = format },
    diagnostics = { errors = errors, warnings = warnings },
    assertions = {},
  }

  local function fail(stage_name, reason, message)
    case.status = 'fail'
    case.failure = { stage = stage_name, reason = reason, message = message, log = log_path }
    return case
  end

  local function grade_assertions(ctx, log_only)
    local entries, notes = assertions.evaluate(target.assertions, ctx, log_only)
    case.assertions = entries
    for _, note in ipairs(notes) do
      warnings[#warnings + 1] = note
    end
    -- The summary and the TAP read the case warnings, so an assertion that
    -- did not run, or that q2 rejects, is named there too.
    for _, entry in ipairs(entries) do
      if entry.status == 'skip' then
        warnings[#warnings + 1] = string.format('%s did not run: %s', entry.id, tostring(entry.message))
      end
      for _, warning in ipairs(entry.warnings or {}) do
        if not util.contains(warnings, warning) then
          warnings[#warnings + 1] = warning
        end
      end
    end
    local message = assertions.failure(entries)
    if message then
      return fail('assert', 'assertion-failed', message)
    end
    case.status = 'pass'
    return case
  end

  -- A timeout is the harness giving up, not the failure the document
  -- declares, so `shouldError` does not turn a stall into a pass.
  if util.timed_out(code, util.timeout_command() and settings.timeout, elapsed) then
    return fail('render', 'timeout', string.format('the render exceeded %s seconds', tostring(settings.timeout)))
  end

  -- With no log, the log rule cannot be judged, and an empty log would read
  -- as a clean one. That is a gap in this run, so the case is a skip. A
  -- render that exits with an error code is still judged on its exit code.
  if log_missing and code == 0 then
    case.status = 'skip'
    case.failure = {
      stage = 'log', reason = 'log-missing',
      message = 'Quarto wrote no log to ' .. log_path .. ', so the log rule cannot be checked',
    }
    return case
  end

  if target.policy == 'shouldError' then
    if code == 0 and #errors == 0 then
      return fail('log', 'unexpected-pass',
        'the case declares `shouldError` but the render exited 0 and logged no error')
    end
    return grade_assertions({ lines = lines }, true)
  end

  if code ~= 0 then
    local message = M.first_error(output, errors)
    fail('render', 'exit ' .. tostring(code), message)
    -- With nothing to quote, the console output is all there is to go on,
    -- so it is kept beside the log rather than lost with the run.
    if message == M.NO_DIAGNOSTIC then
      local written, err = util.write_file(console_path, output)
      if written then
        case.failure.output = console_path
      else
        warnings[#warnings + 1] = 'the console output could not be kept: ' .. tostring(err)
      end
    end
    return case
  end


  -- The render succeeded. Everything below is the difference between
  -- "Quarto exited 0" and "the extension actually did something".
  local promoted = M.promoted(lines)
  if promoted then
    return fail('assert', promoted.reason, promoted.message)
  end

  local log_reason, log_message = M.log_failure(target.policy, errors, logged_warnings)
  if log_reason then
    return fail('log', log_reason, log_message)
  end

  -- Under `exhaustive`, a `noErrors` format allows only the warnings that a
  -- `printsMessage` entry expects.
  if context.exhaustive and target.policy == 'noErrors' then
    local unexpected, unusable = assertions.unexpected_warnings(target.assertions, logged_warnings)
    if #unexpected > 0 then
      local message = unexpected[1]
      if #unusable > 0 then
        message = string.format('%s (%s)', message, table.concat(unusable, '; '))
      end
      return fail('log', 'unexpected-warning', message)
    end
  end

  local output_path, missing = M.output_path(context.tests, document, format, output_file, context.output_dir)
  if not output_path then
    case.status, case.failure = M.grade_missing(missing, format, log_path)
    return case
  end
  if M.has_unexpanded(output_path) then
    return fail('assert', 'shortcode-not-expanded',
      'the output still holds shortcode text, so the shortcode did not expand')
  end

  local prefix = context.tests .. '/'
  local output_label = output_path:sub(1, #prefix) == prefix and output_path:sub(#prefix + 1) or output_path
  local ctx = {
    lines = lines,
    output_path = output_path,
    output_label = output_label,
    output_dir = pandoc.path.directory(output_path),
    support_dir = pandoc.path.split_extension(output_path) .. '_files',
    -- Only a Typst render keeps a `.typ` file, so another format has none to
    -- read, whatever sits beside the document.
    typ_path = is_typst and (output_is_typ and output_path or typ_path) or nil,
    format = format,
    typ_preexisting = typ_preexisting,
    typ_label = output_is_typ and output_label or pandoc.path.filename(typ_path),
  }
  grade_assertions(ctx, false)
  if case.status ~= 'pass' or not context.check then
    return case
  end

  local result = check.run({
    tests = context.tests,
    command = context.check,
    timeout = settings.timeout,
    log_path = util.join(context.log_dir, slug .. '.check.log'),
    env = {
      EXTENSION_TEST_INPUT = document.absolute,
      EXTENSION_TEST_OUTPUT = output_path,
      EXTENSION_TEST_FORMAT = format,
      EXTENSION_TEST_CASE_ID = id,
    },
  })
  table.move(result.entries, 1, #result.entries, #case.assertions + 1, case.assertions)
  if result.status == 'timeout' or result.status == 'fail' then
    fail('check', result.status == 'timeout' and 'timeout' or 'check-failed', result.message)
    case.failure.log = result.log
  end
  return case
end

--- Render one document to one format, judge it, and remove the `.typ` file
--- the render kept for an assertion, whatever the outcome.
--- @param context table
--- @param target table
--- @return table case
local function render_one(context, target)
  local typ = {}
  local case = render_and_grade(context, target, typ)
  if typ.remove then
    os.remove(typ.path)
  end
  return case
end

--- Grade a render whose output could not be found.
---
--- An unknown suffix means there is nowhere to look, which is a gap in this
--- harness rather than a fault in the extension, so it stays a skip. Every
--- other reason is a failure: the render claimed success and produced nothing
--- to read, and reporting that as a skip is how a layer comes to assert nothing
--- inside a run that passes.
---
--- Separate from `render_one` so the mapping can be exercised. Nothing reaches
--- it through a fixture: a render that succeeds while writing nothing findable
--- was easy to construct when the harness guessed the output name, and is not
--- now that the name and the directory both come from `quarto inspect`.
---
--- @param missing string The reason `output_path` gave.
--- @param format string The format that was rendered.
--- @param log_path string|nil The render log, when one was written.
--- @return string status `skip` for an unplaceable format, otherwise `fail`.
--- @return table failure The failure record for the case.
function M.grade_missing(missing, format, log_path)
  local unplaceable = missing == 'unknown-suffix'
  return unplaceable and 'skip' or 'fail', {
    stage = 'assert',
    reason = missing,
    message = unplaceable
      and string.format('this harness does not know what file a `%s` render writes', format)
      or string.format('the render reported success but wrote no `%s` output to check', format),
    log = log_path,
  }
end

--- Where a render put its output.
---
--- @param tests string
--- @param document table
--- @param format string
--- @param output_file string|nil the name Quarto reports for this format
--- @param output_dir string|nil the output directory Quarto resolved
--- @return string|nil path
--- @return string|nil reason `unknown-suffix` when there is nowhere to look
function M.output_path(tests, document, format, output_file, output_dir)
  local candidates, reason = M.output_candidates(tests, document, format, output_file, output_dir)
  if not candidates then
    return nil, reason
  end
  for _, candidate in ipairs(candidates) do
    if util.exists(candidate) then
      return candidate, nil
    end
  end
  return nil, 'output-not-found'
end

--- Every path a render of this document and format could have written.
--- @return string[]|nil candidates
--- @return string|nil reason `unknown-suffix` when there is nowhere to look
function M.output_candidates(tests, document, format, output_file, output_dir)
  local extensions = {
    html = 'html', revealjs = 'html', typst = 'pdf', pdf = 'pdf',
    docx = 'docx', gfm = 'md', markdown = 'md', commonmark = 'md',
    latex = 'tex', beamer = 'pdf', pptx = 'pptx', epub = 'epub',
  }
  -- A contributed format is `<extension>-<base>`, so the trailing base name
  -- decides the suffix. There is deliberately no fallback: guessing `.html`
  -- finds the previous format's output in the same directory, and scanning
  -- the wrong file gives a false pass or blames the wrong format. A format
  -- this table does not know is still placed when Quarto reports a name
  -- carrying its own extension, because that name needs no guess.
  local base = format:match('([^%-]+)$') or format
  local suffix = extensions[format] or extensions[base]

  -- A document that sets `output-file` writes under that name rather than its
  -- own, and `quarto inspect` reports the name per format. Looking only for a
  -- file named after the document finds nothing in that case, which used to
  -- leave the layer asserting nothing while the run reported a pass. Quarto
  -- reports the name with or without the suffix, so one is added only when it
  -- is missing.
  local name
  if output_file and output_file ~= '' then
    name = output_file
    if suffix then
      if name:sub(-#suffix - 1) ~= '.' .. suffix then
        name = name .. '.' .. suffix
      end
    elseif not name:match('%.[%w]+$') then
      -- No mapped suffix and a reported name with no extension of its own
      -- leaves nothing to look for.
      return nil, 'unknown-suffix'
    end
  elseif suffix then
    name = (document.relative:match('([^/]+)%.qmd$') or 'index') .. '.' .. suffix
  else
    return nil, 'unknown-suffix'
  end

  -- `output-file` renames the file, never the directory it sits in.
  local relative_dir = document.relative:match('^(.*/)[^/]+%.qmd$') or ''
  local absolute_dir = document.absolute:match('^(.*[/\\])[^/\\]+%.qmd$') or ''
  local candidates = { absolute_dir .. name }
  if output_dir then
    candidates[#candidates + 1] = util.join(tests, output_dir, relative_dir .. name)
  end
  -- The defaults stay as a fallback, for a document inspected without a
  -- project or a Quarto that reports no directory.
  candidates[#candidates + 1] = util.join(tests, '_output', relative_dir .. name)
  candidates[#candidates + 1] = util.join(tests, '_site', relative_dir .. name)
  return candidates, nil
end

--- The output name to use for a format that `quarto inspect` does not report.
---
--- Quarto writes such a format under the document's top-level `output-file`.
--- A name set inside one format block does not apply to the others. Without
--- a top-level name, nil leaves `output_candidates` to add the suffix of the
--- format to the stem, or to report a format it cannot place.
--- @param path string absolute path of the document
--- @return string|nil
function M.fallback_output_file(path)
  local declared = frontmatter.document_output_file(path)
  if declared then
    return (pandoc.path.split_extension(declared))
  end
  return nil
end

--- The `render/_config` case, when the tests project sets a key it may not,
--- or when it cannot be inspected to find out. The leading underscore keeps
--- the id apart from a document, because `discover` skips such names.
--- @param tests string tests directory
--- @return table|nil case
function M.project_check(tests)
  local block, err = cli.project_tests(tests)
  if err then
    return {
      id = 'render/_config',
      layer = 'render',
      status = 'skip',
      failure = { stage = 'discover', reason = 'project-inspect-failed', message = err },
    }
  end
  local problem = frontmatter.project_problem(block)
  if problem then
    return {
      id = 'render/_config',
      layer = 'render',
      status = 'fail',
      failure = { stage = 'discover', reason = 'project-tests-keys', message = problem },
    }
  end
  return nil
end

--- Render a list of documents and judge each result.
---
--- Staging is the caller's responsibility, so the smoke layer can generate
--- documents into an already-staged project rather than staging twice.
--- @param options table
--- @param documents table[]
--- @param descriptors table `run.extension-test` descriptors
--- @param layer string which layer the cases belong to
--- @param emit function(case)
function M.execute(options, documents, descriptors, layer, emit)
  local log_dir = util.join(options.tests, '_results', 'logs')
  -- Quarto creates the parent of `--log` itself, but a run whose log cannot be
  -- written loses the log rule silently, so it is not left to undocumented
  -- behaviour.
  pcall(pandoc.system.make_directory, log_dir, true)
  local context = { tests = options.tests, log_dir = log_dir }

  for _, document in ipairs(documents) do
    local base_id = layer .. '/' .. document.relative:gsub('%.qmd$', '')
    local stem = pandoc.path.filename(document.relative):gsub('%.qmd$', '')
    local function emit_document(status, stage_name, reason, message, warnings)
      emit({
        id = base_id,
        layer = layer,
        status = status,
        target = { document = document.relative },
        diagnostics = { errors = {}, warnings = warnings or {} },
        failure = { stage = stage_name, reason = reason, message = message },
      })
    end

    local info, inspect_err = cli.inspect(document.absolute, options.tests)
    if not info then
      emit_document('fail', 'inspect', 'inspect-failed', inspect_err)
      goto continue
    end

    do
      local spec, problem = frontmatter.spec(info.tests)
      if problem then
        emit_document('fail', 'discover', 'front-matter-invalid', problem)
        goto continue
      end
      local run_warnings = frontmatter.unknown_run_keys(spec.run)
      local reason = frontmatter.skip_reason(spec.run)
      if reason then
        emit_document('skip', 'discover', 'skipped', reason, run_warnings)
        goto continue
      end
      local settings, options_err = frontmatter.options(spec.run, descriptors, stem)
      if options_err then
        emit_document('fail', 'inspect', 'options-invalid', options_err, run_warnings)
        goto continue
      end
      local exhaustive = settings.warnings == 'exhaustive' and not document.ignores_exhaustive
      if exhaustive then
        local has_no_errors = false
        for _, entry in ipairs(spec.formats) do
          if entry.policy == 'noErrors' then
            has_no_errors = true
            break
          end
        end
        if not has_no_errors then
          emit_document('fail', 'inspect', 'options-invalid',
            '`warnings: exhaustive` needs `noErrors` on at least one format, because q2 allows an expected warning only there',
            run_warnings)
          goto continue
        end
      end

      local default_policy = document.default_policy or 'noErrorsOrWarnings'
      local targets = spec.formats
      if not spec.has_format_keys then
        targets = {}
        for _, name in ipairs(info.formats) do
          targets[#targets + 1] = { name = name, policy = default_policy, assertions = {} }
        end
      end

      context.document = document
      context.settings = settings
      context.exhaustive = exhaustive
      context.check = document.origin == 'tests' and settings.check or nil
      context.layer = layer
      context.output_files = info.output_files
      context.output_dir = info.output_dir
      context.fallback_output_file = M.fallback_output_file(document.absolute)
      for _, target in ipairs(targets) do
        if target.problem then
          emit({
            id = base_id .. '/' .. target.name,
            layer = layer,
            status = 'fail',
            target = { kind = document.origin, document = document.relative, format = target.name },
            diagnostics = { errors = {}, warnings = run_warnings },
            failure = { stage = 'discover', reason = target.problem.reason, message = target.problem.message },
          })
        else
          local case = render_one(context, target)
          for _, warning in ipairs(run_warnings) do
            table.insert(case.diagnostics.warnings, warning)
          end
          emit(case)
        end
      end
    end

    ::continue::
  end
end

--- Run the render layer.
--- @param options table
--- @param descriptors table `run.extension-test` descriptors
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

  local staged, reason, message = stage.prepare(options.root, options.tests)
  if not staged then
    emit({
      id = 'render/stage',
      layer = 'render',
      status = reason == 'nothing-to-stage' and 'skip' or 'fail',
      failure = { stage = 'stage', reason = reason, message = message },
    })
    return
  end

  -- Inspected after staging, so the project is in the state the renders see.
  local config_case = M.project_check(options.tests)
  if config_case then
    emit(config_case)
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
