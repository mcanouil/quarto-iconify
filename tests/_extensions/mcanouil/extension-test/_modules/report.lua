--- Extension Test - Result tree and report emission.
---
--- JSON is the canonical format because every downstream consumer is bash
--- and `jq`. TAP 13 is written alongside for humans and for CI systems that
--- already parse it, from the same tree, so the two can never disagree.

local M = {}

--- Ordered case statuses. A run is `fail` when any case failed, `pass` when
--- any passed, and `skip` when every case was skipped.
M.PASS = 'pass'
M.FAIL = 'fail'
M.SKIP = 'skip'

--- Create an empty result tree.
--- @param meta table framework, extension, quarto and environment metadata
--- @return table
function M.new(meta)
  return {
    version = 1,
    framework = meta.framework or {},
    extension = meta.extension or {},
    quarto = meta.quarto or {},
    environment = meta.environment or {},
    tier = meta.tier or 'render',
    cases = {},
  }
end

--- Count the advisories carried by a result tree.
--- @param results table
--- @return integer
function M.warning_count(results)
  local count = 0
  for _, case in ipairs(results.cases) do
    count = count + #((case.diagnostics or {}).warnings or {})
  end
  return count
end

--- Append a case.
---
--- `id` is a stable slash path, `<layer>/<kind>/<name>/<format>`, so two runs
--- can be diffed and the listing can deep-link a single case.
--- @param results table
--- @param case table
function M.add(results, case)
  assert(case.id, 'a case needs an id')
  assert(case.layer, 'a case needs a layer')
  assert(case.status, 'a case needs a status')
  case.diagnostics = case.diagnostics or { warnings = {}, errors = {} }
  -- Present and empty in v1 so v2 can fill it without a schema change
  -- downstream in publish-results.sh, build-index.sh, or the renderer.
  case.assertions = case.assertions or {}
  results.cases[#results.cases + 1] = case
end

--- Roll per-case results up into per-layer and overall summaries.
--- @param results table
--- @return table results
function M.finalise(results)
  local layers, order = {}, {}
  local total = { total = 0, pass = 0, fail = 0, skip = 0 }

  for _, case in ipairs(results.cases) do
    if not layers[case.layer] then
      layers[case.layer] = { total = 0, pass = 0, fail = 0, skip = 0 }
      order[#order + 1] = case.layer
    end
    local layer = layers[case.layer]
    layer.total = layer.total + 1
    layer[case.status] = (layer[case.status] or 0) + 1
    total.total = total.total + 1
    total[case.status] = (total[case.status] or 0) + 1
  end

  for _, name in ipairs(order) do
    local layer = layers[name]
    layer.status = (layer.fail > 0 and M.FAIL) or (layer.pass > 0 and M.PASS) or M.SKIP
  end

  results.layers = layers
  results.layer_order = order
  results.summary = total
  results.status = (total.fail > 0 and M.FAIL) or (total.pass > 0 and M.PASS) or M.SKIP
  return results
end

--- Serialise the tree as JSON.
--- @param results table
--- @return string
function M.to_json(results)
  return pandoc.json.encode(results)
end

--- A double-quoted YAML scalar, safe for any message.
--- @param value any
--- @return string
function M.yaml_scalar(value)
  local text = tostring(value or '')
    :gsub('\\', '\\\\')
    :gsub('"', '\\"')
    :gsub('\n', '\\n')
    :gsub('\r', '')
  return '"' .. text .. '"'
end

--- Serialise the tree as TAP 13.
--- @param results table
--- @return string
function M.to_tap(results)
  local out = { 'TAP version 13', '1..' .. #results.cases }
  for index, case in ipairs(results.cases) do
    local line
    if case.status == M.SKIP then
      line = string.format('ok %d - %s # SKIP %s', index, case.id,
        (case.failure and case.failure.reason) or 'skipped')
    elseif case.status == M.PASS then
      line = string.format('ok %d - %s', index, case.id)
    else
      line = string.format('not ok %d - %s', index, case.id)
    end
    out[#out + 1] = line
    for _, warning in ipairs((case.diagnostics or {}).warnings or {}) do
      out[#out + 1] = '# warning: ' .. tostring(warning)
    end
    if case.status == M.FAIL and case.failure then
      -- Quoted: a failure message routinely carries a colon, and a bare
      -- `message: ERROR: ...` is not the YAML a TAP consumer expects.
      out[#out + 1] = '  ---'
      out[#out + 1] = '  stage: ' .. M.yaml_scalar(case.failure.stage)
      out[#out + 1] = '  reason: ' .. M.yaml_scalar(case.failure.reason)
      if case.failure.message then
        out[#out + 1] = '  message: ' .. M.yaml_scalar(case.failure.message)
      end
      out[#out + 1] = '  ...'
    end
  end
  return table.concat(out, '\n') .. '\n'
end

--- A short human summary for stderr.
--- @param results table
--- @return string
function M.to_summary(results)
  local out = {}
  for _, name in ipairs(results.layer_order or {}) do
    local layer = results.layers[name]
    out[#out + 1] = string.format('  %-12s %s  %d passed, %d failed, %d skipped',
      name, layer.status == M.FAIL and 'FAIL' or (layer.status == M.PASS and 'ok  ' or 'skip'),
      layer.pass, layer.fail, layer.skip)
  end
  for _, case in ipairs(results.cases) do
    if case.status == M.FAIL then
      out[#out + 1] = string.format('  FAIL %s\n       %s: %s', case.id,
        case.failure and case.failure.stage or '?',
        case.failure and (case.failure.message or case.failure.reason) or '?')
    end
  end
  for _, case in ipairs(results.cases) do
    for _, warning in ipairs((case.diagnostics or {}).warnings or {}) do
      out[#out + 1] = string.format('  warn %s\n       %s', case.id, warning)
    end
  end
  local summary = results.summary or {}
  local warnings = M.warning_count(results)
  out[#out + 1] = string.format('  %s: %d cases, %d passed, %d failed, %d skipped, %d warnings',
    string.upper(results.status or '?'), summary.total or 0, summary.pass or 0,
    summary.fail or 0, summary.skip or 0, warnings)
  return table.concat(out, '\n') .. '\n'
end

--- GitHub Actions annotations, one per failure, so failures land on the diff.
--- @param results table
--- @return string
function M.to_annotations(results)
  local out = {}
  for _, case in ipairs(results.cases) do
    if case.status == M.FAIL then
      local file = (case.target and case.target.document) or ''
      local message = (case.failure and (case.failure.message or case.failure.reason)) or 'failed'
      if file ~= '' then
        out[#out + 1] = string.format('::error file=%s::%s: %s', file, case.id, message)
      else
        out[#out + 1] = string.format('::error::%s: %s', case.id, message)
      end
    end
  end
  if #out == 0 then
    return ''
  end
  return table.concat(out, '\n') .. '\n'
end

return M
