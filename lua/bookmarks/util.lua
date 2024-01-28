local uv = vim.loop
local M = {}

function M.path_exists(path)
   if path then
      return vim.loop.fs_stat(path) and true or false
   end
   return false
end

local jit_os

if jit then
   jit_os = jit.os:lower()
end

local is_unix = false
if jit_os then
   is_unix = jit_os == "linux" or jit_os == "osx" or jit_os == "bsd"
else
   local binfmt = package.cpath:match "%p[\\|/]?%p(%a+)"
   is_unix = binfmt ~= "dll"
end

function M.dirname(file)
   return file:match(string.format("^(.+)%s[^%s]+", M.path_sep, M.path_sep))
end

function M.file_lines(file)
   local text = {}
   for line in io.lines(file) do
      text[#text + 1] = line
   end
   return text
end

M.path_sep = package.config:sub(1, 1)

function M.tmpname()
   if is_unix then
      return os.tmpname()
   end
   return vim.fn.tempname()
end

function M.copy_array(x)
   local r = {}
   for i, e in ipairs(x) do
      r[i] = e
   end
   return r
end

function M.strip_cr(xs0)
   for i = 1, #xs0 do
      if xs0[i]:sub(-1) ~= "\r" then
         return xs0
      end
   end

   local xs = vim.deepcopy(xs0)
   for i = 1, #xs do
      xs[i] = xs[i]:sub(1, -2)
   end
   return xs
end

function M.emptytable()
   return setmetatable({}, {
      __index = function(t, k)
         t[k] = {}
         return t[k]
      end,
   })
end

function M.clear_prompt()
   vim.api.nvim_command "normal! :"
end

function M.prompt_yes_no(prompt, callback, prompt_no_cr)
   prompt = string.format("%s [y/N] ", prompt)
   if prompt_no_cr then -- use getchar so no <cr> is required
      print(prompt)
      local ans = vim.fn.nr2char(vim.fn.getchar())
      local is_confirmed = ans:lower():match "^y"
      M.clear_prompt()
      callback(is_confirmed)
   else -- use vim.ui.input
      vim.ui.input({ prompt = prompt }, function(answer)
         callback(vim.tbl_contains({ "y", "yes" }, answer and answer:lower()))
      end)
   end
end

M.write_file = function(path, content)
   local file = io.open(path, "w")
   if file then
      file:write(content)
      file:close()
   else
      error("Could not open file for writing: " .. path)
   end
end

M.read_file = function(path, callback)
   local file = io.open(path, "r")
   if file then
      local content = file:read("*all")
      file:close()
      callback(content)
   else
      error("Could not open file for reading: " .. path)
   end
end

function M.warn(...)
   vim.notify(string.format(...), vim.log.levels.WARN)
end

function M.error(...)
   vim.notify(string.format(...), vim.log.levels.ERROR)
end

function M.lazy(fn)
   local cached
   return function(...)
      if cached == nil then
         cached = fn(...)
         assert(cached ~= nil, "lazy: fn returned nil")
      end
      return cached
   end
end

function M.setqflist(content, opts)
   if type(opts) == "string" then
      opts = { cwd = opts }
      if opts.cwd:sub(1, 4) == "cwd=" then
         opts.cwd = opts.cwd:sub(5)
      end
   end
   opts = opts or {}
   opts.open = (opts.open ~= nil) and opts.open or true
   vim.fn.setqflist({}, " ", { title = "Bookmarks", id = "$", items = content })
   if opts.open then
      vim.cmd [[copen]]
   end
   -- local win = vim.fn.getqflist { winid = true }
   -- if win.winid ~= 0 then
   -- end
end

return M
