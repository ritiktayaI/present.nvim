local M = {}

local function create_floating_window(config, enter)
  -- Create a buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Create the floating window
  local win = vim.api.nvim_open_win(buf, enter or false, config)

  return { buf = buf, win = win }
end

M.setup = function()
  -- do nothing
end

---@class present.Slides
---@fields slides present.Slide[]: The slides of the file

---@class present.Slide
---@fields title string: The title of the slide
---@fields body string[]: The body of the slide
---@fields blocks present.Block[]: A codeblock inside of a slide

---@class present.Block
---@field language string: The language of the codeblock
---@field body string: The body of the codeblock

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return present.Slides
local parse_slides = function(lines)
  local slides = { slides = {} }
  local current_slide = {
    title = "",
    body = {},
    blocks = {},
  }

  local separator = "^#"

  for _, line in ipairs(lines) do
    if line:find(separator) then
      if #current_slide.title > 0 then
        table.insert(slides.slides, current_slide)
      end

      current_slide = {
        title = line,
        body = {},
        blocks = {},
      }
    else
      table.insert(current_slide.body, line)
    end
  end

  table.insert(slides.slides, current_slide)

  for _, slide in ipairs(slides.slides) do
    local block = {
      language  = nil,
      body = "",
    }
    local inside_block = false
    for _, line in ipairs(slide.body) do
      if vim.startswith(line, "```") then
        if not inside_block then
          inside_block = true
          block.language = string.sub(line, 4)
        else
          inside_block = false
          block.body = vim.trim(block.body)
          table.insert(slide.blocks, block)
        end
      else
        -- OK, we are inside of a current markdown block
        -- but it is not one of the guards.
        -- So insert this text
        if inside_block then
          block.body = block.body .. line .. "\n"
        end
      end
    end
  end
  return slides
end

local create_window_configurations = function()
  local width = vim.o.columns
  local height = vim.o.lines

  local header_height = 3
  local footer_height = 1
  local body_height = height - header_height - footer_height - 2 - 3

  return {
    background = {
      relative = "editor",
      width = width,
      height = height,
      col = 0,
      row = 0,
      style = "minimal",
      zindex = 1,
    },
    header = {
      relative = "editor",
      width = width,
      height = header_height,
      -- border = { " ", " ", " ", " ", " ", " ", " ", " ", },
      -- border = "rounded",
      col = 0,
      row = 0,
      style = "minimal",
      zindex = 2,
    },
    body = {
      relative = "editor",
      width = width - 8,
      height = body_height,
      -- border = { " ", " ", " ", " ", " ", " ", " ", " ", },
      col = 8,
      row = 3,
      style = "minimal",
    },
    footer = {
      relative = "editor",
      width = width,
      height = 1,
      -- border = { " ", " ", " ", " ", " ", " ", " ", " ", },
      -- border = "rounded",
      col = 0,
      row = height - 1,
      style = "minimal",
      zindex = 2,
    },
  }
end

local state = {
  current_slide = 1,
  parsed = {
    slides = {},
  },
  floats = {
    background = {},
    header = {},
    body = {},
    footer = {},
  },
}

local foreach_float = function(cb)
  for name, float in pairs(state.floats) do
    cb(name, float)
  end
end

local present_keymap = function(mode, key, callback)
  vim.keymap.set(mode, key, callback, {
    buffer = state.floats.body.buf
  })
end

M.start_presentation = function(opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or 0

  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
  state.parsed = parse_slides(lines)
  state.current_slide = 1
  state.title = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ":t")

  local windows = create_window_configurations()
  state.floats.background = create_floating_window(windows.background)
  state.floats.header = create_floating_window(windows.header)
  state.floats.body = create_floating_window(windows.body, true)
  state.floats.footer = create_floating_window(windows.footer)

  foreach_float(function(_, float)
    vim.bo[float.buf].filetype = "markdown"
  end)

  local set_slide_content = function(idx)
    local slide = state.parsed.slides[idx]

    local padding = string.rep(" ", (vim.o.columns - #slide.title) / 2)
    local title = padding .. slide.title
    vim.api.nvim_buf_set_lines(state.floats.header.buf, 0, -1, false, { title })
    vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, slide.body)

    local footer_content = string.format(
      " %d / %d | %s",
      state.current_slide,
      #state.parsed.slides,
      state.title
    )
    vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, { footer_content })
  end

  present_keymap("n", "n", function()
    state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
    set_slide_content(state.current_slide)
  end)

  present_keymap("n", "p", function()
    state.current_slide = math.max(state.current_slide - 1, 1)
    set_slide_content(state.current_slide)
  end)

  present_keymap("n", "q", function()
    vim.api.nvim_win_close(state.floats.body.win, true)
  end)

  present_keymap("n", "X", function()
    local slide = state.parsed.slides[state.current_slide]
    -- TODO: Make a way for people to execute this for other languages
    local block = slide.blocks[1]
    if not block then
      print("No blocks on this page")
      return
    end

    -- Override the default print function, to capture all of the output
    -- Store the original print function
    local original_print = print

    -- Table to capture print messages
    local output = { "", "# Code", "" }

    -- Redefine the print function
    print = function(...)
      local args = {...}
      local message = table.concat(vim.tbl_map(tostring, args), "\t")
      table.insert(output, message)
    end

    -- Call the provided function
    pcall(function()
      local block = vim.api.nvim_buf_get_lines(bufnr, block_start, block_end - 1, false)

      local chunk = vim.api.nvim_buf_get_lines(bufnr, block_start - 1, block_end, false)

    local chunk = loadstring(block.body)
    chunk()
  end)

  local restore = {
    cmdheight = {
      original = vim.o.cmdheight,
      present = 0,
    }
  }

  -- Set the options we want during presentation
  for option, config in pairs(restore) do
    vim.opt[option] = config.present
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = state.floats.body.buf,
    callback = function()
      -- Reset the values when we are done with the presentation
      for option, config in pairs(restore) do
        vim.opt[option] = config.original
      end

      foreach_float(function(_, float)
        pcall(vim.api.nvim_win_close, float.win, true)
      end)
    end
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("present-resized", {}),
    callback = function()
      if state.floats.body.win == nil or not vim.api.nvim_win_is_valid(state.floats.body.win) then
        return
      end

      local updated = create_window_configurations()
      foreach_float(function(name, float)
        vim.api.nvim_win_set_config(float.background.win, updated[name])
      end)
    end
  })

  set_slide_content(state.current_slide)
end

M.start_presentation { bufnr = 6 }

M._parse_slides = parse_slides

return M
