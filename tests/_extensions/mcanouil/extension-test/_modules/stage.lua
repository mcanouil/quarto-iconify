--- Extension Test - Staging the extension under test.
---
--- Quarto builds its extension registry while reading `_quarto.yml`, before
--- any `pre-render` script runs, so an extension copied in from inside a
--- render is not seen by that render. Staging therefore happens here, before
--- Quarto is invoked at all.
---
--- Staging is a copy, not a symlink. Measured against Quarto 99.9.9: a
--- symlinked extension inside a real `_extensions/` directory is silently not
--- resolved, and the render still exits 0 with only a warning. Symlinking the
--- whole `_extensions/` directory does work, but that shape is unavailable
--- here because the same directory must also hold the framework.

local util = require('util')

local M = {}

--- The owner directory generated copies are staged under.
---
--- `local` matches the convention the documentation sites already use. It
--- keeps a staged copy from colliding with an extension named after its
--- owner, and it says on the face of the path that the copy is generated.
M.STAGE_OWNER = 'local'

--- The project file names Quarto accepts for a directory.
M.PROJECT_FILES = { '_quarto.yml', '_quarto.yaml' }

--- Why staging cannot be resolved, when the tests directory is not a project.
---
--- Quarto resolves an extension from the project the document belongs to.
--- Without a project file the tests directory is not one, the staged copy is
--- never read, and every generated document reports a shortcode that is not
--- found. That reads as a broken extension when the harness is simply not set
--- up, so it is reported for what it is.
--- @param tests string tests directory
--- @return string|nil message
function M.missing_project(tests)
  for _, name in ipairs(M.PROJECT_FILES) do
    if util.exists(util.join(tests, name)) then
      return nil
    end
  end
  return string.format(
    'the tests directory has no `%s`, so the staged extension is not resolved; '
    .. 'add one that declares `project:` with `type: extension-test`',
    M.PROJECT_FILES[1])
end

--- Stage every extension a repository ships into the tests project.
---
--- The staging directory is removed first. Copying onto an existing directory
--- nests the new copy inside the old one, which is the failure the
--- documentation sync scripts document.
--- @param root string repository root
--- @param tests string tests directory
--- @return table staged {names, dir}
--- @return string|nil error
function M.stage(root, tests)
  local source = util.join(root, '_extensions')
  local target = util.join(tests, '_extensions', M.STAGE_OWNER)

  util.remove_tree(target)

  if not util.is_dir(source) then
    return { names = {}, dir = target }, nil
  end

  local names = {}
  for _, name in ipairs(util.list_dir(source)) do
    local from = util.join(source, name)
    if util.is_dir(from) and util.exists(util.join(from, '_extension.yml')) then
      local ok, err = util.copy_tree(from, util.join(target, name))
      if not ok then
        return { names = names, dir = target }, string.format('cannot stage `%s`: %s', name, tostring(err))
      end
      names[#names + 1] = name
    end
  end

  return { names = names, dir = target }, nil
end

--- Remove the staging directory.
---
--- Only the generated owner directory is touched, never the framework's own
--- `tests/_extensions/<owner>/` beside it.
--- @param tests string tests directory
function M.unstage(tests)
  util.remove_tree(util.join(tests, '_extensions', M.STAGE_OWNER))
end

return M
