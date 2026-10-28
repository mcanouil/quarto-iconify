--- Extension Test - Layer A, conformance.
---
--- Generalises the reference conformance sweep from "walk directories looking
--- for `_schema.yml`" into "check the extensions of one repository". Two
--- defects in that reference are fixed here. It iterated with `pairs()`, so
--- its findings reordered between runs and could not be diffed; every
--- iteration below goes through `schema.key_order` or a sorted key list.
--- And it exited non-zero both when it found problems and when it found no
--- schemas at all, conflating a failure with a skip.

local util = require('util')
local schema = require('schema')

local M = {}

--- Schema file names, in Quarto's own resolution order. A JSON schema wins
--- over YAML in the same directory. The reference parser reads pretty-printed
--- JSON correctly, so all three take the same path.
local SCHEMA_FILENAMES = { '_schema.json', '_schema.yml', '_schema.yaml' }

--- Contribution keys observed across the published extension corpus.
--- Unrecognised keys warn rather than fail: the full set Quarto accepts has
--- not been confirmed against the CLI source.
local KNOWN_CONTRIBUTIONS = {
  'shortcodes', 'filters', 'formats', 'project', 'metadata',
  'revealjs-plugins', 'engines', 'brand',
}

--- Types the v2 vocabulary allows.
local V2_TYPES = {
  string = true, number = true, integer = true, boolean = true,
  array = true, object = true, ['null'] = true, content = true,
}

--- Keywords that only ever appeared in the v1 vocabulary.
local V1_ONLY = { 'min', 'max', 'enum-case-insensitive', 'element-attributes', 'pattern-exact' }

--- Keys a shortcode entry may carry; the meta-schema forbids the rest.
local SHORTCODE_KEYS = { description = true, arguments = true, attributes = true, required = true }

--- Pandoc elements an attribute group may name.
local ELEMENTS = { div = true, span = true, code = true, codeblock = true, header = true }

--- Find the extensions a repository ships.
---
--- Only `<root>/_extensions/<name>/` counts. A vendored copy under `docs/` or
--- a staged copy under `tests/` documents or exercises an extension rather
--- than being one, and including either would report another author's
--- problems as this repository's.
--- @param root string repository root
--- @return table[] list of {name, dir}
function M.discover(root)
  local base = util.join(root, '_extensions')
  local found = {}
  for _, name in ipairs(util.list_dir(base)) do
    local dir = util.join(base, name)
    if util.is_dir(dir) and util.exists(util.join(dir, '_extension.yml')) then
      found[#found + 1] = { name = name, dir = dir }
    end
  end
  return found
end

--- Resolve an extension's schema file, in Quarto's order.
--- @param dir string
--- @return string|nil path
local function find_schema(dir)
  for _, name in ipairs(SCHEMA_FILENAMES) do
    local path = util.join(dir, name)
    if util.exists(path) then
      return path
    end
  end
  return nil
end

--- Classify a schema's declared vocabulary.
--- @param path string
--- @return string version one of v2, v1, unknown, missing
--- @return string|nil detail
local function schema_vocabulary(path)
  local text = util.read_file(path) or ''
  local declared = text:match('%$schema%s*:%s*["\']?([^"\'%s]+)')
  if declared then
    if declared == schema.SCHEMA_VERSION then
      return 'v2', declared
    end
    if declared:find('/v1/', 1, true) then
      return 'v1', declared
    end
    return 'unknown', declared
  end
  for _, keyword in ipairs(V1_ONLY) do
    if text:match('%f[%w-]' .. keyword:gsub('%-', '%%-') .. '%s*:') then
      return 'v1', 'inferred from `' .. keyword .. '`'
    end
  end
  return 'missing', nil
end

--- Build a case table.
local function case(id, status, message, stage, reason)
  local entry = { id = id, layer = 'conformance', status = status }
  if status ~= 'pass' then
    entry.failure = { stage = stage or 'conformance', reason = reason or 'invalid', message = message }
  end
  return entry
end

--- Build an advisory: a passing case carrying a warning.
---
--- An advisory reports a real problem without failing the run. It is the
--- right shape for a finding the extension's author should act on but which
--- does not make the extension wrong, and for a finding whose rule the
--- framework is not yet confident enough to enforce.
local function advisory(id, message)
  return {
    id = id,
    layer = 'conformance',
    status = 'pass',
    diagnostics = { warnings = { message }, errors = {} },
  }
end

--- Check one extension's `_extension.yml`.
--- @param ext table {name, dir}
--- @param manifest_schema table descriptors from manifest-schema.yml
--- @param emit function(case)
local function check_manifest(ext, manifest_schema, emit)
  local path = util.join(ext.dir, '_extension.yml')
  local id = 'conformance/manifest/' .. ext.name

  local text, read_err = util.read_file(path)
  if not text then
    emit(case(id, 'fail', read_err, 'discover', 'manifest-unreadable'))
    return nil
  end

  local parsed = schema._parse_yaml_text(text)
  if type(parsed) ~= 'table' then
    emit(case(id, 'fail', 'the manifest is not a YAML mapping', 'discover', 'manifest-unparseable'))
    return nil
  end

  local valid, errors, warnings = schema.validate(parsed, manifest_schema, { unknown = 'ignore' })
  if not valid then
    emit(case(id, 'fail', table.concat(util.sorted_messages(errors), '; '), 'conformance', 'manifest-invalid'))
  else
    emit(case(id, 'pass'))
  end
  for index, warning in ipairs(util.sorted_messages(warnings)) do
    emit(advisory(string.format('%s/warning/%d', id, index), warning))
  end

  local contributes = parsed.contributes
  if type(contributes) == 'table' then
    for _, key in ipairs(util.sorted_keys(contributes)) do
      if not util.contains(KNOWN_CONTRIBUTIONS, key) then
        -- Advisory, not a failure: the full set of contribution keys Quarto
        -- accepts has not been confirmed against the CLI source, so an
        -- unrecognised key is more likely a gap here than a defect there.
        emit(advisory('conformance/contributes/' .. ext.name .. '/' .. key,
          string.format('unrecognised contribution `%s`', key)))
      end
    end
    M.check_contributed_paths(ext, contributes, emit)
  end

  return parsed
end

--- Every file a `contributes` shortcode or filter names must exist.
---
--- A rename that a render would only surface for one format shows up here for
--- every extension, before anything is rendered at all. Limited to the two
--- kinds that name a Lua file directly: `formats`, `revealjs-plugins` and
--- `brand` reference their resources in other ways and are not checked.
--- @param ext table
--- @param contributes table
--- @param emit function
function M.check_contributed_paths(ext, contributes, emit)
  local function check_one(kind, value)
    local path
    if type(value) == 'string' then
      path = value
    elseif type(value) == 'table' and type(value.path) == 'string' then
      -- Quarto also accepts `{at: pre|post, path: <file>}` for filters.
      path = value.path
    else
      return
    end
    if path:match('^%a+://') then
      return
    end
    local id = string.format('conformance/path/%s/%s/%s', ext.name, kind, path)
    if util.exists(util.join(ext.dir, path)) then
      emit(case(id, 'pass'))
    else
      emit(case(id, 'fail', string.format('`contributes.%s` names `%s`, which does not exist', kind, path),
        'conformance', 'missing-contributed-file'))
    end
  end

  for _, kind in ipairs({ 'shortcodes', 'filters' }) do
    local entries = contributes[kind]
    if type(entries) == 'table' then
      for _, value in ipairs(entries) do
        check_one(kind, value)
      end
    end
  end
end

--- Check one extension's `_schema.yml`.
--- @param ext table
--- @param severity string
--- @param emit function
--- @return table|nil loaded schema, when it is v2 and usable by the smoke layer
local function check_schema(ext, severity, emit)
  local id = 'conformance/schema/' .. ext.name
  local path = find_schema(ext.dir)

  if not path then
    emit(case(id, 'skip', 'the extension ships no `_schema.yml`', 'conformance', 'schema-absent'))
    return nil
  end

  local vocabulary, detail = schema_vocabulary(path)
  if vocabulary == 'v1' then
    emit(case(id, 'skip', string.format(
      'the schema uses the v1 vocabulary (%s); the runner validates v2 only. ' ..
      'Rename `min` to `minimum`, `max` to `maximum`, `enum-case-insensitive` to ' ..
      '`enumCaseInsensitive`, `element-attributes` to `attributes`, and replace ' ..
      '`pattern-exact` with an anchored `pattern`, then declare `$schema: %s`.',
      detail, schema.SCHEMA_VERSION), 'conformance', 'schema-v1-not-supported'))
    return nil
  end
  if vocabulary == 'unknown' then
    emit(case(id, 'skip', string.format('unrecognised `$schema` (%s)', detail),
      'conformance', 'schema-version-unknown'))
    return nil
  end
  if vocabulary == 'missing' then
    -- Advisory rather than a failure. The schema is still usable, but Quarto
    -- Wizard defaults an undeclared `$schema` to v1 while this runner reads
    -- it as v2, so the two consumers of one file can disagree until it is
    -- declared. That is worth reporting and not worth failing over.
    emit(advisory('conformance/schema-version/' .. ext.name,
      string.format('the schema declares no `$schema`; add `$schema: %s`', schema.SCHEMA_VERSION)))
  end

  local loaded, load_err = schema.load_schema(path)
  if not loaded then
    emit(case(id, 'fail', load_err, 'conformance', 'schema-unloadable'))
    return nil
  end
  emit(case(id, 'pass'))

  M.check_descriptors(ext, loaded, severity, emit)

  -- An empty configuration must validate. This is where a `default` whose
  -- type contradicts its own declaration surfaces, and it is the check that
  -- protects every extension reading its defaults back out of the schema.
  local empty_id = 'conformance/defaults/' .. ext.name
  local valid, errors = schema.validate({}, loaded.options, { unknown = 'ignore' })
  if valid then
    emit(case(empty_id, 'pass'))
  else
    emit(case(empty_id, 'fail',
      'an empty configuration is rejected by the schema: ' .. table.concat(util.sorted_messages(errors), ' | '),
      'conformance', 'defaults-invalid'))
  end

  return loaded
end

--- Walk every descriptor in a loaded schema, checking keywords, types and
--- patterns. Iteration order comes from `schema.key_order`, so findings are
--- reported in declaration order and two runs produce identical output.
--- @param ext table
--- @param loaded table
--- @param severity string strict fails on an uncompilable pattern; lenient advises
--- @param emit function
function M.check_descriptors(ext, loaded, severity, emit)
  local seen_problem = false

  local function fail(id, message, reason)
    seen_problem = true
    emit(case(id, 'fail', message, 'conformance', reason))
  end

  local function check_descriptor(path, descriptor)
    if type(descriptor) ~= 'table' then
      return
    end
    for _, keyword in ipairs(schema.key_order(descriptor)) do
      if schema.KEYWORDS[keyword] == nil then
        fail('conformance/keyword/' .. ext.name .. '/' .. path .. '/' .. keyword,
          string.format('`%s` declares the unknown keyword `%s`', path, keyword),
          'unknown-keyword')
      end
    end

    local declared = descriptor.type
    local types = type(declared) == 'table' and declared or { declared }
    for _, name in ipairs(types) do
      if name ~= nil and not V2_TYPES[name] then
        fail('conformance/type/' .. ext.name .. '/' .. path,
          string.format('`%s` declares the unknown type `%s`', path, tostring(name)),
          'unknown-type')
      end
    end

    for _, keyword in ipairs({ 'pattern', 'propertyNames' }) do
      local pattern = descriptor[keyword]
      if type(pattern) == 'string' then
        local compiled, compile_err = schema._compile_pattern(pattern)
        if not compiled then
          -- Strict is the author's own CI, where a pattern this validator
          -- cannot express means runtime validation silently degrades.
          -- Lenient is the catalogue sweep, where a legal regex the Lua
          -- compiler simply cannot express is not the author's fault.
          local pattern_id = 'conformance/pattern/' .. ext.name .. '/' .. path .. '/' .. keyword
          local message = string.format('`%s.%s` does not compile: %s', path, keyword, tostring(compile_err))
          if severity == 'strict' then
            fail(pattern_id, message, 'pattern-uncompilable')
          else
            emit(advisory(pattern_id, message))
          end
        end
      end
    end

    -- A declared example that its own descriptor rejects is documentation
    -- that has drifted from the constraint beside it.
    if type(descriptor.examples) == 'table' then
      for index, example in ipairs(descriptor.examples) do
        local valid = schema.validate({ probe = example }, { probe = descriptor }, { unknown = 'ignore' })
        if not valid then
          fail('conformance/example/' .. ext.name .. '/' .. path .. '/' .. index,
            string.format('`%s.examples[%d]` does not satisfy its own descriptor', path, index),
            'example-invalid')
        end
      end
    end

    if descriptor.const ~= nil then
      local valid = schema.validate({ probe = descriptor.const }, { probe = descriptor }, { unknown = 'ignore' })
      if not valid then
        fail('conformance/const/' .. ext.name .. '/' .. path,
          string.format('`%s.const` does not satisfy its own descriptor', path), 'const-invalid')
      end
    end

    if type(descriptor.properties) == 'table' then
      for _, key in ipairs(schema.key_order(descriptor.properties)) do
        check_descriptor(path .. '.' .. key, descriptor.properties[key])
      end
    end
    if type(descriptor.items) == 'table' then
      check_descriptor(path .. '.items', descriptor.items)
    end
  end

  local function check_map(section, map)
    if type(map) ~= 'table' then
      return
    end
    for _, key in ipairs(schema.key_order(map)) do
      check_descriptor(section .. '.' .. key, map[key])
    end
  end

  check_map('options', loaded.options)
  check_map('classes', loaded.classes)

  for _, name in ipairs(schema.key_order(loaded.formats or {})) do
    check_map('formats.' .. name, loaded.formats[name])
  end
  for _, group in ipairs(schema.key_order(loaded.attributes or {})) do
    check_map('attributes.' .. group, loaded.attributes[group])
    local lowered = tostring(group):lower()
    if group ~= '_any' and not ELEMENTS[lowered] and not tostring(group):match('^[A-Za-z_][A-Za-z0-9_-]*$') then
      fail('conformance/attribute-group/' .. ext.name .. '/' .. group,
        string.format('`attributes.%s` is neither `_any`, a Pandoc element, nor a class or ID token', group),
        'attribute-group-unrecognised')
    end
  end

  for _, name in ipairs(schema.key_order(loaded.shortcodes or {})) do
    local entry = loaded.shortcodes[name]
    if type(entry) == 'table' then
      for _, key in ipairs(schema.key_order(entry)) do
        if not SHORTCODE_KEYS[key] then
          fail('conformance/shortcode-key/' .. ext.name .. '/' .. name .. '/' .. key,
            string.format('`shortcodes.%s` declares the unexpected key `%s`', name, key),
            'shortcode-key-unexpected')
        end
      end

      for index, argument in ipairs(entry.arguments or {}) do
        if type(argument) ~= 'table' or type(argument.name) ~= 'string' then
          fail('conformance/argument/' .. ext.name .. '/' .. name .. '/' .. index,
            string.format('`shortcodes.%s.arguments[%d]` has no `name`', name, index),
            'argument-unnamed')
        else
          check_descriptor('shortcodes.' .. name .. '.arguments.' .. argument.name, argument)
        end
      end

      check_map('shortcodes.' .. name .. '.attributes', entry.attributes)

      for _, required in ipairs(entry.required or {}) do
        local attributes = entry.attributes or {}
        if attributes[required] == nil then
          fail('conformance/required/' .. ext.name .. '/' .. name .. '/' .. tostring(required),
            string.format('`shortcodes.%s.required` names `%s`, which is not declared in `attributes`',
              name, tostring(required)),
            'required-undeclared')
        end
      end
    end
  end

  if not seen_problem then
    emit(case('conformance/descriptors/' .. ext.name, 'pass'))
  end
end

--- The manifest file name an extension declares its vendored files in.
local DEPENDENCIES_FILE = '_dependencies.yml'

--- The manifest format version this runner reads.
local DEPENDENCIES_VERSION = 1

--- The keys a source declaration may carry.
---
--- The validator reports an unknown key in the top-level map only, so a key
--- inside a source or a file entry is accepted in silence. The format is
--- public and written by hand, and `runtimes:` written for `runtime:` would
--- otherwise disable the tripwire and say nothing. The report is an advisory,
--- because a later version of the format may add a key this list has not
--- heard of yet.
local SOURCE_KEYS = { 'origin', 'fetch', 'version', 'licence', 'licence-url', 'files' }

--- The keys a file entry may carry.
local FILE_KEYS = { 'sha256', 'runtime' }

--- The directory vendored files are written into, one subdirectory per source.
local VENDOR_DIR = '_vendor'

--- The names a source's licence file may carry.
---
--- Both spellings are here. This project writes British English, and the
--- upstreams it vendors from overwhelmingly ship the American one. A licence
--- under any of these names satisfies the licence check and is not an
--- undeclared file.
local LICENCE_FILES = {
  'LICENSE', 'LICENSE.md', 'LICENSE.txt',
  'LICENCE', 'LICENCE.md', 'LICENCE.txt',
  'COPYING',
}

--- Whether a vendor directory entry is a source's licence file.
---
--- The names are matched without regard to case. Upstreams ship `license` in
--- lower case as readily as `LICENSE`, and the format offers no way to say
--- which. An exact comparison also made the verdict depend on the machine: a
--- case-insensitive filesystem accepted what a case-sensitive one refused, so
--- the same repository passed on macOS and failed on the Linux runner.
---
--- The licence check and the orphan check both read this. A name that
--- satisfies the one is never an undeclared file to the other.
--- @param name string a directory entry, as the filesystem spells it
--- @return boolean
local function is_licence_file(name)
  local lowered = string.lower(name)
  for _, licence in ipairs(LICENCE_FILES) do
    if lowered == string.lower(licence) then
      return true
    end
  end
  return false
end

--- Check one extension's `_dependencies.yml`.
---
--- An extension with no manifest is skipped, not failed. The catalogued
--- extensions belong to other people, and declaring nothing is not a defect.
--- @param ext table {name, dir}
--- @param dependencies_schema table descriptors from dependencies-schema.yml
--- @param emit function(case)
--- @return table|nil parsed manifest
local function check_dependencies(ext, dependencies_schema, emit)
  local path = util.join(ext.dir, DEPENDENCIES_FILE)
  local id = 'conformance/vendored/' .. ext.name

  if not util.exists(path) then
    emit(case(id, 'skip', 'the extension declares no vendored dependency',
      'conformance', 'no-dependency-manifest'))
    return nil
  end

  local text, read_err = util.read_file(path)
  if not text then
    emit(case(id, 'fail', read_err, 'conformance', 'dependencies-unreadable'))
    return nil
  end

  local parsed = schema._parse_yaml_text(text)
  if type(parsed) ~= 'table' then
    emit(case(id, 'fail', 'the manifest is not a YAML mapping',
      'conformance', 'dependencies-unparseable'))
    return nil
  end

  -- Read the version before validating against descriptors that describe one
  -- version of the format. A manifest written to a later version is skipped,
  -- the way an unrecognised schema vocabulary is, because every copy of this
  -- framework already released would otherwise report a future format as the
  -- author's defect.
  --
  -- Only a whole number that is not 1 is a version from the future. `schema`
  -- is required, so a value that is absent, fractional or not a number at all
  -- is a malformed manifest, and it falls through to the validator below,
  -- which says so. Skipping it would take every checksum, licence and orphan
  -- check for that extension with it.
  --
  -- The version is read the way the validator reads it, through a numeric
  -- coercion, because the validator accepts a quoted scalar for an integer.
  -- Reading `schema: "2"` any other way would walk a manifest from the future
  -- as if it were version 1.
  local declared_version = tonumber(parsed.schema)
  if declared_version ~= nil
    and (declared_version ~= declared_version
      or declared_version == math.huge
      or declared_version == -math.huge) then
    -- `inf`, `-inf` and NaN are not whole numbers in any useful sense, and the
    -- vendored validator's own integer test rejects them too. Without this,
    -- `schema: 1e999` reads as a version from the future and skips every
    -- checksum, licence and orphan check silently, instead of failing the
    -- typo it is.
    declared_version = nil
  end
  local from_the_future = declared_version ~= nil
    and declared_version == math.floor(declared_version)
    and declared_version ~= DEPENDENCIES_VERSION
  if from_the_future then
    emit(case(id, 'skip', string.format(
      'the manifest declares format version %s; this runner reads version %d',
      tostring(parsed.schema), DEPENDENCIES_VERSION),
      'conformance', 'dependency-schema-version-unknown'))
    return nil
  end

  local valid, errors, warnings = schema.validate(parsed, dependencies_schema, { unknown = 'warn' })
  if not valid then
    emit(case(id, 'fail', table.concat(util.sorted_messages(errors), '; '),
      'conformance', 'dependencies-invalid'))
    return nil
  end
  emit(case(id, 'pass'))
  for index, warning in ipairs(util.sorted_messages(warnings)) do
    emit(advisory(string.format('%s/warning/%d', id, index), warning))
  end

  --- Check one source: its licence, the files it declares, and its orphans.
  ---
  --- The caller guards the shape this reads. `M.run` continues with empty
  --- descriptors when it cannot read its own, and then nothing has validated
  --- the manifest before it is walked.
  local function check_source(source_name, source)
    local dir = util.join(ext.dir, VENDOR_DIR, source_name)

    for _, key in ipairs(util.sorted_keys(source)) do
      if not util.contains(SOURCE_KEYS, key) then
        emit(advisory(string.format('%s/%s/unknown-key/%s', id, source_name, key),
          string.format('`sources.%s` declares the unrecognised key `%s`', source_name, key)))
      end
    end

    -- Third-party source shipped inside an extension carries its licence.
    --
    -- The directory is read, rather than probed once for each name, because a
    -- probe answers from the filesystem's own idea of case and accepts on
    -- macOS what it refuses on Linux. Reading the entries the directory holds
    -- gives the same verdict on either machine, and gives the orphan check
    -- below the very names this check has already accepted.
    local licence_id = string.format('%s/%s/source-licence', id, source_name)
    local licence_present = false
    for _, present in ipairs(util.list_dir(dir)) do
      if is_licence_file(present) then
        licence_present = true
      end
    end
    if licence_present then
      emit(case(licence_id, 'pass'))
    else
      emit(case(licence_id, 'fail', string.format(
        '`%s/%s/` ships no licence file for `%s`; name it one of %s',
        VENDOR_DIR, source_name, source_name, table.concat(LICENCE_FILES, ', ')),
        'conformance', 'vendored-licence-missing'))
    end

    --- Check one declared file: its keys, its presence and its checksum.
    ---
    --- The entry's shape is guarded here, not by the caller. Nothing has
    --- validated the manifest when the descriptors did not load, and reading
    --- `entry.sha256` off a number raises and takes the whole run with it.
    local function check_file(file_name, entry)
      local file_id = string.format('%s/%s/%s', id, source_name, file_name)
      local file_path = util.join(dir, file_name)

      if type(entry) ~= 'table' then
        emit(case(file_id, 'fail', string.format(
          '`sources.%s.files.%s` is not a file entry carrying a checksum',
          source_name, file_name), 'conformance', 'dependencies-invalid'))
        return
      end

      for _, key in ipairs(util.sorted_keys(entry)) do
        if not util.contains(FILE_KEYS, key) then
          emit(advisory(string.format('%s/unknown-key/%s', file_id, key), string.format(
            '`sources.%s.files.%s` declares the unrecognised key `%s`',
            source_name, file_name, key)))
        end
      end

      if not util.exists(file_path) then
        emit(case(file_id, 'fail', string.format(
          'the manifest declares `%s`, which `%s/%s/` does not hold',
          file_name, VENDOR_DIR, source_name), 'conformance', 'vendored-file-missing'))
      else
        local digest, digest_err = util.sha256(file_path)
        if digest_err == 'no-tool' then
          -- Neither hashing tool is available. A checksum that cannot be
          -- computed is not a checksum that does not match, and it is not a
          -- checksum that matches either. Graded as a skip rather than an
          -- advisory, which passes: this case guards the manifest contract the
          -- whole fleet run depends on, so it must not report success on the
          -- strength of never having looked.
          emit(case(file_id, 'skip', string.format(
            'cannot verify `%s`: no SHA-256 tool is available',
            file_name), 'conformance', 'vendored-checksum-unverifiable'))
        elseif not digest then
          -- The machine has a tool and it produced nothing, so the entry
          -- names something that is not a readable file.
          emit(case(file_id, 'fail', string.format(
            'the manifest declares `%s`, which `%s/%s/` holds as something no SHA-256 tool can read',
            file_name, VENDOR_DIR, source_name), 'conformance', 'vendored-checksum-unreadable'))
        elseif digest ~= tostring(entry.sha256):lower() then
          emit(case(file_id, 'fail', string.format(
            '`%s` does not match the checksum the manifest records; it reads %s',
            file_name, digest), 'conformance', 'vendored-checksum-mismatch'))
        else
          emit(case(file_id, 'pass'))
        end
      end

      if entry.runtime == 'pandoc' then
        -- A tripwire, not a check. q2 builds Lua for wasm, where the libraries
        -- Pandoc provides are unavailable, and q2 has not shipped.
        emit(advisory(file_id .. '/runtime', string.format(
          '`%s` declares `runtime: pandoc`, so it cannot load where only a plain Lua is available',
          file_name)))
      end
    end

    for _, file_name in ipairs(util.sorted_keys(source.files)) do
      check_file(file_name, source.files[file_name])
    end

    -- The check aimed at the copying habit: a file that reached the vendor
    -- directory without passing through the manifest.
    if util.is_dir(dir) then
      for _, present in ipairs(util.list_dir(dir)) do
        if not is_licence_file(present) and source.files[present] == nil then
          emit(case(string.format('%s/%s/%s', id, source_name, present), 'fail',
            string.format('`%s/%s/%s` is not declared by the manifest',
              VENDOR_DIR, source_name, present),
            'conformance', 'vendored-undeclared'))
        end
      end
    end
  end

  -- An id of its own. The manifest's own id has already been written above,
  -- and one id on two cases loses one of them for every reader that keys on
  -- the id.
  if type(parsed.sources) ~= 'table' then
    emit(case(id .. '/sources', 'fail', '`sources` is not a map of source declarations',
      'conformance', 'dependencies-invalid'))
    return nil
  end

  for _, source_name in ipairs(util.sorted_keys(parsed.sources)) do
    local source = parsed.sources[source_name]
    if type(source) ~= 'table' or type(source.files) ~= 'table' then
      emit(case(string.format('%s/%s/declaration', id, source_name), 'fail',
        string.format('`sources.%s` is not a source declaration carrying a `files` map', source_name),
        'conformance', 'dependencies-invalid'))
    else
      check_source(source_name, source)
    end
  end

  -- The loop above only ever lists the directories the manifest names, so a
  -- whole source copied in by hand is invisible to it. Listing the vendor
  -- directory itself is what catches that, and a loose file at its root with
  -- it: a source is a directory the manifest declares, and nothing else
  -- belongs here.
  local vendor_root = util.join(ext.dir, VENDOR_DIR)
  if util.is_dir(vendor_root) then
    for _, present in ipairs(util.list_dir(vendor_root)) do
      local root_id = string.format('%s/%s', id, present)
      if parsed.sources[present] == nil then
        emit(case(root_id, 'fail',
          string.format('`%s/%s` is not a source the manifest declares', VENDOR_DIR, present),
          'conformance', 'vendored-undeclared'))
      elseif not util.is_dir(util.join(vendor_root, present)) then
        -- A name the manifest does declare, written as a file. The verdict is
        -- the same failure, and the sentence above is not: telling the author
        -- the manifest does not declare it contradicts the file they wrote.
        emit(case(root_id, 'fail', string.format(
          'the manifest declares `%s` as a source, so `%s/%s` must be a directory, and it is a file',
          present, VENDOR_DIR, present),
          'conformance', 'vendored-source-not-a-directory'))
      end
    end
  end

  return parsed
end

--- Load each extension's manifest and schema without reporting on them.
---
--- The smoke layer needs both, and asking for it without the conformance
--- layer used to leave every extension without a schema and skip silently.
--- @param root string
--- @return table[] extensions
function M.load(root)
  local extensions = M.discover(root)
  for _, ext in ipairs(extensions) do
    local text = util.read_file(util.join(ext.dir, '_extension.yml'))
    if text then
      local ok, parsed = pcall(schema._parse_yaml_text, text)
      ext.manifest = (ok and type(parsed) == 'table') and parsed or nil
    end
    local path = find_schema(ext.dir)
    if path and schema_vocabulary(path) == 'v2' then
      ext.schema = schema.load_schema(path)
    end
  end
  return extensions
end

--- Run the conformance layer over a repository.
--- @param options table {root, severity, module_dir}
--- @param emit function(case)
--- @return table[] extensions, each with its loaded schema attached
function M.run(options, emit)
  local manifest_path = util.join(options.extension_dir, 'manifest-schema.yml')
  local manifest_schema = {}
  local loaded_manifest, manifest_err = schema.load_schema(manifest_path)
  if loaded_manifest then
    manifest_schema = loaded_manifest.options
  else
    emit(case('conformance/harness/manifest-schema', 'fail',
      'the framework cannot read its own manifest descriptors: ' .. tostring(manifest_err),
      'discover', 'harness-error'))
  end

  local dependencies_schema = {}
  local loaded_dependencies, dependencies_err =
    schema.load_schema(util.join(options.extension_dir, 'dependencies-schema.yml'))
  if loaded_dependencies then
    dependencies_schema = loaded_dependencies.options
  else
    emit(case('conformance/harness/dependencies-schema', 'fail',
      'the framework cannot read its own dependency descriptors: ' .. tostring(dependencies_err),
      'discover', 'harness-error'))
  end

  local extensions = M.discover(options.root)
  if #extensions == 0 then
    emit(case('conformance/discover', 'skip',
      string.format('no extension found under `%s/_extensions/`', options.root),
      'discover', 'no-extension'))
    return {}
  end

  for _, ext in ipairs(extensions) do
    ext.manifest = check_manifest(ext, manifest_schema, emit)
    ext.schema = check_schema(ext, options.severity, emit)
    ext.dependencies = check_dependencies(ext, dependencies_schema, emit)
  end

  return extensions
end

--- Exposed for the framework's own tests.
---
--- The licence rule is a rule about names, and a fixture can only ask the
--- filesystem it runs on. A case-insensitive one answers for `LICENSE` when
--- the directory holds `license`, and hides half the rule. This reads the name
--- alone, so the tests assert the rule on either machine.
M._is_licence_file = is_licence_file

return M
