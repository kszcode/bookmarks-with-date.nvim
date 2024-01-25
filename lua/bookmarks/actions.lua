local config = require("bookmarks.config").config
local uv = vim.loop
local Signs = require "bookmarks.signs"
local utils = require "bookmarks.util"
local api = vim.api
local current_buf = api.nvim_get_current_buf
local M = {}
local signs
local DELETED_MARK = "--deleted--"

M.setup = function()
    signs = Signs.new(config.signs)
end

M.detach = function(bufnr, keep_signs)
    if not keep_signs then
        signs:remove(bufnr)
    end
end

-- This function checks if the mark for a given line in a given buffer is equal to --deleted--.
-- @param bufnr: The buffer number.
-- @param lnum: The line number.
local function isLineDeleted(bufnr, lnum)
    -- Get the real path of the file associated with the buffer.
    local filepath = uv.fs_realpath(api.nvim_buf_get_name(bufnr))

    -- If the filepath is nil, return false.
    if filepath == nil then
        return false
    end

    -- Get the data from the cache.
    local data = config.cache["data"]

    -- Get the marks for the file.
    local marks = data[filepath]

    -- If there are no marks for the file, return false.
    if marks == nil then
        return false
    end

    -- Get the mark for the line.
    local mark = marks[string.format("%05d", lnum)]

    -- If there is no mark for the line, return false.
    if mark == nil then
        return false
    end

    -- If the mark for the line is equal to --deleted--, return true.
    if mark.mark == DELETED_MARK then
        return true
    end

    -- Otherwise, return false.
    return false
end

-- This function updates the bookmarks for a given buffer.
-- @param bufnr: The buffer number.
-- @param lnum: The line number.
-- @param mark: The mark to be added.
-- @param ann: The annotation to be added.
local function updateBookmarks(bufnr, lnum, mark, ann)
    -- Get the real path of the file associated with the buffer.
    local filepath = uv.fs_realpath(api.nvim_buf_get_name(bufnr))

    -- If the filepath is nil, exit the function.
    if filepath == nil then
        return
    end

    -- Get the data from the cache.
    local data = config.cache["data"]

    -- Get the marks for the file.
    local marks = data[filepath]

    -- -- Iterate over the marks.
    -- for k, _ in pairs(marks or {}) do
    --     -- If the mark matches the line number, set the flag to true.
    --     if k == string.format("%05d", lnum) then
    --         -- If the mark is empty, remove it.
    --         if mark == "" then
    --             marks[k] = nil
    --         end
    --         break
    --     end
    -- end

    -- If the flag is false or an annotation is provided, create a new mark.
    -- if isIns == false or ann then
    marks = marks or {}
    local bookmark = {
        mark = mark,
        datetime = os.date("%Y-%m-%d %H:%M:%S")     -- Insert datetime
    }
    if ann then
        bookmark.annotation = ann
    end
    marks[string.format("%05d", lnum)] = bookmark
    -- end

    -- Update the marks for the file in the data.
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
    local isDeleted = isLineDeleted(bufnr, lnum)
    if isExt and not isDeleted then
        signs:remove(bufnr, lnum)
        updateBookmarks(bufnr, lnum, DELETED_MARK)
    else
        local line = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
        updateBookmarks(bufnr, lnum, line)
    end
    M.saveBookmarks()
    M.loadBookmarks()
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
    return lnum and marks[string.format("%05d", lnum)] or marks
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
        k = tonumber(k, 10)
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

    -- Remove invalid file paths from allmarks
    for k, _ in pairs(allmarks) do
        if not utils.path_exists(k) then
            allmarks[k] = nil
        end
    end

    -- Create marklist with filename, line number, and text
    for k, ma in pairs(allmarks) do
        for l, v in pairs(ma) do
            local m = v.mark or v.m or ""
            -- remove the surrounding white space
            m = string.gsub(m, "^%s*(.-)%s*$", "%1")
            local a = v.annotation or v.a or ""
            local datetime = v.datetime or ""
            -- local text = datetime .. "->" .. a .. " -> " .. m
            local text = datetime
            if a ~= "" then
                text = text .. " -a> " .. a
            end
            text = text .. " -m> " .. m
            table.insert(marklist, { filename = k, lnum = tonumber(l, 10), text = text })
        end
    end

    -- sort the marklist by text in desc order
    table.sort(marklist, function(a, b)
        return a.text > b.text
    end)

    -- Set the quickfix list with marklist
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
                lnum = tonumber(k, 10),
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
    local full_message = string.format("[%s] [%s] %s - %s", os.date("%Y-%m-%d %H:%M:%S"), current_folder, caller_info,
        message)
    local file = io.open(log_file_path, "a")
    if file then
        file:write(full_message .. "\n")
        file:close()
    end
end
-- Call the function to log a message
-- log_to_file("nvim:bookmarks:actions.lua initialized")

function M.deep_extend_keep(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key] or false) == "table" then
                M.deep_extend_keep(target[key] or {}, source[key] or {})
            else
                target[key] = value
            end
        else
            if target[key] == nil then
                target[k] = v
            end
        end
    end
    return target
end

function M.loadBookmarks()
    -- vim.notify("M.loadBookmarks called INFO notify", vim.log.levels.INFO)
    if utils.path_exists(config.save_file) then
        utils.read_file(config.save_file, function(data)
            local newData = vim.json.decode(data)
            if config.cache then
                config.cache = M.deep_extend_keep(config.cache, newData)
            else
                config.cache = newData
            end
            config.marks = data
        end)
    end
end

local function escape_string(str)
    local escapes = {
        ['\\'] = '\\\\',
        ['"'] = '\\"',
        ['\n'] = '\\n',
        ['\r'] = '\\r',
        ['\t'] = '\\t'
    }
    return str:gsub('["\\\n\r\t]', escapes)
end

local function pretty_print_json(input, indent)
    indent = indent or 0
    local indent_str1 = string.rep(" ", indent)
    local indent_str2 = string.rep(" ", indent + 2)
    local output = {}
    local sorted_keys = {}
    for k, _ in pairs(input) do
        table.insert(sorted_keys, k)
    end
    table.sort(sorted_keys)
    for _, k in ipairs(sorted_keys) do
        local v = input[k]
        local kv_pair = indent_str2 .. '"' .. escape_string(k) .. '": '
        if type(v) == "table" then
            kv_pair = kv_pair .. pretty_print_json(v, indent + 2)
        else
            kv_pair = kv_pair .. '"' .. escape_string(tostring(v)) .. '"'
        end
        table.insert(output, kv_pair)
    end
    return indent_str1 .. "{\n" .. table.concat(output, ",\n") .. "\n" .. indent_str1 .. "}"
end

function M.saveBookmarks()
    -- load it first to make sure we don't overwrite changes
    M.loadBookmarks()
    vim.notify("M.saveBookmarks called INFO notify", vim.log.levels.INFO)
    local data = config.cache

    -- Iterate over each bookmark in the data
    for i, bookmark in ipairs(data) do
        -- If the bookmark is marked as deleted and it was not deleted today
        if bookmark.mark == DELETED_MARK and bookmark.deleted_date ~= os.date("%Y-%m-%d") then
            -- Remove the bookmark from the data
            table.remove(data, i)
        end
    end

    local newData = pretty_print_json(data)

    if config.marks ~= newData then
        utils.write_file(config.save_file, newData)
    end
end

return M
