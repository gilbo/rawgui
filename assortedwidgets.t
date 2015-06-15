--
--  assortedwidgets.t
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

local Exports = {}
package.loaded['assortedwidgets'] = Exports

---------------------------------------------

local SDL       = require 'SDL'
local RawGUI    = require 'rawgui'
local Widget    = RawGUI.Widget
local Viewport  = require 'viewport'
local P         = require 'primitives'
local NColor    = P.NewColorUnsafe
local NVec      = P.NewVecUnsafe


-- ------------------------------------------------------------------------- --
--                              SIGNAL MONITOR                               --
-- ------------------------------------------------------------------------- --

local SignalMonitor = RawGUI.SubClassWidget({}, 'SignalMonitor')
Exports.SignalMonitor = SignalMonitor

function SignalMonitor.New(args)
  local monitor = setmetatable({
    _samples      = {},
    _max          = nil,
    _min          = nil,
    _params       = {
      tickpow       = 10, -- scale at which to display ticks
      tickminfreq   = 8, -- minimum pixels between ticks
      ticklen       = 2, -- px length of ticks
      sampfreq      = 2, -- px between samples horizontally
    },
    --_exec_clbk    = function() end,
    _padding      = args.padding or 0,
    _draw_clbk    = function() end,
  }, SignalMonitor)
  Widget._initialize(monitor, args)

  monitor:setLineColor(args.linecolor or NColor(0,0,0,255))
  monitor:setTextColor(args.textcolor or NColor(0,0,0,255))
  monitor:setBackColor(args.backcolor)

  monitor:setFontSize(args.fontsize or 14)
  return monitor
end
function SignalMonitor:destroy()
  if self._font then
    RawGUI.ReleaseFont(self._font)
    self._font = nil
  end
end

function SignalMonitor:setPxBox(box)
  Widget.setPxBox(self, box)
  self:_ResetMeasurements()
end

function SignalMonitor:setLineColor(color)
  self._linecolor = P.NewColor(color)
end
function SignalMonitor:setTextColor(color)
  self._textcolor = P.NewColor(color)
end
function SignalMonitor:setBackColor(color)
  if not color then self._backcolor = nil
               else self._backcolor = P.NewColor(color) end
end

function SignalMonitor:setFontSize(pts)
  if self._font then
    RawGUI.ReleaseFont(self._font)
  end

  self._fontsize    = pts
  self._font        = RawGUI.CheckoutFont {
    file = 'fonts/OsakaMono.ttf',
    pts  = pts,
    bold = true,
  }
  self._lineheight  = self._font:lineSkip()
  self:_ResetMeasurements()
end
function SignalMonitor:getFontSize()
  return self._fontsize
end

function SignalMonitor:setMinMax(min,max)
  self._min = min
  self._max = max
  self:_ResetMeasurements()
end
function SignalMonitor:_ResetMeasurements()
  if self._max and self._min then
    local p = self._params

    -- compute the scaling factor
    local yspace = self._pxbox.h - 2*self._padding
    local vspace = self._max - self._min
    local v_to_y = yspace / vspace
    self._v_to_y = v_to_y

    -- find the right octave in which to place ticks
    local minv_spacing = p.tickminfreq / v_to_y
    local octave = 1
    if octave > minv_spacing then
      while octave / p.tickpow > minv_spacing do
        octave = octave / p.tickpow
      end
    else
      while octave <= minv_spacing do
        octave = octave * p.tickpow
      end
    end

    -- compute tick values and heights
    local val = math.floor(self._min/octave) * octave
    local y   = self._pxbox.b + v_to_y * (val-self._min)
    local yjump = v_to_y * octave
    self._ticks = {}
    while y > self._pxbox.t do
      table.insert(self._ticks, { v=val, y=y })
      y   = y - yjump
      val = val + octave
    end
  end
end

function SignalMonitor:addSample(value)
  -- add sample
  table.insert(self._samples, value)
  -- make sure we bound the size of the sample buffer
  if #self._samples > self._pxbox.w / self._params.sampfreq then
    table.remove(self._samples, 1)
  end
end


function SignalMonitor:draw()
  self._draw_clbk()

  local win = RawGUI.GetMainWindow()
  local box = self._pxbox
  local pad = self._padding
  local p = self._params
  win:cairoSave()

  -- optionally draw a backdrop
  if self._backcolor then
    win:setColor(self._backcolor:unpack())
    win:rectangle(box.l, box.t, box.w, box.h)
    win:fill()
  end

  local inbox = {
    l = box.l + pad + 0.5 + p.ticklen,
    t = box.t + pad + 0.5,
    r = box.r - pad - 0.5,
    b = box.b - pad - 0.5,
  }
  local tickl = box.l - p.ticklen

  -- draw the axes
  win:setLineWidth(1)
  win:setColor(self._linecolor:unpack())
  win:beginPath()
  win:moveTo(inbox.l, inbox.t)
  win:lineTo(inbox.l, inbox.b)
  win:lineTo(inbox.r, inbox.b)
  win:stroke()

  -- draw ticks
  win:setLineWidth(1.5)
  if self._ticks then
    for _,tick in ipairs(self._ticks) do
      win:beginPath()
      win:moveTo(tickl, tick.y)
      win:lineTo(inbox.l, tick.y)
      win:stroke()
    end
  end

  -- draw samples
  if self._min and self._max and #self._samples > 1 then
    local v = self._samples[1]
    v = math.min(self._max, math.max(self._min, v)) -- clamp
    local y = inbox.b - self._v_to_y * (v - self._min)
    local x = inbox.l

    win:beginPath()
    win:moveTo(x,y)
    for i = 2,#self._samples do
      x = x + p.sampfreq
      local v = self._samples[i]
      v = math.min(self._max, math.max(self._min, v)) -- clamp
      local y = inbox.b - self._v_to_y * (v - self._min)
      win:lineTo(x,y)
    end
    win:stroke()

    -- labels
    local lineh = self._lineheight
    win:setColor(self._textcolor:unpack())
    local min = tostring(self._min):sub(1,5)
    local max = tostring(self._max):sub(1,5)
    win:drawText(self._font, min, inbox.l+2+0.5, inbox.b+0.5 - lineh)
    win:drawText(self._font, max, inbox.l+2+0.5, inbox.t-0.5)
  end

  win:cairoRestore()
end
-- disable routing
function SignalMonitor:testPxBox() return false end
--function SignalMonitor:route() end
function SignalMonitor:onDraw(clbk)
  self._draw_clbk = clbk
end








-- ------------------------------------------------------------------------- --
--                                   LABEL                                   --
-- ------------------------------------------------------------------------- --

local Label = RawGUI.SubClassWidget({}, 'Label')
Exports.Label = Label

function Label.New(args)
  if not P.isVec(args.pos) then
    error('must provide "pos" vector', 2)
  end
  local label = setmetatable({
    _text = args.text or ' ',
    _x = args.pos.x,
    _y = args.pos.y,
  }, Label)
  --Widget._initialize()

  label:setTextColor(args.textcolor or NColor(0,0,0))

  label:setFont(args.fontsize or 14, {
    bold          = args.bold,
    italic        = args.italic,
    underline     = args.underline,
    strikethrough = args.strikethrough,
    outline       = args.outline,
  })

  return label
end
function Label:destroy()
  if self._font then
    RawGUI.ReleaseFont(self._font)
    self._font = nil
  end
end


function Label:setTextColor(color)
  self._textcolor = P.NewColor(color)
end
function Label:setFont(pts, args)
  if self._font then
    RawGUI.ReleaseFont(self._font)
  end

  args = args or {}
  local argcopy = {
    file = 'fonts/OsakaMono.ttf',
    pts  = pts,
  }
  for k,v in pairs(args) do argcopy[k] = v end

  self._fontsize    = pts
  self._font        = RawGUI.CheckoutFont(argcopy)
  self._lineheight  = self._font:lineSkip()
  self:_ResetMeasurements()
end
function Label:getFontSize()
  return self._fontsize
end

function Label:setText(txt)
  self._text = tostring(txt)
  self:_ResetMeasurements()
end
function Label:getText() return self._text end
function Label:setPos(vec)
  self._x = vec.x
  self._y = vec.y
  self:_ResetMeasurements()
end
function Label:getPos()
  return P.NewVecUnsafe(self._x, self._y)
end

function Label:_ResetMeasurements()
  local wh = self._font:sizeText(self._text)
  if wh._0 < 1 or wh._1 < 1 then error('cannot have empty label', 2) end
  Widget.setPxBox(self, {
    l=self._x, t=self._y,
    w=wh._0, h=wh._1,
  })
end

-- disable use of setting the box directly
function Label:setPxBox(box) end
-- disable routing
function Label:testPxBox() return false end

function Label:draw()
  local win   = RawGUI.GetMainWindow()

  win:setColor(self._textcolor:unpack())
  win:drawText(self._font, self._text, self._x, self._y)
end




-- ------------------------------------------------------------------------- --
--                                   PANEL                                   --
-- ------------------------------------------------------------------------- --


local Panel = RawGUI.SubClassWidget({}, 'Panel')
Exports.Panel = Panel


function Panel.New(args)
  local panel = setmetatable({
    _strokewidth = args.strokewidth or 1,
  }, Panel)
  Widget._initialize(panel, args)

  panel:setFillColor(args.fillcolor)
  panel:setStrokeColor(args.strokecolor)

  return panel
end

function Panel:setStrokeWidth(w)    self._strokewidth = w       end
function Panel:getStrokeWidth()     return self._strokewidth    end

function Panel:setFillColor(color)
  self._fillcolor = color and P.NewColor(color) or nil
end
function Panel:setStrokeColor(color)
  self._strokecolor = color and P.NewColor(color) or nil
end

-- disable routing
function Panel:testPxBox() return false end

function Panel:draw()
  local win = RawGUI.GetMainWindow()
  --win:cairoSave()

  if self._fillcolor then
    win:setColor(self._fillcolor:unpack())
    win:beginPath()
    win:rectangle( self._pxbox:unpack_ltwh() )
    win:fill()
  end

  if self._strokecolor then
    win:setColor(self._strokecolor:unpack())
    win:setLineWidth(self._strokewidth)
    win:beginPath()
    win:rectangle( self._pxbox:expandBy(-0.5):unpack_ltwh() )
    win:stroke()
  end

  --win:cairoRestore()
end



-- ------------------------------------------------------------------------- --
--                                VIEW PANEL                                 --
-- ------------------------------------------------------------------------- --

local ViewPanel = RawGUI.SubClassWidget({}, 'ViewPanel', Viewport)
Exports.ViewPanel = ViewPanel


function ViewPanel.New(args)
  local vpanel = setmetatable({
    _strokewidth = args.strokewidth or 1,
  }, ViewPanel)

  vpanel:setFillColor(args.fillcolor)
  vpanel:setStrokeColor(args.strokecolor)

  return vpanel
end

function ViewPanel:setStrokeWidth(w)    self._strokewidth = w       end
function ViewPanel:getStrokeWidth()     return self._strokewidth    end

function ViewPanel:setFillColor(color)
  self._fillcolor = color and P.NewColor(color) or nil
end
function ViewPanel:setStrokeColor(color)
  self._strokecolor = color and P.NewColor(color) or nil
end

-- disable routing
function ViewPanel:testPxBox() return false end

function ViewPanel:draw()
  local win = RawGUI.GetMainWindow()
  --win:cairoSave()

  -- paint the backdrop
  if self._fillcolor then
    win:cairoSave()
    win:setColor(self._fillcolor:unpack())
    win:beginPath()
    win:rectangle( self._pxbox:unpack_ltwh() )
    win:fill()
    win:cairoRestore()
  end

  -- draw the viewport contents
  win:cairoSave()
    self:drawScene()
  win:cairoRestore()

  -- paint the outline
  if self._strokecolor then
    win:cairoSave()
    win:setColor(self._strokecolor:unpack())
    win:setLineWidth(self._strokewidth)
    win:beginPath()
    win:rectangle( self._pxbox:unpack_ltwh() )
    win:stroke()
    win:cairoRestore()
  end

  --win:cairoRestore()
end


-- ------------------------------------------------------------------------- --
--                                  BUTTON                                   --
-- ------------------------------------------------------------------------- --

local btn_fill_color = {
  ['plain'] = NColor(239,239,239,255),
  ['hover'] = NColor(223,223,223,255),
  ['press'] = NColor(191,191,191,255),
}
local btn_stroke_color  = {
  ['plain'] = NColor(191,191,191,255),
  ['hover'] = NColor(175,175,175,255),
  ['press'] = NColor(127,127,127,255),
}
function Exports.SetButtonColors(args)
  if args.fillplain then btn_fill_color.plain = args.fillplain end
  if args.fillhover then btn_fill_color.hover = args.fillhover end
  if args.fillpress then btn_fill_color.press = args.fillpress end

  if args.strokeplain then btn_stroke_color.plain = args.strokeplain end
  if args.strokehover then btn_stroke_color.hover = args.strokehover end
  if args.strokepress then btn_stroke_color.press = args.strokepress end
end


local Button = RawGUI.SubClassWidget({}, 'Button')
Exports.Button = Button

function Button:_initialize(args)
  Widget._initialize(self, args)

  self._strokewidth  = args.strokewidth or 1
  self._state        = 'plain'
  self._alpha        = args.alpha or 255
  self._text         = args.text  or nil
  self._fontsize     = args.fontsize or 14
  self._press_clbk   = args.onpress or function() end

  return self
end
function Button.New(args)
  local button = setmetatable({}, Button)
  return button:_initialize(args)
end

function Button:setStrokeWidth(w)    self._strokewidth = w       end
function Button:getStrokeWidth()     return self._strokewidth    end

function Button:onPress(clbk)
  self._press_clbk = clbk
end
function Button:route(event)
  local caught_event = true

  if      event.type == 'MOUSEDOWN'         then
    self._state = 'press'
    self:GrabMouseFocus() -- get focus on mousedown

  elseif  event.type == 'MOUSE_FOCUS_LOST'  then
    if self:testPxBox(NVec(event:mousePos())) then
      self._state = 'hover'
    else
      self._state = 'plain'
    end

  elseif  event.type == 'MOUSEUP'           then
    if self._state == 'press' then
      self._press_clbk()
    end
    -- regardless release mouse focus if we have it
    self:ReleaseMouseFocus()

  -- hover in
  elseif  event.type == 'MOUSE_ENTER' and
          not self:hasMouseFocus()          then
    self._state = 'hover'

  -- hover out
  elseif  event.type == 'MOUSE_LEAVE' and
          not self:hasMouseFocus()          then
    self._state = 'plain'

  -- drag in
  elseif  event.type == 'MOUSE_ENTER' and
          self:hasMouseFocus()              then
    self._state = 'press'

  -- drag out
  elseif  event.type == 'MOUSE_LEAVE' and
          self:hasMouseFocus()              then
    self._state = 'plain'

  else
    caught_event = false
  end
  if caught_event then RawGUI.CaptureCurrentEvent() end
end


local function common_btn_draw(btn, state)
  local win = RawGUI.GetMainWindow()

  local fillcolor   = btn_fill_color[state]:withAlpha(btn._alpha)
  local strokecolor = btn_stroke_color[state]:withAlpha(btn._alpha)

  win:beginPath()
  win:rectangle( btn._pxbox:expandBy(-0.5):unpack_ltwh() )

  win:setColor(fillcolor:unpack())
  win:fillAndKeepPath()

  win:setColor(strokecolor:unpack())
  win:setLineWidth(btn._strokewidth)
  win:stroke()

  -- maybe draw text here

end
function Button:draw()
  common_btn_draw(self, self._state)
end






-- ------------------------------------------------------------------------- --
--                               TOGGLE BUTTON                               --
-- ------------------------------------------------------------------------- --

local ToggleButton = RawGUI.SubClassWidget({}, 'ToggleButton', Button)
Exports.ToggleButton = ToggleButton

function ToggleButton:_initialize(args)
  Button._initialize(self, args)
  self._toggle_clbk = args.ontoggle or function() end
  self._is_down     = false
  -- on press, toggle!
  self._press_clbk  = function()
    self._is_down = not self._is_down
    self._toggle_clbk(self._is_down)
  end

  return self
end
function ToggleButton.New(args)
  local tbut = setmetatable({}, ToggleButton)
  return tbut:_initialize(args)
end

-- we block the ability for the caller to set onPress callbacks
function ToggleButton:onPress(clbk) end
function ToggleButton:onToggle(clbk)
  self._toggle_clbk = clbk
end
-- does not trigger an event
function ToggleButton:setToggleState(val)
  self._is_down = val
end


function ToggleButton:draw()
  local state = self._state
  if self._is_down then
    if state == 'press' then state = 'plain'
                        else state = 'press' end
  end
  common_btn_draw(self, state)
end







-- ------------------------------------------------------------------------- --
--                                  HANDLE                                   --
-- ------------------------------------------------------------------------- --

local Handle = RawGUI.SubClassWidget({}, 'Handle')
Exports.Handle = Handle


function Handle.New(args)
  local handle = setmetatable({
    _strokewidth  = args.strokewidth or 1,
    _state        = 'plain',
    _alpha        = args.alpha or 255,
  }, Handle)
  Widget._initialize(handle, args)

  if args.dragstart then handle._drag_start_clbk = args.dragstart end
  if args.dragmove  then handle._drag_move_clbk  = args.dragstart end
  if args.dragstop  then handle._drag_stop_clbk  = args.dragstart end

  return handle
end

function Handle:setStrokeWidth(w)    self._strokewidth = w       end
function Handle:getStrokeWidth()     return self._strokewidth    end

function Handle:draw()
  common_btn_draw(self, self._state)
end

function Handle._drag_start_clbk() end
function Handle._drag_move_clbk()  end
function Handle._drag_stop_clbk()  end
function Handle:onDragStart(clbk) self._drag_start_clbk = clbk end
function Handle:onDragMove(clbk)  self._drag_move_clbk  = clbk end
function Handle:onDragStop(clbk)  self._drag_stop_clbk  = clbk end

function Handle:route(event)
  local caught_event = true

  if      event.type == 'MOUSEDOWN'         then
    self._state = 'press'
    self:GrabMouseFocus() -- get focus on mousedown
    self._drag_start_clbk(event)

  elseif  event.type == 'MOUSE_FOCUS_LOST'  then
    if self:testPxBox(NVec(event:mousePos())) then
      self._state = 'hover'
    else
      self._state = 'plain'
    end
    self._drag_stop_clbk(event)

  elseif  event.type == 'MOUSEUP'           then
    self:ReleaseMouseFocus()

  elseif  event.type == 'MOUSEMOVE' and
          self:hasMouseFocus()              then
    self._drag_move_clbk(event)

  -- hover in
  elseif  event.type == 'MOUSE_ENTER' and
          not self:hasMouseFocus()          then
    self._state = 'hover'

  -- hover out
  elseif  event.type == 'MOUSE_LEAVE' and
          not self:hasMouseFocus()          then
    self._state = 'plain'

  else
    caught_event = false
  end
  if caught_event then RawGUI.CaptureCurrentEvent() end
end





-- ------------------------------------------------------------------------- --
--                                  SLIDER                                   --
-- ------------------------------------------------------------------------- --



local Slider = RawGUI.SubClassWidget({}, 'Slider')
Exports.Slider = Slider

local slider_stroke_color = NColor(159,159,159,255)
local slider_back_color   = NColor(247,247,247,255)

function Slider.New(args)
  local slider = setmetatable({
    _strokewidth  = args.strokewidth or 1,
    _state        = 'plain',
    _alpha        = args.alpha or 255,
    _value        = 0.5,
  }, Slider)
  Widget._initialize(slider, args)

  if slider._pxbox.w < 22 or slider._pxbox.h < 30 then
    error('Sliders must be at least 22 px wide and 30 px tall')
  end

  if args.value     then slider:setValue(args.value)              end
  if args.dragstart then slider._drag_start_clbk = args.dragstart end
  if args.dragmove  then slider._drag_move_clbk  = args.dragstart end
  if args.dragstop  then slider._drag_stop_clbk  = args.dragstart end

  return slider
end

function Slider:setStrokeWidth(w)    self._strokewidth = w       end
function Slider:getStrokeWidth()     return self._strokewidth    end

local function slider_measurements(slider)
  local w       = slider._pxbox.w
  local h       = slider._pxbox.h
  local stroke  = slider._strokewidth
  local pad     = stroke * 2

  local sw      = w - 2*pad
  local sh      = 18

  -- track-height
  local th      = h - 2*pad - sh

  return w, h, stroke, pad, sw, sh, th
end

function Slider:draw()
  local w, h,         -- full widget widht and height
        stroke, pad,  -- stroke width and padding
        sw, sh,       -- shuttle width and height
        th =          -- track-height (how much the shuttle can move)
    slider_measurements(self)
  -- shuttle's pixel position
  local spx     = (1.0-self._value) * th

  local sbox    = P.NewBox {
    l = self._pxbox.l + pad,    t = self._pxbox.t + spx + pad,
    w = sw, h = sh }

  local win = RawGUI.GetMainWindow()
  win:cairoSave()
    win:setLineWidth(self._strokewidth)
    win:beginPath()
    win:rectangle( self._pxbox:expandBy(-0.5):unpack_ltwh() )
    win:setColor(slider_back_color:withAlpha(self._alpha):unpack())
    win:fillAndKeepPath()
    win:setColor(slider_stroke_color:withAlpha(self._alpha):unpack())
    win:stroke()

    local fillcolor   = btn_fill_color[self._state]:withAlpha(self._alpha)
    local strokecolor = btn_stroke_color[self._state]:withAlpha(self._alpha)
    win:beginPath()
    win:rectangle( sbox:expandBy(-0.5):unpack_ltwh() )
    win:setColor(fillcolor:unpack())
    win:fillAndKeepPath()
    win:setColor(strokecolor:unpack())
    win:stroke()
  win:cairoRestore()
end

function Slider:getValue()  return self._value                        end
function Slider:setValue(v) self._value = math.max(0, math.min(1, v)) end

function Slider._drag_start_clbk() end
function Slider._drag_move_clbk()  end
function Slider._drag_stop_clbk()  end
function Slider:onDragStart(clbk) self._drag_start_clbk = clbk end
function Slider:onDragMove(clbk)  self._drag_move_clbk  = clbk end
function Slider:onDragStop(clbk)  self._drag_stop_clbk  = clbk end

local function update_value(slider, py, first_call)
  local w, h,         -- full widget widht and height
        stroke, pad,  -- stroke width and padding
        sw, sh,       -- shuttle width and height
        th =          -- track-height (how much the shuttle can move)
    slider_measurements(slider)

  local track_y   = py - slider._pxbox.t - pad - sh/2.0

  local curr_val  = slider._value
  local req_val   = 1 - math.max(0, math.min(1, track_y / th))

  if first_call then
    slider._drag_start_clbk(req_val, curr_val)
  else
    slider._drag_move_clbk(req_val, curr_val)
  end
end

function Slider:route(event)
  local caught_event = true

  if      event.type == 'MOUSEDOWN'         then
    self._state = 'press'
    self:GrabMouseFocus() -- get focus on mousedown
    update_value(self, event.y, true)

  elseif  event.type == 'MOUSE_FOCUS_LOST'  then
    if self:testPxBox(NVec(event:mousePos())) then
      self._state = 'hover'
    else
      self._state = 'plain'
    end
    self._drag_stop_clbk(event)

  elseif  event.type == 'MOUSEUP'           then
    self:ReleaseMouseFocus()

  elseif  event.type == 'MOUSEMOVE' and
          self:hasMouseFocus()              then
    update_value(self, event.y, false)

  -- hover in
  elseif  event.type == 'MOUSE_ENTER' and
          not self:hasMouseFocus()          then
    self._state = 'hover'

  -- hover out
  elseif  event.type == 'MOUSE_LEAVE' and
          not self:hasMouseFocus()          then
    self._state = 'plain'

  else
    caught_event = false
  end
  if caught_event then RawGUI.CaptureCurrentEvent() end
end







-- ------------------------------------------------------------------------- --
--                                 TEXT BOX                                  --
-- ------------------------------------------------------------------------- --

local TextBox     = RawGUI.SubClassWidget({}, 'TextBox')
Exports.TextBox   = TextBox

function TextBox.New(args)
  local tb = setmetatable({
    _text             = '',
    _cursor_pos       = 1,
    _all_highlighted  = false, -- should I support this?

    _padding      = (args.padding or 0) + 1, -- + 1 for outline
  }, TextBox)
  RawGUI.Widget._initialize(tb, args)

  tb:setBackColor(args.backcolor or NColor(255,255,255,255))
  tb:setTextColor(args.textcolor or NColor(0,0,0,255))
  tb:setStrokeColor(args.strokecolor or NColor(0,0,0,255))
  tb:setFontSize(args.fontsize or 14)

  return tb
end
function TextBox:destroy()
  if self._font then
    RawGUI.ReleaseFont(self._font)
    self._font = nil
  end
  -- release this memory as quickly as possible
  self._text    = nil
end
function TextBox:setPxBox(box)
  RawGUI.Widget.setPxBox(self, box)
  self:_ResetMeasurements()
end

function TextBox:setBackColor(color)
  self._backcolor   = P.NewColor(color)
end
function TextBox:setTextColor(color)
  self._textcolor   = P.NewColor(color)
end
function TextBox:setStrokeColor(color)
  self._strokecolor = P.NewColor(color)
end
function TextBox:getBackColor()     return self._backcolor:clone()    end
function TextBox:getTextColor()     return self._textcolor:clone()    end
function TextBox:getStrokeColor()   return self._strokecolor:clone()  end

function TextBox:setFontSize(pts)
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
function TextBox:_ResetMeasurements()
  local w = self._pxbox.w - 2*self._padding
  -- measure
  self._n_chars_per_line  = math.floor(w/self._charwidth)
  self._n_lines_on_screen = 1
  -- now we reset the pixel box to enforce the one line rule
  local y = self._pxbox.t
  local h = self._lineheight + 2*self._padding
  self._pxbox = self._pxbox:setBounds { t=y, b=y+h }
end

function TextBox:getFontSize()      return self._fontsize           end
function TextBox:getCharsPerLine()  return self._n_chars_per_line   end
function TextBox:getWidthForNChars(nchars)
  return 2*self._padding + self._charwidth * nchars
end


function TextBox:_DrawCursor(win)
  local w = self._charwidth
  local h = self._lineheight
  local x = self._pxbox.l + self._padding +
            (self._cursor_pos-1) * w + 0.5
  local y = self._pxbox.t + self._padding

  win:beginPath()
  win:moveTo(x,y)
  win:lineTo(x,y+h)
  win:setLineWidth(1)
  win:stroke()
end
function TextBox:draw()
  local win = RawGUI.GetMainWindow()
  win:cairoSave()

  -- draw backdrop and frame
  win:rectangle(self._pxbox:expandBy(-0.5):unpack_ltwh())
  win:setColor(self._backcolor:unpack())
  win:fillAndKeepPath()
  win:setColor(self._strokecolor:unpack())
  win:setLineWidth(1)
  win:stroke()

  -- draw text if any
  win:setColor(self._textcolor:unpack())
  local x = self._pxbox.l + self._padding
  local y = self._pxbox.t + self._padding
  if #self._text > 0 then win:drawText(self._font, self._text, x, y) end
  if self:hasKeyFocus() then self:_DrawCursor(win) end

  win:cairoRestore()
end



function TextBox:setText(str)
  -- filter out bad stuff
  local len   = math.min(#str, self._n_chars_per_line)
  local nlpos = str:find('\n')
  if nlpos then len = math.min(len, nlpos-1) end
  str = str:sub(1,len)
  -- now actually set the text
  self._text = str
  self._cursor_pos = #self._text + 1
end
function TextBox:getText()
  return self._text
end

function TextBox:_SplitAtCursor()
  local before = self._text:sub(1,self._cursor_pos-1)
  local after  = self._text:sub(self._cursor_pos)
  return before, after
end
function TextBox:_WouldInsertOverflow(txt)
  local linelen = #self._text + #txt
  return linelen >= self._n_chars_per_line
end
function TextBox:_InsertText(txt)
  if txt:find('\n') then
    error('INTERNAL: Please Append, not Insert Newlines')
  end
  if self:_WouldInsertOverflow(txt) then
    error('TEXTBOX OVERFLOW')
  end

  local before, after   = self:_SplitAtCursor()
  self._text            = before .. txt .. after
  self._cursor_pos      = self._cursor_pos + #txt
end
function TextBox:_DeleteBack()
  local before, after   = self:_SplitAtCursor()
  self._text            = before:sub(1,-2) .. after
  self:_CursorBack()
end
function TextBox:_CursorBack()
  if self._cursor_pos > 1 then
    self._cursor_pos = self._cursor_pos - 1
  end
end
function TextBox:_CursorFwd()
  if self._cursor_pos <= #self._text then
    self._cursor_pos = self._cursor_pos + 1
  end
end

function TextBox:GrabKeyFocus()
  Widget.GrabKeyFocus(self)
  if not SDL.IsTextInputActive() then
    SDL.StartTextInput()
  end
end
function TextBox:ReleaseKeyFocus()
  SDL.StopTextInput()
  Widget.ReleaseKeyFocus(self)
end
function TextBox:route(event)
  local caught_event = true

  if      event.type == 'MOUSEDOWN'           then
    local has_focus = self:hasKeyFocus()
    self:GrabKeyFocus() -- if we don't have it
    -- need to handle multi-click for multi-select case here
    -- if event.clicks == 2 and has_focus then ... end
    if has_focus then
      -- just move the cursor
      local frac = (event.x - self._pxbox.l - self._padding) /
                    self._charwidth
      local idx  = math.ceil(frac+0.5)
      if idx > #self._text then idx = #self._text + 1 end
      self._cursor_pos = idx
    end

  elseif  event.type == 'TEXTINPUT' and self:hasKeyFocus() then
    if not self:_WouldInsertOverflow(event.text) then
      self:_InsertText(event.text)
    end

  elseif  event.type == 'KEYDOWN' and self:hasKeyFocus() then
    if      event.key == 'Return' then
      self._return_clbk(self._text)

    elseif  event.key == 'Left' then
      self:_CursorBack()
    elseif  event.key == 'Right' then
      self:_CursorFwd()
    elseif  event.key == 'Backspace' then
      self:_DeleteBack()
    else caught_event = false end

  else caught_event = false end
  if caught_event then RawGUI.CaptureCurrentEvent() end
end

-- overwrite this function to respond to return being pushed
function TextBox._return_clbk(text) end
function TextBox:onReturnPress(clbk) self._return_clbk = clbk end






-- ------------------------------------------------------------------------- --
--                              SELECT SCROLLER                              --
-- ------------------------------------------------------------------------- --

local SelectScroller    = RawGUI.SubClassWidget({}, 'SelectScroller')
Exports.SelectScroller  = SelectScroller

function SelectScroller.New(args)
  local ss = setmetatable({
    _options        = {},
    _curr_select    = nil,
    _scroll_offset  = NVec(0,0),

    _padding        = (args.padding or 0) + 1, -- + 1 for outline
  }, SelectScroller)
  RawGUI.Widget._initialize(ss, args)

  ss:setBackColor(args.backcolor or NColor(255,255,255,255))
  ss:setHighlightColor(args.highlightcolor or NColor(191,191,191,255))
  ss:setTextColor(args.textcolor or NColor(0,0,0,255))
  ss:setStrokeColor(args.strokecolor or NColor(0,0,0,255))
  ss:setFontSize(args.fontsize or 14)
  if args.options then ss:setOptions(args.options) end

  return ss
end
function SelectScroller:destroy()
  if self._font then
    RawGUI.ReleaseFont(self._font)
    self._font = nil
  end
  -- release this memory as quickly as possible
  self._options  = nil
end
function SelectScroller:setPxBox(box)
  RawGUI.Widget.setPxBox(self, box)
  self:_ResetMeasurements()
end

function SelectScroller:setBackColor(color)
  self._backcolor       = P.NewColor(color)
end
function SelectScroller:setHighlightColor(color)
  self._highlightcolor  = P.NewColor(color)
end
function SelectScroller:setTextColor(color)
  self._textcolor       = P.NewColor(color)
end
function SelectScroller:setStrokeColor(color)
  self._strokecolor     = P.NewColor(color)
end
function SelectScroller:getBackColor()
  return self._backcolor:clone()        end
function SelectScroller:getHightlightColor()
  return self._highlightcolor:clone()   end
function SelectScroller:getTextColor()
  return self._textcolor:clone()        end
function SelectScroller:getStrokeColor()
  return self._strokecolor:clone()      end

function SelectScroller:setFontSize(pts)
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
function SelectScroller:_ResetMeasurements()
  local w = self._pxbox.w - 2*self._padding
  -- measure
  self._n_chars_per_line  = math.floor(w/self._charwidth)
end

function SelectScroller:getFontSize()     return self._fontsize         end
function SelectScroller:getCharsPerLine() return self._n_chars_per_line end
function SelectScroller:getWidthForNChars(nchars)
  return 2*self._padding + self._charwidth * nchars
end


function SelectScroller:draw()
  local win = RawGUI.GetMainWindow()
  win:cairoSave()

  -- clip mask
  win:rectangle(self._pxbox:expandBy(0):unpack_ltwh())
  win:clip()
  -- draw backdrop
  win:rectangle(self._pxbox:expandBy(-0.5):unpack_ltwh())
  win:setColor(self._backcolor:unpack())
  win:fill()

  if self._curr_select then
    local x = self._pxbox.l + self._padding
            - self._scroll_offset.x
    local y = self._pxbox.t + self._padding
            + (self._curr_select-1)*self._lineheight
            - self._scroll_offset.y
    local w = math.max(self._opt_w, self._pxbox.w - 2*self._padding)
    local h = self._lineheight
    win:setColor(self._highlightcolor:unpack())
    win:rectangle(x,y,w,h)
    win:fill()
  end

  -- draw text if any
  win:setColor(self._textcolor:unpack())
  local x = self._pxbox.l + self._padding - self._scroll_offset.x
  local y = self._pxbox.t + self._padding - self._scroll_offset.y
  for i,line in ipairs(self._options) do
    if #line > 0 then win:drawText(self._font, line, x, y) end
    y = y + self._lineheight
  end
  --if #self._text > 0 then win:drawText(self._font, self._text, x, y) end
  --if self:hasKeyFocus() then self:_DrawCursor(win) end

  -- draw frame
  win:rectangle(self._pxbox:expandBy(-0.5):unpack_ltwh())
  win:setColor(self._strokecolor:unpack())
  win:setLineWidth(1)
  win:stroke()

  win:cairoRestore()
end


function SelectScroller:setOptions(opt_list)
  -- do error checking
  if type(opt_list) ~= 'table' then error("expecting list of options", 2) end
  self._options = {}
  for i=1,#opt_list do
    if type(opt_list[i]) ~= 'string' then
      error('expecting option list to contain strings', 2) end
    self._options[i] = opt_list[i]
  end
  -- take measurements of where we can scroll safely
  local maxline = 0
  for _,line in ipairs(self._options) do
    maxline = math.max(maxline, #line)
  end
  self._opt_w = self._charwidth * maxline
  self._opt_h = self._lineheight * #self._options
  -- reset some data
  self._curr_select = nil
  self._scroll_offset = NVec(0,0)
end
function SelectScroller:setSelection(idx)
  if not idx then
    local is_changing = idx ~= self._curr_select
    self._curr_select = nil
    if is_changing then self._select_clbk(nil) end

  else
    if idx < 1 or idx > #self._options then
      error('cannot set selection to out of range index for options', 2)
    end

    local is_changing = idx ~= self._curr_select
    self._curr_select = idx
    self:_ScrollToFitSelection()
    if is_changing then self._select_clbk(self:getSelectText()) end

  end
end
function SelectScroller:getNumOptions()
  return #self._options
end
function SelectScroller:getSelectText()
  return self._curr_select and self._options[self._curr_select]
end

function SelectScroller:_ScrollWindow(dxy)
  -- non-linear scaling
  local cp = dxy:clone()
  dxy.x = math.floor(dxy.x * math.pow(1.2, math.abs(dxy.x)))
  dxy.y = math.floor(dxy.y * math.pow(1.2, math.abs(dxy.y)))
  -- bounds
  local w = self._pxbox.w - 2*self._padding
  local h = self._pxbox.h - 2*self._padding
  local lowbd      = NVec(0,0)
  local hibd       = NVec(self._opt_w-w, self._opt_h-h)
  -- note, it's critical that we apply hibd before lowbd
  -- b/c we did not check that hibd is non-negative
  local newxy = self._scroll_offset + dxy
  self._scroll_offset = newxy:min(hibd):max(lowbd)
end
function SelectScroller:_ScrollToFitSelection()
  -- compute selection bounds
  local miny = (self._curr_select-1) * self._lineheight
  local maxy = miny + self._lineheight
  local dy = 0
  local h = self._pxbox.h - 2*self._padding
  if miny < self._scroll_offset.y then
    dy = miny - self._scroll_offset.y end
  if maxy > self._scroll_offset.y + h then
    dy = maxy - h - self._scroll_offset.y end
  self._scroll_offset.y = self._scroll_offset.y + dy
end
function SelectScroller:_ClickToItem(xy)
  local y   = xy.y - self._pxbox.t -self._padding + self._scroll_offset.y
  local idx = math.floor(y/self._lineheight) + 1
  if idx < 1 or idx > #self._options then idx = nil end
  return idx
end

function SelectScroller:route(event)
  local caught_event = true

  if      event.type == 'MOUSEWHEEL'          then
    self:_ScrollWindow(NVec(event.x, -event.y))

  elseif  event.type == 'KEY_FOCUS_LOST'      then
    self._curr_select = nil

  elseif  event.type == 'MOUSEDOWN'           then
    self:GrabKeyFocus() -- so we get any useful key events first

    self:setSelection(self:_ClickToItem(NVec(event.x,event.y)))
    if event.clicks == 2 then
      self._confirm_clbk(self:getSelectText())
    end

  elseif  event.type == 'KEYDOWN' and self:hasKeyFocus() then
    if      event.key == 'Return' then
      if self._curr_select then self._confirm_clbk(self:getSelectText()) end

    elseif  event.key == 'Up' then
      if self._curr_select and #self._options > 0 then
        local idx = math.max(self._curr_select - 1, 1)
        self:setSelection(idx)
      else
        self:setSelection(1)
      end
    elseif  event.key == 'Down' then
      if self._curr_select and #self._options > 0 then
        local idx = math.min(self._curr_select + 1, #self._options)
        self:setSelection(idx)
      else
        self:setSelection(1)
      end
    else caught_event = false end

  else caught_event = false end
  if caught_event then RawGUI.CaptureCurrentEvent() end
end

function SelectScroller._select_clbk(text) end
function SelectScroller._confirm_clbk(text) end
function SelectScroller:onSelectionChange(clbk) self._select_clbk = clbk end
function SelectScroller:onSelectionConfirm(clbk) self._confirm_clbk = clbk end










-- ------------------------------------------------------------------------- --
--                            FILE CHOOSER DIALOG                            --
-- ------------------------------------------------------------------------- --

--[[
local FileChooser = RawGUI.SubClassWidget({}, 'FileChooser')
Exports.FileChooser = FileChooser

function SignalMonitor.New(args)
  local fc = setmetatable({
    _params       = {
      tickpow       = 10, -- scale at which to display ticks
      tickminfreq   = 8, -- minimum pixels between ticks
      ticklen       = 2, -- px length of ticks
      sampfreq      = 2, -- px between samples horizontally
    },
    --_exec_clbk    = function() end,
    _padding      = args.padding or 0,
  }, FileChooser)
  Widget._initialize(fc, args)

  fc:setLineColor(args.linecolor or NColor(0,0,0,255))
  fc:setTextColor(args.textcolor or NColor(0,0,0,255))
  fc:setBackColor(args.backcolor)

  fc:setFontSize(args.fontsize or 14)
  return fc
end







function SignalMonitor:draw()

end

function Slider:route(event)

end

--]]








