local config = require("bookmarks.config").config
local uv = vim.loop
local Signs = require "bookmarks.signs"
local utils = require "bookmarks.util"
local api = vim.api
local current_buf = api.nvim_get_current_buf
local M = {}
local signs
M.setup = function()
   signs = Signs.new(config.signs)
end

M.detach = function(bufnr, keep_signs)
   if not keep_signs then
      signs:remove(bufnr)
   end
end

local function updateBookmarks(bufnr, lnum, mark, ann)
   local filepath = uv.fs_realpath(api.nvim_buf_get_name(bufnr))
   if filepath == nil then
      return
   end
   local data = config.cache["data"]
   local marks = data[filepath]
   local isIns = false
   if lnum == -1 then
      marks = nil
      isIns = true
      -- check buffer auto_save to file
   end
   for k, _ in pairs(marks or {}) do
      if k == tostring(lnum) then
         isIns = true
         if mark == "" then
            marks[k] = nil
         end
         break
      end
   end
   if isIns == false or ann then
      marks = marks or {}
      marks[tostring(lnum)] = ann and { m = mark, a = ann } or { m = mark }
      -- check buffer auto_save to file
      -- M.saveBookmarks()
   end
   data[filepath] = marks
end

M.toggle_signs = function(value)
   if value ~= nil then
      config.signcolumn = value
   else
      config.signcolumn = not config.signcolumn
   end
   M.refresh()
   return config.signcolumn
end

M.bookmark_toggle = function()
   local lnum = api.nvim_win_get_cursor(0)[1]
   local bufnr = current_buf()
   local signlines = { {
      type = "add",
      lnum = lnum,
   } }
   local isExt = signs:add(bufnr, signlines)
   if isExt then
      signs:remove(bufnr, lnum)
      updateBookmarks(bufnr, lnum, "")
   else
      local line = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
      updateBookmarks(bufnr, lnum, line)
   end
end

M.bookmark_clean = function()
   local bufnr = current_buf()
   signs:remove(bufnr)
   updateBookmarks(bufnr, -1, "")
end

M.bookmark_line = function(lnum, bufnr)
   bufnr = bufnr or current_buf()
   local file = uv.fs_realpath(api.nvim_buf_get_name(bufnr))
   local marks = config.cache["data"][file] or {}
   return lnum and marks[tostring(lnum)] or marks
end

M.bookmark_ann = function()
   local lnum = api.nvim_win_get_cursor(0)[1]
   local bufnr = current_buf()
   local signlines = { {
      type = "ann",
      lnum = lnum,
   } }
   local mark = M.bookmark_line(lnum, bufnr)
   vim.ui.input({ prompt = "Edit:", default = mark.a }, function(answer)
      if answer == nil then return end
      local line = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
      signs:remove(bufnr, lnum)
      local text = config.keywords[string.sub(answer or "", 1, 2)]
      if text then
         signlines[1]["text"] = text
      end
      signs:add(bufnr, signlines)
      updateBookmarks(bufnr, lnum, line, answer)
   end)
end

local jump_line = function(prev)
   local lnum = api.nvim_win_get_cursor(0)[1]
   local marks = M.bookmark_line()
   local small, big = {}, {}
   for k, _ in pairs(marks) do
      k = tonumber(k)
      if k < lnum then
         table.insert(small, k)
      elseif k > lnum then
         table.insert(big, k)
      end
   end
   if prev then
      local tmp = #small > 0 and small or big
      table.sort(tmp, function(a, b)
         return a > b
      end)
      lnum = tmp[1]
   else
      local tmp = #big > 0 and big or small
      table.sort(tmp)
      lnum = tmp[1]
   end
   if lnum then
      api.nvim_win_set_cursor(0, { lnum, 0 })
      local mark = marks[tostring(lnum)]
      if mark.a then
         api.nvim_echo({ { "ann: " .. mark.a, "WarningMsg" } }, false, {})
      else
      end
   end
end

M.bookmark_prev = function()
   jump_line(true)
end

M.bookmark_next = function()
   jump_line(false)
end

M.bookmark_list = function()
   local allmarks = config.cache.data
   local marklist = {}
   for k, ma in pairs(allmarks) do
      if utils.path_exists(k) == false then
         allmarks[k] = nil
      end
      for l, v in pairs(ma) do
         table.insert(marklist, { filename = k, lnum = l, text = v.m .. "|" .. (v.a or "") })
      end
   end
   utils.setqflist(marklist)
end

M.refresh = function(bufnr)
   bufnr = bufnr or current_buf()
   local file = uv.fs_realpath(api.nvim_buf_get_name(bufnr))
   if file == nil then
      return
   end
   local marks = config.cache.data[file]
   local signlines = {}
   if marks then
      for k, v in pairs(marks) do
         local ma = {
            type = v.a and "ann" or "add",
            lnum = tonumber(k),
         }
         local pref = string.sub(v.a or "", 1, 2)
         local text = config.keywords[pref]
         if text then
            ma["text"] = text
         end
         signs:remove(bufnr, ma.lnum)
         table.insert(signlines, ma)
      end
      signs:add(bufnr, signlines)
   end
end

local function log_to_file(message)
    -- local home_folder = vim.fcibn.expand("~")
    local home_folder = vim.fn.getenv("HOME") or vim.fn.getenv("USERPROFILE")
    local log_file_path = home_folder .. "/Downloads/nvim-logfile.log" -- Change this to your desired log path
    local current_folder = vim.fn.getcwd()
    -- Get the caller file and line number (2 levels up in the stack)
    local info = debug.getinfo(2, "Sl")
    local caller_info = string.format("%s:%d", info.short_src, info.currentline)
    -- Construct the full log message
    local full_message = string.format("[%s] [%s] %s - %s", os.date("%Y-%m-%d %H:%M:%S"), current_folder, caller_info, message)
    local file = io.open(log_file_path, "a")
    if file then
        file:write(full_message .. "\n")
        file:close()
    end
end
-- Call the function to log a message
log_to_file("nvim:bookmarks:actions.lua initialized")

function M.loadBookmarks()
   log_to_file("nvim:bookmarks:actions.lua loadBookmarks called")
   if utils.path_exists(config.save_file) then
      utils.read_file(config.save_file, function(data)
         local newData = vim.json.decode(data)
         if config.cache then
            config.cache = vim.tbl_deep_extend("force", config.cache, newData)
         else
            config.cache = newData
         end
         config.marks = data
      end)
   end
end

function pretty_print_json(input, indent)
   indent = indent or 0
   local indent_str1 = string.rep(" ", indent)
   local indent_str2 = string.rep(" ", indent + 2)
   local output = "{\n"
   for k, v in pairs(input) do
       output = output .. indent_str2 .. '"' .. k .. '": '
       if type(v) == "table" then
           output = output .. pretty_print_json(v, indent + 2)
       else
           output = output .. '"' .. tostring(v) .. '"'
       end
       output = output .. ",\n"
   end
   output = output .. indent_str1 .. "}"
   return output
end

function M.saveBookmarks()
  -- load it first to make sure we don't overwrite changes
  -- TBD: figure out how to delete a bookmark
  -- M.loadBookmarks()
  log_to_file("nvim:bookmarks:actions.lua saveBookmarks called")
  local status, data = pcall(pretty_print_json, config.cache)
  if not status then
     log_to_file("nvim:bookmarks:actions.lua saveBookmarks error: " .. data)
     log_to_file("nvim:bookmarks:actions.lua saveBookmarks status: " .. tostring(status))
     return
  end
  log_to_file("nvim:bookmarks:actions.lua saveBookmarks data: " .. data)
  if config.marks ~= data then
     utils.write_file(config.save_file, data)
     utils.write_file(config.save_file .. ".v2", data)
  end
end

return M
