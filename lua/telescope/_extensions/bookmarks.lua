local has_telescope, telescope = pcall(require, "telescope")

if not has_telescope then
    error "This plugins requires nvim-telescope/telescope.nvim"
end

local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local entry_display = require "telescope.pickers.entry_display"
local conf = require("telescope.config").values
local config = require("bookmarks.config").config
local utils = require "telescope.utils"

local function get_text(annotation)
    local prefix = string.sub(annotation, 1, 2)
    local ret = config.keywords[prefix]
    if ret == nil then
        ret = config.signs.ann.text .. " "
    end
    return ret .. annotation
end

-- This function generates a list of bookmarks and displays them using the Telescope plugin.
-- It takes an optional 'opts' table as a parameter.
-- The function retrieves the bookmarks from the 'config.cache.data' table and creates a list of marklist.
-- Each bookmark entry in the marklist table contains the filename, line number, and text of the bookmark.
-- The 'display' function is used to format the bookmark entry for display in the Telescope results.
-- The 'entry_maker' function is used to create a valid entry for each bookmark in the marklist table.
-- Finally, the function initializes a new Telescope picker with the provided options and displays the bookmarks.
local function handleBookmarksList(options)
    options = options or {}

    -- Get all bookmarks from the cache
    local allBookmarks = config.cache.data

    -- Initialize an empty table to store the list of bookmarks
    local bookmarkList = {}

    -- Iterate over all bookmarks
    for filename, marks in pairs(allBookmarks) do
        for lineNumber, mark in pairs(marks) do
            -- Insert each bookmark into the bookmarkList

            local m = mark.mark or mark.m or ""
            -- remove the surrounding white space
            m = string.gsub(m, "^%s*(.-)%s*$", "%1")
            local a = mark.annotation or mark.a or ""
           --  local datetime = v.datetime or ""
            local combinedText = ""
            if a ~= "" then
                combinedText = combinedText .. " -a> " .. a
            end
            combinedText = combinedText .. " -m> " .. m
            table.insert(bookmarkList, {
                filename = filename,
                lnum = tonumber(lineNumber),
                text = combinedText,
            })
        end
    end

    -- Define a function to display each bookmark
    local fnDisplayBookmark = function(bookmarkEntry)
        -- Create a displayer with specific settings
        local displayer = entry_display.create {
            separator = "▏",
            items = {
                { width = 5 },
                { width = 30 },
                { remaining = true },
            },
        }

        -- Prepare the line information
        local lineInfo = { bookmarkEntry.lnum, "TelescopeResultsLineNr" }

        -- Return the displayer with the line information, text, and filename
        return displayer {
            lineInfo,
            utils.path_smart(bookmarkEntry.filename), -- or path_tail
            (bookmarkEntry.text or bookmarkEntry.mark or ""):gsub(".* | ", ""),
        }
    end

    -- Use the picker to display the bookmarks
    pickers.new(options, {
        prompt_title = "bookmarks",
        finder = finders.new_table {
            results = bookmarkList,
            entry_maker = function(entry)
                return {
                    valid = true,
                    value = entry,
                    display = fnDisplayBookmark,
                    ordinal = entry.filename .. (entry.text or ""),
                    filename = entry.filename,
                    lnum = entry.lnum,
                    col = 1,
                    text = entry.text,
                }
            end,
        },
        sorter = conf.generic_sorter(options),
        previewer = conf.qflist_previewer(options),
    }):find()
end

return telescope.register_extension { exports = { list = handleBookmarksList } }
