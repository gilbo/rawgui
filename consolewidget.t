--
--  consolewidget.t
--
--  Copyright 2015 Gilbert Bernstein
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--

local ConsoleWidget = {}
package.loaded['consolewidget'] = ConsoleWidget

---------------------------------------------

local RawGUI  = require 'rawgui'
local Widget  = RawGUI.Widget
local SDL     = require 'SDL'

local P       = require 'primitives'
local Color   = P.Color

-- set widget prototype chain now
RawGUI.SubClassWidget(ConsoleWidget, 'ConsoleWidget')






local function NewConsoleWidget(args)
  local console = setmetatable({
    _textlines    = {''}, -- not a great representation
    _cmdhistory   = {''},
    _cmdline      = '',
    _cursor_pos   = 1,
    _history_pos  = 1,
    _exec_clbk    = function() end,
    _padding      = args.padding or 0,
  }, ConsoleWidget)
  RawGUI.Widget._initialize(console, args)

  console:setTextColor(args.textcolor or P.NewColorUnsafe(255,255,255,255))
  console:setBackColor(args.backcolor or P.NewColorUnsafe(0,0,0,255))

  console:setFontSize(args.fontsize or 14)
  return console
end
ConsoleWidget.New = NewConsoleWidget

function ConsoleWidget:destroy()
  if self._font then
    RawGUI.ReleaseFont(self._font)
    self._font = nil
  end
  -- release this memory as quickly as possible
  self._textlines   = nil
  self._cmdhistory  = nil
end

function ConsoleWidget:setPxBox(box)
  RawGUI.Widget.setPxBox(self, box)
  self:_ResetMeasurements()
end
function ConsoleWidget:setTextColor(color)
  self._textcolor = P.NewColor(color)
end
function ConsoleWidget:setBackColor(color)
  self._backcolor = P.NewColor(color)
end

function ConsoleWidget:getTextColor()
  return self._textcolor:clone()
end
function ConsoleWidget:getBackColor()
  return self._backcolor:clone()
end

function ConsoleWidget:setFontSize(pts)
  if self._font then
    RawGUI.ReleaseFont(self._font)
  end

  -- note that we rely on monospace for sizing
  self._fontsize    = pts
  self._font        = RawGUI.CheckoutFont {
    file = 'fonts/OsakaMono.ttf',
    pts  = pts,
    bold = false,
  }
  self._charwidth   = self._font:sizeText('M')._0
  self._lineheight  = self._font:lineSkip()
  self:_ResetMeasurements()
end
function ConsoleWidget:_ResetMeasurements()
  local w = self._pxbox.w - 2*self._padding
  local h = self._pxbox.h - 2*self._padding
  self._n_chars_per_line  = math.floor(w/self._charwidth)
  self._n_lines_on_screen = math.floor(h/self._lineheight)
end
function ConsoleWidget:getFontSize()
  return self._fontsize
end
function ConsoleWidget:getCharsPerLine()
  return self._n_chars_per_line
end
function ConsoleWidget:getLinesForHeight()
  return self._n_lines_on_screen
end
function ConsoleWidget:getWidthForNChars(nchars)
  return 2*self._padding + self._charwidth * nchars
end
function ConsoleWidget:getHeightForNLines(nlines)
  return 2*self._padding + self._lineheight * nlines
end

local function drawConsoleCursor(win, console)
  local filled = console:hasKeyFocus()

  local w = console._charwidth
  local h = console._lineheight
  local x = console._pxbox.l + console._padding +
            (1 + console._cursor_pos) * w
  local y = console._pxbox.b - h - console._padding

  if filled then
    win:beginPath()
    win:rectangle(x,y,w,h)
    win:fill()
  else
    -- adjust position to get crisp stroked hairlines
    x = x + 0.5
    y = y + 0.5
    win:beginPath()
    win:rectangle(x,y,w,h)
    win:setLineWidth(1)
    win:stroke()
  end
end
function ConsoleWidget:draw()
  local win = RawGUI.GetMainWindow()
  win:cairoSave()

  -- draw backdrop
  win:setColor(self._backcolor:unpack())
  win:rectangle(self._pxbox:unpack_ltwh())
  win:fill()

  -- draw text
    -- set text color
    win:setColor(self._textcolor:unpack())

    -- prepare variables
    local i       = #self._textlines
    local top     = self._pxbox.t
    local lineh   = self._lineheight
    local y       = self._pxbox.b - lineh - self._padding
    local x       = self._pxbox.l + self._padding

    -- draw command line first
    win:drawText(self._font, '> '..self._cmdline, x, y)
    y = y - lineh

  -- draw text bottom up
  while i > 0 and y >= self._pxbox.t do
    local line = self._textlines[i]
    if #line > 0 then
      win:drawText(self._font, line, x, y)
    end
    y = y - lineh
    i = i - 1 -- jump back a line
  end
  drawConsoleCursor(win, self)

  win:cairoRestore()
end








function ConsoleWidget:appendText(txt)
  -- normalize end of line characters
  txt = txt:gsub('\r\n?','\n')

  -- have to do some line breaking
  local N = #self._textlines
  while #txt > 0 do
    -- find the next breakpoint
    local wrap = self._n_chars_per_line - #self._textlines[N]
    local nl   = string.find(txt, '\n', 1, true)
    if nl and nl <= wrap then
      self._textlines[N] = self._textlines[N] .. txt:sub(1,nl-1)
      txt = txt:sub(nl+1)
      -- add new-line
      N = N + 1
      self._textlines[N] = ''
    elseif #txt >= wrap then
      self._textlines[N] = self._textlines[N] .. txt:sub(1,wrap)
      txt = txt:sub(wrap+1)
      -- add new-line
      N = N + 1
      self._textlines[N] = ''
    else
      -- just append and don't create a new line
      self._textlines[N] = self._textlines[N] .. txt
      txt = ''
    end
  end
end
function ConsoleWidget:wouldAppendCauseNewLine(txt)
  -- obviously line breaks will cause
  if string.find(txt, '\n', 1, true) or
     string.find(txt, '\r', 1, true)
  then
    return true
  end
  -- otherwise, check for overflow
  local N     = #self._textlines
  local wrap  = self._n_chars_per_line - #self._textlines[N]
  if #txt >= wrap then return true end
  -- looks safe
  return false
end

local function splitAtCursor(console)
  local before = console._cmdline:sub(1,console._cursor_pos-1)
  local after  = console._cmdline:sub(console._cursor_pos)
  return before, after
end
function ConsoleWidget:wouldInsertOverflowCommandline(txt)
  local linelen = #self._cmdline + 2 + #txt -- 2 for '> '
  return linelen >= self._n_chars_per_line
end
function ConsoleWidget:insertCmdText(txt)
  if txt:find('\n') then
    error('INTERNAL: Please Append, not Insert Newlines')
  end
  if self:wouldInsertOverflowCommandline(txt) then
    error('CMDLINE OVERFLOW')
  end

  local before, after = splitAtCursor(self)
  self._cmdline = before .. txt .. after
  self._cursor_pos = self._cursor_pos + #txt
end
function ConsoleWidget:getCmdLine()
  return self._cmdline
end
function ConsoleWidget:clearCmdLine()
  self._cmdline = ''
  self._cursor_pos = 1
end
function ConsoleWidget:setCmdLine(txt)
  self._cmdline = txt
  self._cursor_pos = #txt + 1
end

function ConsoleWidget:cursorDeleteBack()
  local before, after = splitAtCursor(self)
  self._cmdline = before:sub(1,-2) .. after
  if self._cursor_pos > 1 then
    self._cursor_pos = self._cursor_pos - 1
  end
end
function ConsoleWidget:cursorBack()
  if self._cursor_pos > 1 then
    self._cursor_pos = self._cursor_pos - 1
  end
end
function ConsoleWidget:cursorFwd()
  if self._cursor_pos <= #self._cmdline then
    self._cursor_pos = self._cursor_pos + 1
  end
end

--function ConsoleWidget:getLastLine()
--  return self._textlines[#self._textlines]
--end
--function ConsoleWidget:clearLastLine()
--  self._textlines[#self._textlines] = ''
--end
--function ConsoleWidget:setLastLine(str)
--  self._textlines[#self._textlines] = str
--end
--function ConsoleWidget:backspaceOnLastLine()
--  local N = #self._textlines
--  local str = self._textlines[N]
--  self._textlines[N] = str:sub(1,-2)
--end






function ConsoleWidget:onExecute(clbk)
  self._exec_clbk = clbk
end
function ConsoleWidget:print(str)
  self:appendText(str..'\n')
end


local function readCmdLine(console)
  return console:getCmdLine()
end
local function historySaveCmd(console, cmdline)
  local N = #console._cmdhistory
  -- commit the entered command to history
  console._cmdhistory[N] = cmdline
  -- advance the history buffer and pointer
  console._cmdhistory[N+1] = ''
  console._history_pos = N+1
end
local function jumpHistory(console, inc)
  local H = console._history_pos + inc
  console._history_pos = H
  console:setCmdLine(console._cmdhistory[H])
end
function ConsoleWidget:GrabKeyFocus()
  Widget.GrabKeyFocus(self)
  if not SDL.IsTextInputActive() then
    SDL.StartTextInput()
  end
end
function ConsoleWidget:ReleaseKeyFocus()
  SDL.StopTextInput()
  Widget.ReleaseKeyFocus(self)
end
function ConsoleWidget:route(event)
  local caught_event = true
  
  -- way to gain key-focus
  if     event.type == 'MOUSEDOWN' then
    self:GrabKeyFocus()

  elseif event.type == 'TEXTINPUT' and self:hasKeyFocus() then
    if not self:wouldInsertOverflowCommandline(event.text) then
      self:insertCmdText(event.text)
    end

  elseif event.type == 'KEYDOWN' and self:hasKeyFocus() then
    if      event.key == 'Return' then
      -- get the command
      local cmdline = readCmdLine(self)
      self:print('\n> '..cmdline)

      -- remember this command
      historySaveCmd(self, cmdline)
      self:clearCmdLine()

      -- execute and print output
      local output = self._exec_clbk(cmdline)
      if output then self:appendText(output) end

    elseif  event.key == 'Up' then
      if self._history_pos > 1 then -- limit
        if self._history_pos == #self._cmdhistory then -- at the last point
          self._cmdhistory[self._history_pos] = self:getCmdLine()
        end
        jumpHistory(self, -1)
      end

    elseif  event.key == 'Down' then
      if self._history_pos < #self._cmdhistory then
        jumpHistory(self, 1)
      end

    elseif  event.key == 'Left' then
      self:cursorBack()
    elseif  event.key == 'Right' then
      self:cursorFwd()

    elseif  event.key == 'Backspace' then
      self:cursorDeleteBack()

    else
      caught_event = false
    end

  else
    caught_event = false
  end
  if caught_event then RawGUI.CaptureCurrentEvent() end
end





function ConsoleWidget.DefaultLuaTerraEval(cmdline)
  cmdline = cmdline:gsub('^%s*=', 'return ')
  local has_return = cmdline:find('^%s*return')

  local output = nil
  xpcall(function()
    local cmd, err = terralib.loadstring(cmdline)
    if not cmd then
      output = tostring(err)
    else
      local result = cmd()
      if has_return then 
        output = tostring(result)
      end
    end
  end, function(err)
    output = tostring(err)
  end)

  return output
end




