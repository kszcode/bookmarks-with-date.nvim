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
        datetime = os.date("%Y-%m-%d %H:%M:%S") -- Insert datetime
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

-- This function is used to bookmark a specific line in a buffer.
-- If no buffer number is provided, it defaults to the current buffer.
-- It returns the bookmark for the specified line, or all bookmarks for the buffer if no line number is provided.
M.bookmark_line = function(lnum, bufnr)
    -- If no buffer number is provided, use the current buffer.
    bufnr = bufnr or current_buf()

    -- Get the real path of the file associated with the buffer.
    local file = uv.fs_realpath(api.nvim_buf_get_name(bufnr))

    -- Get the bookmarks for the file from the cache, or use an empty table if there are no bookmarks.
    local marks = config.cache["data"][file] or {}

    -- If a line number is provided, return the bookmark for that line.
    -- The line number is formatted as a five-digit string (padded with zeros on the left if necessary).
    -- If no line number is provided, return all bookmarks for the file.
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
    -- make sure if lnum is outside the buffer then just load the last line
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

local function expandPath(path)
    -- Check if the path starts with a tilde
    if path:sub(1, 1) == '~' then
        -- Get the HOME environment variable
        local home = os.getenv("HOME")
        if home then
            -- Replace the tilde with the home directory path
            path = home .. path:sub(2)
        end
    end
    return path
end

-- This function is used to create a list of all bookmarks.
M.bookmark_list = function()
    -- Get all bookmarks from the cache.
    local allmarks = config.cache.data
    local marklist = {}

    -- Remove invalid file paths from allmarks
    for k, v in pairs(allmarks) do
        -- but first make sure that the path is expanded
        local fullPathKey = expandPath(k)
        if fullPathKey ~= k then      -- If the path was expanded
            allmarks[fullPathKey] = v -- Update with the full path
            allmarks[k] = nil         -- Remove the old entry
        end
        -- If the file path does not exist, remove it from allmarks.
        if not utils.path_exists(fullPathKey) then
            allmarks[k] = nil
        end
    end

    print("bookmark_list: " .. vim.inspect(allmarks))
    -- Create marklist with filename, line number, and text
    for k, ma in pairs(allmarks) do
        -- For each bookmark in the file, create an entry in marklist.
        for l, v in pairs(ma) do
            -- Get the mark text, or use an empty string if there is no mark.
            local m = v.mark or v.m or ""
            -- Remove the surrounding white space from the mark text.
            m = string.gsub(m, "^%s*(.-)%s*$", "%1")
            -- Get the annotation text, or use an empty string if there is no annotation.
            local a = v.annotation or v.a or ""
            -- Get the datetime text, or use an empty string if there is no datetime.
            local datetime = v.datetime or ""
            -- Create the text for the bookmark entry.
            local text = datetime
            if a ~= "" then
                text = text .. " -a> " .. a
            end
            text = text .. " -m> " .. m
            lineNumber = tonumber(l, 10)
            -- Add the bookmark entry to marklist.
            print("bookmark_list: " .. k .. ":" .. lineNumber .. ":" .. text)
            table.insert(marklist, { filename = k, lnum = lineNumber, text = text })
        end
    end

    -- Sort the marklist by text in descending order.
    table.sort(marklist, function(a, b)
        return a.text > b.text
    end)

    -- Set the quickfix list with marklist.
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

-- local function log_to_file(message)
--     -- local home_folder = vim.fcibn.expand("~")
--     local home_folder = vim.fn.getenv("HOME") or vim.fn.getenv("USERPROFILE")
--     local log_file_path = home_folder .. "/Downloads/nvim-logfile.log" -- Change this to your desired log path
--     local current_folder = vim.fn.getcwd()
--     -- Get the caller file and line number (2 levels up in the stack)
--     local info = debug.getinfo(2, "Sl")
--     local caller_info = string.format("%s:%d", info.short_src, info.currentline)
--     -- Construct the full log message
--     local full_message = string.format("[%s] [%s] %s - %s", os.date("%Y-%m-%d %H:%M:%S"), current_folder, caller_info,
--         message)
--     local file = io.open(log_file_path, "a")
--     if file then
--         file:write(full_message .. "\n")
--         file:close()
--     end
-- end

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
    -- vim.notify("BookmarkNvim.loadBookmarks called INFO notify", vim.log.levels.INFO)
    if utils.path_exists(config.save_file) then
        utils.read_file(config.save_file, function(data)
            local newData = vim.json.decode(data)
            if config.cache then
                -- call deep_extend_keep to keep the existing data in the buffer (so deleted marks are not lost)
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

local function pretty_print_json_custom_file_list(input, indent)
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
            kv_pair = kv_pair .. pretty_print_json_custom_file_list(v, indent + 2)
        else
            kv_pair = kv_pair .. '"' .. escape_string(tostring(v)) .. '"'
        end
        table.insert(output, kv_pair)
    end
    return indent_str1 .. "{\n" .. table.concat(output, ",\n") .. "\n" .. indent_str1 .. "}"
end

function M.saveBookmarks()
    if not config.cache or not config.cache.data then
        vim.notify("BookmarkNvim.saveBookmarks Error: config.cache is not initialized", vim.log.levels.INFO)
        return
    end

    -- load it first to make sure we don't overwrite changes
    M.loadBookmarks()
    -- vim.notify("BookmarkNvim.saveBookmarks called INFO notify", vim.log.levels.INFO)

    local fileList = config.cache

    -- vim.notify("Debug fileList:" .. pretty_print_json_custom_file_list(fileList), vim.log.levels.INFO)

    -- Iterate over each file in the fileList
    for file, bookmarks in pairs(fileList.data) do
        -- vim.notify(string.format("BookmarkNvim.saveBookmarks file: %s", file), vim.log.levels.INFO)
        -- vim.notify(string.format("BookmarkNvim.saveBookmarks bookmarks: %s", vim.inspect(bookmarks)), vim.log.levels.INFO)
        -- Iterate over each bookmark in reverse order (to avoid index shifting issues)
        -- vim.notify(string.format("M.saveBookmarks found i bookmarks: %s", vim.inspect(i)), vim.log.levels.INFO)
        for line, bookmark in pairs(bookmarks) do
            -- vim.notify(string.format("BookmarkNvim.saveBookmarks bookmark: %s", vim.inspect(bookmark)), vim.log.levels.INFO)
            if bookmark and bookmark.mark == "--deleted--" then
                -- Extract date part from datetime
                local date_from_datetime = string.sub(bookmark.datetime, 1, 10)
                -- Get current date
                local current_date = os.date("%Y-%m-%d")
                if date_from_datetime ~= current_date then
                    -- Remove the bookmark from the fileList, and make sure that is not saved again
                    bookmarks[line] = nil
                    vim.notify(string.format("BookmarkNvim.saveBookmarks removed bookmark at %s in file %s", line, file),
                        vim.log.levels.INFO)
                end
            end
        end
    end

    local newData = pretty_print_json_custom_file_list(fileList)

    if config.marks ~= newData then
        utils.write_file(config.save_file, newData)
    end


    M.convertAndSaveBookmarksRecentFirst()
end

local function parse_datetime_to_table(datetime_str)
    local year, month, day, hour, min, sec = datetime_str:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    return {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
    }
end

-- This function should convert an absolute datetime string to a relative format (e.g., "3h 2min ago")
-- You'll need to calculate the difference between the current time and the datetime, then format it.
-- For simplicity, let's just return a mock string, but you should replace this with actual logic.
local function datetime_to_relative(datetime_str)
    local datetime_table = parse_datetime_to_table(datetime_str)
    local datetime_sec = os.time(datetime_table)
    local current_sec = os.time()
    local diff_sec = os.difftime(current_sec, datetime_sec)

    if diff_sec < 60 then
        return "just now"
    elseif diff_sec < 3600 then -- Less than an hour
        local minutes = math.floor(diff_sec / 60)
        return minutes .. "min ago"
    elseif diff_sec < 86400 then -- Less than a day
        local hours = math.floor(diff_sec / 3600)
        local minutes = math.floor((diff_sec % 3600) / 60)
        return string.format("%dh %dmin ago", hours, minutes)
    else
        local days = math.floor(diff_sec / 86400)
        local hours = math.floor((diff_sec % 86400) / 3600)
        return string.format("%dd %dh ago", days, hours)
    end
end


local function pretty_print_json_custom_recent_date_files_list(input)
    local parts = {}
    for k, details in pairs(input) do
        -- Serialize each bookmark entry
        local entry = string.format('    "%s -- %s": {\n', details.datetime, details.relativeTime)
        entry = entry .. string.format('        "file_line": "%s",\n', details.file_line)
        entry = entry .. string.format('        "mark": "%s",\n', escape_string(details.mark))
        entry = entry .. string.format('        "annotation": "%s",\n', escape_string(details.annotation or ""))
        -- entry = entry .. string.format('        "relativeTime": "%s"\n', details.relativeTime)
        entry = entry .. "    }"
        table.insert(parts, entry)
    end
    local entries = table.concat(parts, ",\n")
    local jsonOutput = "{\n" .. entries .. "\n}"
    return jsonOutput
end

-- This function is used to convert and save bookmarks in a format where the most recent bookmarks are listed first.
function M.convertAndSaveBookmarksRecentFirst()
    if not config.cache or not config.cache.data then
        vim.notify("convertAndSaveBookmarksRecentFirst Error: config.cache is not initialized", vim.log.levels.INFO)
        return
    end

    local bookmarksData = config.cache.data
    local transformedData = {}

    -- Transform data into a sortable structure
    for file, bookmarks in pairs(bookmarksData) do
        for line, bookmark in pairs(bookmarks) do
            local datetimeRelative = datetime_to_relative(bookmark.datetime)
            local timestamp = os.time(parse_datetime_to_table(bookmark.datetime))
            table.insert(transformedData, {
                timestamp = timestamp, -- for sorting
                datetime = bookmark.datetime, -- original datetime string
                file_line = file .. ":" .. tostring(line),
                mark = bookmark.mark,
                annotation = bookmark.annotation or "",
                relativeTime = datetimeRelative
            })
        end
    end

    -- Sort by timestamp in descending order
    table.sort(transformedData, function(a, b) return a.timestamp > b.timestamp end)

    -- Convert to JSON
    local newDataJson = pretty_print_json_custom_recent_date_files_list(transformedData)
    utils.write_file(config.save_file .. "_recent-first.json", newDataJson)
end

function M.runThisOnLoad()
    -- vim.notify("BookmarkNvim.runThisOnLoad called INFO notify", vim.log.levels.INFO)
    -- M.saveBookmarks()
end

M.runThisOnLoad()

return M
