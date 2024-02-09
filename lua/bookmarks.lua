-- This module provides functionality for managing bookmarks in Neovim.
-- It includes functions for attaching and detaching bookmarks to buffers,
-- loading and saving bookmarks, setting up autocmd events, and configuring
-- the behavior of the bookmark system.

local void = require("bookmarks.async").void
local scheduler = require("bookmarks.async").scheduler
local api = vim.api
-- local uv = vim.loop
local current_buf = api.nvim_get_current_buf
local config = require "bookmarks.config"
local nvim = require "bookmarks.nvim"
local hl = require "bookmarks.highlight"
local actions = require "bookmarks.actions"

local M = {}

-- Wraps a function with its arguments, allowing it to be called later.
local function wrap_func(fn, ...)
   local args = { ... }
   local nargs = select("#", ...)
   return function()
      fn(unpack(args, 1, nargs))
   end
end

-- Sets up an autocmd event with the given event name and options.
-- If the options parameter is a function, it is wrapped with its arguments.
-- The autocmd event is assigned to the "bookmarks" group.
local function autocmd(event, opts)
   local opts0 = {}
   if type(opts) == "function" then
      opts0.callback = wrap_func(opts)
   else
      opts0 = opts
   end
   opts0.group = "bookmarks"
   nvim.autocmd(event, opts0)
end

-- Detaches the bookmark system from a buffer when it is detached.
local function on_detach(_, bufnr)
   M.detach(bufnr, true)
end

-- Attaches the bookmark system to a buffer.
-- If no buffer number is provided, the current buffer is used.
-- Loads bookmarks and calls the on_attach function if provided in the configuration.
-- Attaches an autocmd event for detaching the bookmark system when the buffer is detached.
M.attach = void(function(bufnr)
   bufnr = bufnr or current_buf()
   scheduler()
   actions.loadBookmarks()
   if config.config.on_attach then
      config.config.on_attach(bufnr)
   end
   if not api.nvim_buf_is_loaded(bufnr) then return end
   api.nvim_buf_attach(bufnr, false, {
      on_detach = on_detach,
   })
end)

-- Detaches the bookmark system from a buffer.
-- If no buffer number is provided, the current buffer is used.
-- Detaches the bookmark system from the buffer and saves the bookmarks.
M.detach_all = void(function(bufnr)
   bufnr = bufnr or current_buf()
   scheduler()
   actions.detach(bufnr)
   actions.saveBookmarks()
end)

-- Calls a function after the VimEnter event has occurred.
-- If the VimEnter event has already occurred, the function is called immediately.
-- Otherwise, an autocmd event is set up to call the function once the VimEnter event occurs.
local function on_or_after_vimenter(fn)
   if vim.v.vim_did_enter == 1 then
      fn()
   else
      nvim.autocmd("VimEnter", {
         callback = wrap_func(fn),
         once = true,
      })
   end
end

-- Sets up the bookmark system with the given configuration.
-- Builds the configuration, sets up actions, and creates the "bookmarks" augroup.
-- Attaches autocmd events for detaching bookmarks, setting up highlights,
-- attaching bookmarks, and refreshing bookmarks.
M.setup = void(function(cfg)
   config.build(cfg)
   actions.setup()
   nvim.augroup "bookmarks"
   autocmd("VimLeavePre", M.detach_all)
   autocmd("ColorScheme", hl.setup_highlights)
   on_or_after_vimenter(function()
      hl.setup_highlights()
      M.attach()
      autocmd("FocusGained", actions.refresh)
      autocmd("BufReadPost", actions.refresh)
   end)
end)

-- Set the metatable of M to allow accessing actions functions directly.
return setmetatable(M, {
   __index = function(_, f)
      return actions[f]
   end,
})
