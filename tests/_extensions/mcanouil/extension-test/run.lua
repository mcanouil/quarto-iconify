--- Extension Test - Test runner for Quarto extensions.
--- @version 0.0.0
---
--- Run from a repository root:
---
---     quarto pandoc lua tests/_extensions/*/extension-test/run.lua
---
--- The runner drives Quarto rather than running inside it. That is not a
--- style choice: Quarto builds its extension registry while reading
--- `_quarto.yml`, before any `pre-render` script runs, so an extension staged
--- from inside a render is not seen by that render.

local script_dir = (function()
  local self = arg and arg[0]
  if not self then
    local info = debug.getinfo(1, 'S')
    self = info and info.source and info.source:gsub('^@', '')
  end
  local dir = pandoc.path.directory(self or '.')
  if pandoc.path.is_absolute(dir) then
    return dir
  end
  return pandoc.path.normalize(pandoc.path.join({ pandoc.system.get_working_directory(), dir }))
end)()

package.path = table.concat({
  pandoc.path.join({ script_dir, '_modules', '?.lua' }),
  pandoc.path.join({ script_dir, '_vendor', 'quarto-wizard', '?.lua' }),
  package.path,
}, ';')

local util = require('util')
local report = require('report')
local conformance = require('conformance')
local render = require('render')
local generate = require('generate')
local stage = require('stage')
local schema = require('schema')

--- The version the extension manifest declares. The release workflow rewrites
--- `_extension.yml`, and nothing rewrites a constant, so a constant here goes
--- stale at the first release and tells the catalogue the wrong thing.
local VERSION = (function()
  local text = util.read_file(pandoc.path.join({ script_dir, '_extension.yml' }))
  if not text then
    return 'unknown'
  end
  local ok, parsed = pcall(schema._parse_yaml_text, text)
  if not ok or type(parsed) ~= 'table' or parsed.version == nil then
    return 'unknown'
  end
  return tostring(parsed.version)
end)()
local LAYERS = { conformance = true, render = true, smoke = true }

local USAGE = [[
Test a Quarto extension.

Usage:
  quarto pandoc lua tests/_extensions/*/extension-test/run.lua [options]

Options:
  --root <dir>          Repository root. Default: the parent of the tests directory.
  --tests <dir>         Tests directory. Default: detected from this script's location.
  --layer <name>        conformance, render or smoke. Repeatable. Default: all.
  --severity <level>    strict or lenient. Default: strict.
  --max-generated <n>   Cap generated documents per extension. Default: 200.
  --keep-generated      Leave the generated documents in place for inspection.
  --json <path>         Write the result JSON. Default: tests/_results/results.json.
  --tap <path>          Write TAP 13. `-` means stdout. Default: stdout.
  --list                Print the plan and run nothing.
  --quiet               Suppress the human summary on stderr.
  --version             Print the framework version.
  --help                Print this message.

Exit codes:
  0  every case passed or was skipped
  1  at least one case failed
  2  the harness could not run
]]

--- Parse the command line.
--- @param argv string[]
--- @return table|nil options, string|nil error
local function parse_args(argv)
  local options = {
    layers = {},
    severity = 'strict',
    tap = '-',
    list = false,
    quiet = false,
    max_generated = 200,
    keep_generated = false,
  }

  local index = 1
  while index <= #argv do
    local flag = argv[index]
    --- Reading past the end silently leaves the option unset, so a mistyped
    --- invocation would write results somewhere the caller never asked for.
    local missing = false
    local function value()
      index = index + 1
      if argv[index] == nil then
        missing = true
      end
      return argv[index]
    end

    if flag == '--root' then
      options.root = value()
    elseif flag == '--tests' then
      options.tests = value()
    elseif flag == '--layer' then
      local name = value()
      if not name or not LAYERS[name] then
        return nil, string.format('unknown layer `%s`', tostring(name))
      end
      options.layers[#options.layers + 1] = name
    elseif flag == '--severity' then
      local level = value()
      if level ~= 'strict' and level ~= 'lenient' then
        return nil, string.format('unknown severity `%s`', tostring(level))
      end
      options.severity = level
    elseif flag == '--max-generated' then
      local count = tonumber(value())
      if not count or count < 1 then
        return nil, '--max-generated needs a positive integer'
      end
      options.max_generated = math.floor(count)
    elseif flag == '--keep-generated' then
      options.keep_generated = true
    elseif flag == '--json' then
      options.json = value()
    elseif flag == '--tap' then
      options.tap = value()
    elseif flag == '--list' then
      options.list = true
    elseif flag == '--quiet' then
      options.quiet = true
    elseif flag == '--version' then
      options.print_version = true
    elseif flag == '--help' or flag == '-h' then
      options.print_help = true
    else
      return nil, string.format('unknown option `%s`', tostring(flag))
    end
    if missing then
      return nil, string.format('`%s` needs a value', tostring(flag))
    end
    index = index + 1
  end

  if #options.layers == 0 then
    options.layers = { 'conformance', 'render', 'smoke' }
  end
  return options, nil
end

--- Resolve the tests directory and repository root.
---
--- The script lives at `<tests>/_extensions/<owner>/<name>/run.lua`, so the
--- tests directory is three levels up and the repository root is its parent.
--- Both are overridable, because the listing runs its own pinned copy against
--- a repository it did not install into.
---
--- Both are made absolute. The render layer inspects a document from inside
--- the tests directory, so a path relative to the caller's working directory
--- would name a file that is not there.
--- @param options table
local function resolve_paths(options)
  if not options.tests then
    local owner_dir = pandoc.path.directory(script_dir)
    local extensions_dir = pandoc.path.directory(owner_dir)
    options.tests = pandoc.path.directory(extensions_dir)
  end
  options.tests = util.absolute(options.tests)
  if not options.root then
    options.root = pandoc.path.directory(options.tests)
  end
  options.root = util.absolute(options.root)
  options.extension_dir = script_dir
end

--- Detect the Quarto version and channel.
--- @return table
local function quarto_environment()
  local code, output = util.capture('quarto --version')
  local version = util.trim(output)
  if code ~= 0 then
    version = 'unknown'
  end
  -- Quarto marks a pre-release with a four-part version or a `-` suffix.
  local channel = 'release'
  if version:match('%-') or version:match('^%d+%.%d+%.%d+%.%d+') then
    channel = 'prerelease'
  end
  return { version = version, channel = channel }
end

--- Read the `test:` descriptors the framework ships.
--- @param options table
--- @return table descriptors
local function load_test_descriptors(options)
  local loaded, load_err = schema.load_schema(util.join(options.extension_dir, 'test-schema.yml'))
  if loaded then
    return loaded.options
  end
  io.stderr:write('warning: cannot read the `test:` descriptors: ' .. tostring(load_err) .. '\n')
  return {}
end

--- Run the smoke layer: generate documents from each schema, render them,
--- and remove them again.
---
--- Generation happens inside the staged project, so the generated documents
--- resolve the extension under test exactly as an authored one would.
--- @param options table
--- @param extensions table[]
--- @param descriptors table
--- @param emit function(case)
local function run_smoke(options, extensions, descriptors, emit)
  local usable = {}
  for _, ext in ipairs(extensions) do
    if type(ext.schema) == 'table' then
      usable[#usable + 1] = ext
    end
  end

  if #usable == 0 then
    emit({
      id = 'smoke/discover',
      layer = 'smoke',
      status = 'skip',
      failure = {
        stage = 'discover',
        reason = 'no-usable-schema',
        message = 'no extension ships a v2 `_schema.yml` to generate from',
      },
    })
    return
  end

  local staged, stage_err = stage.stage(options.root, options.tests)
  if stage_err or #staged.names == 0 then
    -- Undone on the error path too: a part-copied extension left behind would
    -- be rendered by anything else that looks at the tree before the next run.
    stage.unstage(options.tests)
    emit({
      id = 'smoke/stage',
      layer = 'smoke',
      status = stage_err and 'fail' or 'skip',
      failure = {
        stage = 'stage',
        reason = stage_err and 'staging-failed' or 'nothing-to-stage',
        message = stage_err or 'the repository ships no extension to stage',
      },
    })
    return
  end

  local missing = stage.missing_project(options.tests)
  if missing then
    stage.unstage(options.tests)
    emit({
      id = 'smoke/stage',
      layer = 'smoke',
      status = 'fail',
      failure = { stage = 'stage', reason = 'no-project-file', message = missing },
    })
    return
  end

  local ok, err = pcall(function()
    local planned, skips = {}, {}
    for _, ext in ipairs(usable) do
      local documents, extension_skips = generate.plan(ext, ext.manifest, options.max_generated)
      for _, doc in ipairs(documents) do
        planned[#planned + 1] = doc
      end
      for _, skip in ipairs(extension_skips) do
        skips[#skips + 1] = skip
      end
    end

    -- Every skip is reported. A cap or an underivable value that went
    -- unmentioned would read as coverage that never happened.
    for _, skip in ipairs(skips) do
      emit({
        id = skip.id,
        layer = 'smoke',
        status = 'skip',
        failure = { stage = 'generate', reason = skip.reason, message = skip.message },
      })
    end

    if #planned == 0 then
      return
    end

    local _, written, write_err = generate.write(options.tests, planned)
    if write_err then
      emit({
        id = 'smoke/write',
        layer = 'smoke',
        status = 'fail',
        failure = { stage = 'generate', reason = 'write-failed', message = write_err },
      })
      return
    end

    local documents = {}
    for _, relative in ipairs(written) do
      documents[#documents + 1] = {
        relative = relative,
        absolute = util.join(options.tests, relative),
        origin = 'generated',
      }
    end
    render.execute(options, documents, descriptors, 'smoke', emit)
  end)

  if not options.keep_generated then
    generate.clean(options.tests)
  end
  stage.unstage(options.tests)

  if not ok then
    emit({
      id = 'smoke/harness',
      layer = 'smoke',
      status = 'fail',
      failure = { stage = 'generate', reason = 'harness-error', message = tostring(err) },
    })
  end
end

local function main(argv)
  local options, parse_err = parse_args(argv)
  if not options then
    io.stderr:write('error: ' .. parse_err .. '\n\n' .. USAGE)
    return 2
  end
  if options.print_help then
    io.write(USAGE)
    return 0
  end
  if options.print_version then
    io.write(VERSION, '\n')
    return 0
  end

  resolve_paths(options)

  if not util.is_dir(options.root) then
    io.stderr:write(string.format('error: repository root `%s` is not a directory\n', options.root))
    return 2
  end

  local results = report.new({
    framework = { name = 'extension-test', version = VERSION },
    extension = { root = options.root },
    quarto = quarto_environment(),
    environment = {
      severity = options.severity,
      tests = options.tests,
    },
  })

  if options.list then
    io.write(string.format('root:     %s\ntests:    %s\nlayers:   %s\nseverity: %s\n',
      options.root, options.tests, table.concat(options.layers, ', '), options.severity))
    for _, ext in ipairs(conformance.discover(options.root)) do
      io.write('extension: ', ext.name, '\n')
    end
    return 0
  end

  local function emit(entry)
    report.add(results, entry)
  end

  local extensions = {}
  if util.contains(options.layers, 'conformance') then
    extensions = conformance.run(options, emit)
  elseif util.contains(options.layers, 'smoke') then
    -- The smoke layer generates from the schema, so it has to be loaded even
    -- when the layer that reports on it was not asked for.
    extensions = conformance.load(options.root)
  else
    extensions = conformance.discover(options.root)
  end

  if util.contains(options.layers, 'render') then
    render.run(options, load_test_descriptors(options), emit)
  end

  if util.contains(options.layers, 'smoke') then
    run_smoke(options, extensions, load_test_descriptors(options), emit)
  end

  local names = {}
  for _, ext in ipairs(extensions) do
    names[#names + 1] = ext.name
  end
  results.extension.names = names

  report.finalise(results)

  local json_path = options.json or util.join(options.tests, '_results', 'results.json')
  local written, write_err = util.write_file(json_path, report.to_json(results) .. '\n')
  if not written then
    io.stderr:write('error: cannot write results: ' .. tostring(write_err) .. '\n')
    return 2
  end

  local tap = report.to_tap(results)
  if options.tap == '-' then
    io.write(tap)
  elseif options.tap then
    util.write_file(options.tap, tap)
  end

  if not options.quiet then
    io.stderr:write(report.to_summary(results))
  end

  if pandoc.system.environment()['GITHUB_ACTIONS'] == 'true' then
    io.stderr:write(report.to_annotations(results))
  end

  return results.status == report.FAIL and 1 or 0
end

os.exit(main(arg or {}), true)
