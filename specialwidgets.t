--
--  specialwidgets.t
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


-- Compared to Assorted Widgets, these are more highly specialized
-- Widgets intended for fairly singular/specific jobs

local Exports = {}
package.loaded['specialwidgets'] = Exports

---------------------------------------------

local SDL       = require 'SDL'
local RawGUI    = require 'rawgui'
local Widget    = RawGUI.Widget
local Viewport  = require 'viewport'
local P         = require 'primitives'
local NColor    = P.NewColorUnsafe
local NVec      = P.NewVecUnsafe

local AssortedWidgets   = require 'assortedwidgets'
local SignalMonitor     = AssortedWidgets.SignalMonitor
local Label             = AssortedWidgets.Label
local TextBox           = AssortedWidgets.TextBox
local SelectScroller    = AssortedWidgets.SelectScroller
local Button            = AssortedWidgets.Button

local PNModule          = require 'pathname'
local PN                = PNModule.Pathname


-- ------------------------------------------------------------------------- --
--                            FRAME TIME MONITOR                             --
-- ------------------------------------------------------------------------- --

local FTMonitor     = RawGUI.SubClassWidget({}, 'FTMonitor')
Exports.FTMonitor   = FTMonitor

function FTMonitor.New(args)
  local color = P.NewColor(args.color or {r=127, g=127, b=127, a=127})
  local pxbox = P.NewBox(args.pxbox)
  local ftm = setmetatable({
    _color  = color,
  }, FTMonitor)
  Widget._initialize(ftm, args)

  ftm._graph = SignalMonitor.New {
    pxbox     = pxbox,
    linecolor = color,
    textcolor = color,
  }
  ftm._graph:setMinMax(0,60)
  ftm._graph:onDraw(function()
    local frametime = RawGUI.GetLastDrawTime()
    if frametime then ftm._graph:addSample(1.0e3 * frametime) end
  end)

  ftm._label = Label.New {
    text        = 'ms/frame',
    pos         = pxbox:rt(),
    bold        = true,
    textcolor   = color,
  }
  local textw = ftm._label:getPxBox().w
  ftm._label:setPos( pxbox:rt() - NVec(textw, 0) )

  return ftm
end
function FTMonitor:destroy()
  self._graph:destroy()
  self._label:destroy()
end

function FTMonitor:setPxBox(box)
  Widget.setPxBox(self, box)
  box = self._pxbox

  self._graph:setPxBox(box)

  local labelw = self._label:getPxBox().w
  self._label:setPos( box:rt() - NVec(labelw, 0) )
end
function FTMonitor:setColor(c)
  c = P.NewColor(c)
  self._color = c
  self._graph:setLineColor(c)
  self._graph:setTextColor(c)
  self._label:setTextColor(c)
end
function FTMonitor:getColor()
  return self._color
end

function FTMonitor:draw()
  self._graph:draw()
  self._label:draw()
end

function FTMonitor:testPxBox() return false end
function FTMonitor:route() end





-- ------------------------------------------------------------------------- --
--                                FILE PICKER                                --
-- ------------------------------------------------------------------------- --

local FilePicker    = RawGUI.SubClassWidget({}, 'FilePicker')
Exports.FilePicker  = FilePicker

local function FP_get_dir_files(dirpath)
  local dirfiles = dirpath:isroot() and {} or {'..'}
  for child in dirpath:basechildren() do
    if (dirpath..child):isdir() then
      child = child..'/'
    end
    table.insert(dirfiles, child)
  end
  return dirfiles
end

function FilePicker.New(args)
  local backcolor   = P.NewColor(args.backcolor or {r=239,g=239,b=239,a=255})
  local highlightcolor = P.NewColor(args.highlightcolor or
                                    {r=255,g=255,b=255,a=255})
  local textcolor   = P.NewColor(args.backcolor or {r=31,g=31,b=31,a=255})
  local strokecolor = P.NewColor(args.strokecolor or {r=31,g=31,b=31,a=255})
  local margincolor = P.NewColor(args.margincolor or {r=223,g=223,b=223,a=255})

  local margin      = (args.margin or 10) + 1

  local path        = args.path and PN.new(args.path) or PN.pwd
  local dir         = path:isdir()  and path or path:dirpath()
  local file        = path:isfile() and path:basename() or PN.new('')


  local pxbox = P.NewBox(args.pxbox)
  local fp = setmetatable({
    _curr_dir       = dir,
    _rw_mode        = args.write and 'w' or 'r',
    _margin         = margin,
    _backcolor      = backcolor,
    _highlightcolor = highlightcolor,
    _textcolor      = textcolor,
    _strokecolor    = strokecolor,
    _margincolor    = margincolor,

    -- button height / width
    _btnh           = 20,
    _btnw           = 52,
  }, FilePicker)
  Widget._initialize(fp, args)
  
  local y = pxbox.t + margin
  local x = pxbox.l + margin
  local w = pxbox.w - 2*margin
  local h = pxbox.h - 2*margin
  if fp._rw_mode == 'w' then
    fp._filebox = TextBox.New {
      pxbox           = { x=x, y=y, w=w, h=10 },
      padding         = 1,
      backcolor       = backcolor,
      highlightcolor  = highlightcolor,
      textcolor       = textcolor,
      strokecolor     = strokecolor,
    }
    local lineh = fp._filebox:getPxBox().h
    y = y + lineh + margin
  end

  local btnh = fp._btnh
  local btnw = fp._btnw

  local dirh = (pxbox.b - 2*margin - btnh) - y
  local dirw = w
  fp._dirbox = SelectScroller.New {
    options         = FP_get_dir_files(dir),
    pxbox           = { x=x, y=y, w=dirw, h=dirh },
    padding         = 1,
    backcolor       = backcolor,
    highlightcolor  = highlightcolor,
    textcolor       = textcolor,
    strokecolor     = strokecolor,
  }

  x = pxbox.r - 2*margin - 2*btnw
  y = pxbox.b - margin - btnh

  fp._cancelbtn = Button.New {
    pxbox = { x=x, y=y, w=btnw, h=btnh }
  }
  fp._cancellabel = Label.New {
    text        = 'Cancel',
    pos         = NVec(x+5,y+2),
    --bold        = true,
    textcolor   = textcolor,
  }
  x = x + margin + btnw
  fp._confirmbtn = Button.New {
    pxbox = { x=x, y=y, w=btnw, h=btnh }
  }

  -- wire things up
  if fp._filebox then
    fp._filebox:onReturnPress(function(file)
      if fp:_HasValidSaveFile() then
        fp._confirm_clbk(tostring(fp._curr_dir..file))
      end
    end)
  end
  fp._dirbox:onSelectionChange(function(file)
    if not file then return end
    local path = fp._curr_dir..file
    if fp._rw_mode == 'w' then
      if path:isfile() then
        fp._filebox:setText(file)
      else
        fp._filebox:setText('')
      end
    end
  end)
  fp._dirbox:onSelectionConfirm(function(file)
    local path = fp._curr_dir..file
    if path:isdir() then  fp:_JumpDirs(path)
    else
      fp._confirm_clbk(tostring(path))
    end
  end)
  fp._cancelbtn:onPress(function()
    fp._cancel_clbk()
  end)
  fp._confirmbtn:onPress(function()
    -- Cases:
    if fp._rw_mode == 'w' then
      -- write: there is a name in the filebox
      if fp:_HasValidSaveFile() then
        fp._confirm_clbk( tostring(fp._curr_dir..fp._filebox:getText()) )
      -- write: there is a selected directory
      elseif fp:_IsDirSelected() then
        fp:_JumpDirs(fp._curr_dir..fp._dirbox:getSelectText())
      end
    else -- 'r'
      -- read: there is a selected directory
      if fp:_IsDirSelected() then
        fp:_JumpDirs(fp._curr_dir..fp._dirbox:getSelectText())
      -- read: there is a selected file
      elseif fp:_IsFileSelected() then
        fp._confirm_clbk(
          tostring(fp._curr_dir..fp._dirbox:getSelectText()) )
      end
    end
    -- BASED on these cases, should display appropriate label...
  end)

  return fp
end
function FilePicker:destroy()
  if self._filebox then self._filebox:destroy() end
  self._dirbox:destroy()
  self._cancellabel:destroy()
  if self._confirmlabel then self._confirmlabel:destroy() end
end

function FilePicker._cancel_clbk() end
function FilePicker._confirm_clbk(pathstr) end
function FilePicker:onCancel(clbk)  self._cancel_clbk   = clbk  end
function FilePicker:onConfirm(clbk) self._confirm_clbk  = clbk  end

function FilePicker:_SetConfirmText(txt)
  -- is there an actual change?
  local currtxt = self._confirmlabel and self._confirmlabel:getText() or ''
  if not txt then txt = '' end
  if currtxt == txt then return end


  -- if so, then free previous label
  if self._confirmlabel then
    self._confirmlabel:destroy()
    self._confirmlabel = nil
  end
  -- and create a new label if needed
  if txt ~= '' then 
    local x = self._pxbox.r - self._margin - self._btnw
    local y = self._pxbox.b - self._margin - self._btnh
    self._confirmlabel = Label.New {
      text        = txt,
      pos         = NVec(x+11,y+2),
      --bold        = true,
      textcolor   = self._textcolor,
    }
  end
end

function FilePicker:setPxBox(box)
  Widget.setPxBox(self, box)
  box = self._pxbox

  local x = box.l + self._margin
  local y = box.t + self._margin
  local w = box.w - 2 * self._margin
  local h = box.h - 2 * self._margin
  if self._filebox then
    local lineh = self._filebox.h
    self._filebox:setPxBox { l=x+box.l, t=y+box.t, w=w, h=lineh }
    y = y + self._margin + lineh
  end

  local dirh = (box.b - 2*self._margin - self._btnh) - y
  local dirw = w
  self._dirbox:setPxBox { l=x+box.l, t=y+box.t, w=dirw, h=dirh }

  x = pxbox.r - 2*self._margin - 2*self._btnw
  y = pxbox.b - margin - self._btnh
  self._cancelbtn:setPxBox { x=x, y=y, w=self._btnw, h=self._btnh }
  self._cancellabel:setPos( NVec(x+5,y+2) )
  x = x + self._margin + self._btnw
  self._confirmbtn:setPxBox { x=x, y=y, w=self._btnw, h=self._btnh }
  if self._confirmlabel then
    self._confirmlabel:setPos( NVec(x+5,y+2))
  end
end
function FilePicker:setBackColor(c)
  c = P.NewColor(c)
  self._backcolor = c
  if self._filebox then self._filebox:setBackColor(c) end
  self._dirbox:setBackColor(c)
end
function FilePicker:setHighlightColor(c)
  c = P.NewColor(c)
  self._highlightcolor = c
  --if self._filebox then self._filebox:setHighlightColor(c) end
  self._dirbox:setHighlightColor(c)
end
function FilePicker:setTextColor(c)
  c = P.NewColor(c)
  self._textcolor = c
  if self._filebox then self._filebox:setTextColor(c) end
  self._dirbox:setTextColor(c)
end
function FilePicker:setStrokeColor(c)
  c = P.NewColor(c)
  self._strokecolor = c
  if self._filebox then self._filebox:setStrokeColor(c) end
  self._dirbox:setStrokeColor(c)
end
function FilePicker:setMarginColor(c)
  c = P.NewColor(c)
  self._margincolor = c
end
function FilePicker:getBackColor()
  return self._backcolor
end
function FilePicker:getHighlightColor()
  return self._highlightcolor
end
function FilePicker:getTextColor()
  return self._textcolor
end
function FilePicker:getStrokeColor()
  return self._strokecolor
end
function FilePicker:getMarginColor()
  return self._margincolor
end

function FilePicker:draw()
  local win = RawGUI.GetMainWindow()
  win:cairoSave()
  -- draw backdrop
  win:rectangle(self._pxbox:expandBy(-0.5):unpack_ltwh())
  win:setColor(self._margincolor:unpack())
  win:fillAndKeepPath()
  win:setLineWidth(1)
  win:setColor(self._strokecolor:unpack())
  win:stroke()

  win:cairoRestore()

  -- try to set confirm label state
  local sel = self._dirbox:getSelectText()
  if self._rw_mode == 'w' and self:_HasValidSaveFile() then
    self:_SetConfirmText('Save')
  elseif sel and (sel == '..' or sel:sub(-1) == '/') then
    self:_SetConfirmText('Open')
  elseif sel and self._rw_mode == 'r' then
    self:_SetConfirmText('Open')
  else
    self:_SetConfirmText('')
  end

  -- draw sub-widgets
  if self._filebox then self._filebox:draw() end
  self._dirbox:draw()
  self._cancelbtn:draw()
  self._confirmbtn:draw()
  self._cancellabel:draw()
  if self._confirmlabel then self._confirmlabel:draw() end
end


function FilePicker:_JumpDirs(newpath)
  self._curr_dir = newpath:cleanpath()
  self._dirbox:setOptions(FP_get_dir_files(newpath))
end
function FilePicker:_HasValidSaveFile()
  local filename = self._filebox and self._filebox:getText() or ''
  if #filename == 0 then return false end

  return PNModule.isvalidfilename(filename)
end
function FilePicker:_IsFileSelected()
  local selected = self._dirbox:getSelectText()
  if not selected then return false end

  return (self._curr_dir..selected):isfile()
end
function FilePicker:_IsDirSelected()
  local selected = self._dirbox:getSelectText()
  if not selected then return false end

  return (self._curr_dir..selected):isdir()
end


-- need to track mouse_enter mouse_leave state
function FilePicker:_RouteTo(newsubw, event)
  local lastsubw = self._oversubw
  -- any mouseleave/mouseenter events?
  if lastsubw ~= newsubw then
    if lastsubw then lastsubw:route( event:derive('MOUSE_LEAVE') )  end
    if newsubw  then newsubw:route( event:derive('MOUSE_ENTER') )   end
  end
  -- do main routing
  if newsubw then newsubw:route(event) end
  -- update last subwidget dispatched to
  self._oversubw = newsubw
end
function FilePicker:route(event)
  local mousepos = NVec(event:mousePos())
  local lastsubw = self._oversubw

  if event.type == 'MOUSE_LEAVE' then
    self:_RouteTo(nil, event)
  else
    if self._filebox and self._filebox:testPxBox(mousepos) then
      self:_RouteTo(self._filebox, event)
    elseif self._dirbox:testPxBox(mousepos) then
      self:_RouteTo(self._dirbox, event)
    elseif self._cancelbtn:testPxBox(mousepos) then
      self:_RouteTo(self._cancelbtn, event)
    elseif self._confirmbtn:testPxBox(mousepos) then
      self:_RouteTo(self._confirmbtn, event)
    else
      self:_RouteTo(nil, event)
    end
  end
end





