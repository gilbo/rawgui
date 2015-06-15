--
--  rawgui.t
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

local RawGUI = {}
package.loaded['rawgui'] = RawGUI

---------------------------------------------

local SDL = require 'SDL'
local C   = terralib.includecstring [[
  #include "stdlib.h"
]]

-- Debug mode?
--local use_debug = not not _RAW_GUI_DEBUG

local P = require 'primitives'
local Vec = P.Vec
local Box = P.Box
local Color = P.Color

---------------------------------------------
-- Set up a simpler notion of a widget...
---------------------------------------------

local Widget = {}
Widget.__index = Widget


function Widget:_initialize(args)
  args = args or {}
  -- check args
  if not args.pxbox then
    error('when initializing a widget, you must provide a pxbox argument', 2)
  end

  Widget.setPxBox(self, args.pxbox)
end

function Widget:setPxBox(box)
  self._pxbox = P.NewBox(box)
  if self._pxbox.h < 1 or self._pxbox.w < 1 then
    error('pixel box must be at least 1 pixel wide & tall', 2)
  end
end
function Widget:getPxBox()
  return self._pxbox:clone()
end

function Widget:testPxBox(pt)
  return self._pxbox:containsPoint(pt,0)
end

function Widget:draw()
  error('INTERNAL: draw() unimplemented for '..tostring(self.__name))
end
function Widget:route(ev)
  error('INTERNAL: route() unimplemented for '..tostring(self.__name))
end


RawGUI.Widget = Widget
function RawGUI.SubClassWidget(obj, name, parent)
  if type(name) ~= 'string' then
    error('must provide a Widget name as second argument', 2)
  end
  parent = parent or Widget
  setmetatable(obj, parent)
  obj.__index = obj
  obj.__name = name
  return obj
end


-- Layers

local Layer = {}
Layer.__index = Layer

function Layer.New()
  return setmetatable({
    _widgets = {}
  }, Layer)
end
RawGUI.NewLayer = Layer.New

local function isLayer(obj) return getmetatable(obj) == Layer end
RawGUI.isLayer = isLayer

function Layer:AddWidgetAtFront(widget)
  table.insert(self._widgets, widget)
end
function Layer:AddWidgetAtBack(widget)
  table.insert(self._widgets, 1, widget)
end
function Layer:RemoveWidget(widget)
  local N = #self._widgets
  local idx = 1
  while idx <= N and self._widgets[idx] ~= widget do idx = idx + 1 end
  if idx <= N then table.remove(self._widgets, idx) end
end









---------------------------------------------
-- Major State Items of the GUI
---------------------------------------------


local MAIN_WINDOW       = nil
local IS_MOUSE_CAPTURED = false
local WIDGETS           = {}
local ON_QUIT_CLBKS     = {}
--local MID_LOOP_CLBKS    = {}
local EVENT_DISPATCH    = {}
local SETUP_CALLBACKS   = {}
local CLEAR_COLOR       = P.NewColorUnsafe(255,255,255,255)

function RawGUI.GetMainWindow()
  return MAIN_WINDOW
end

local function iterVals(tbl)
  local k,v
  return function()
    k,v = next(tbl,k)
    if k then return v else return nil end
  end
end
local function flatten_widgets(input, output, do_rev)
  local N = #input
  for iter=1,N do
    local k = do_rev and N-iter+1 or iter
    local v = input[k]
    if isLayer(v) then flatten_widgets(v._widgets, output, do_rev)
                  else table.insert(output, v) end
  end
end
local function WidgetsFrontToBack()
  local rev = {}
  flatten_widgets(WIDGETS, rev, true)
  return iterVals(rev)
end
local function WidgetsBackToFront()
  local fwd = {}
  flatten_widgets(WIDGETS, fwd, false)
  return iterVals(fwd)
end
function RawGUI.AddWidgetAtFront(widget)
  table.insert(WIDGETS, widget)
end
function RawGUI.AddWidgetAtBack(widget)
  table.insert(WIDGETS, 1, widget)
end
function RawGUI.RemoveWidget(widget)
  local N = #WIDGETS
  -- scan to find the widget
  local read = 1
  while read <= N and WIDGETS[read] ~= widget do read = read + 1 end
  if read <= N then
    table.remove(WIDGETS, read)
  end
end

function RawGUI.onQuit(clbk)
  if type(clbk) ~= 'function' then error('expecting function', 2) end
  table.insert(ON_QUIT_CLBKS, clbk)
end
--function RawGUI.onMidLoop(clbk)
--  if type(clbk) ~= 'function' then error('expecting function', 2) end
--  table.insert(MID_LOOP_CLBKS, clbk)
--end
function RawGUI.onSetup(clbk)
  if type(clbk) ~= 'function' then error('expecting function', 2) end
  table.insert(SETUP_CALLBACKS, clbk)
end





---------------------------------------------
-- Routing
---------------------------------------------


-- WIDGET & GUI EVENT ROUTING POLICY
--  The Policy is governed by 3 major pieces of state
--    Hover:        list of widgets the cursor is currently over
--    Key-Focus:    one or zero widgets to which key events/text input must go
--    Mouse-Focus:  one or zero widgets to which mouse events must go
--  The first major issue is to specify how this state changes
--    * 'Hover' is always literally what the cursor is over. Period.
--    * 'Key-Focus' and 'Mouse-Focus' can both be requested by any widget,
--        at any time, for any reason.
--    * If a Focus is requested, then whatever had the focus will lose it
--    * A widget can choose to release focus
--    * 'Key-Focus' is also lost if the entire window loses 'Key-Focus'
--    * 'Mouse-Focus' is NOT lost on leaving the window, mouse-up or any event
--  The next major issue is how events get routed based on state/changes
--    The following events are potentially routed to widgets:
--      MOUSE_ENTER, MOUSE_LEAVE,
--      MOUSEDOWN, MOUSEUP, MOUSEMOVE, MOUSEWHEEL
--      MOUSE_FOCUS_LOST  (this event is invented by the router)
--      KEY_FOCUS_LOST
--      KEYDOWN, KEYUP, TEXTINPUT
--    We can separate the events into XXXX overlapping groups:
--      hover-change:       MOUSE_ENTER, MOUSE_LEAVE
--      keyfocus-change:    KEY_FOCUS_LOST
--      mousefocus-change:  MOUSE_FOCUS_LOST
--      hover-route:        MOUSEDOWN, MOUSEUP, MOUSEMOVE, MOUSEWHEEL,
--                          KEYDOWN, KEYUP
--      keyfocus-route:     KEYDOWN, KEYUP, TEXTINPUT
--      mousefocus-route:   MOUSEDOWN, MOUSEUP, MOUSEMOVE, MOUSEWHEEL,
--                          KEYDOWN, KEYUP
--    Then the policy is simple.  While a widget is hovered or focused,
--      route the *-route events to it, and route the change events
--      whenever a change happens.  In the case of an explicit
--      request to de-focus a widget, the event will fire immediately
--  One slight other issue is that we allow widgets to CAPTURE events
--    which stops their propagation.  This means we need a clear order
--    in which events will be propagated through the UI
--  Event Issue Order:
--    1. The key-focused widget
--    2. The mouse-focused widget
--    3. The hover stack in front-to-back order
--    4. The global GUI handler for the event

local HOVER_STACK   = {}
local KEY_FOCUSED   = nil
local MOUSE_FOCUSED = nil

local HALT_EVENT_ROUTING = false
local function stop_routing_event() HALT_EVENT_ROUTING = true end

-- stops event propagation
function RawGUI.CaptureCurrentEvent()
  HALT_EVENT_ROUTING = true
end

-- seize or relinquish focus
function Widget:GrabKeyFocus()
  if not self:hasKeyFocus() then
    if KEY_FOCUSED then KEY_FOCUSED:ReleaseKeyFocus() end
    KEY_FOCUSED = self
  end
end
function Widget:GrabMouseFocus()
  if not self:hasMouseFocus() then
    if MOUSE_FOCUSED then MOUSE_FOCUSED:ReleaseMouseFocus() end
    MOUSE_FOCUSED = self
  end
end
function Widget:hasKeyFocus()
  return self == KEY_FOCUSED
end
function Widget:hasMouseFocus()
  return self == MOUSE_FOCUSED
end
function Widget:ReleaseKeyFocus()
  if self:hasKeyFocus() then
    self:route( SDL.NewEvent { type = 'KEY_FOCUS_LOST' } )
    KEY_FOCUSED = nil
  end
end
function Widget:ReleaseMouseFocus()
  if self:hasMouseFocus() then
    self:route( SDL.NewEvent { type = 'MOUSE_FOCUS_LOST' } )
    MOUSE_FOCUSED = nil
  end
end
function RawGUI.ReleaseKeyFocus()
  if KEY_FOCUSED then KEY_FOCUSED:ReleaseKeyFocus() end
end
function RawGUI.ReleaseMouseFocus()
  if MOUSE_FOCUSED then MOUSE_FOCUSED:ReleaseMouseFocus() end
end


local function HoverFrontToBack()
  --local i = #HOVER_STACK + 1
  --return function()
  --  i = i - 1
  --  return HOVER_STACK[i]
  --end
  return iterVals(HOVER_STACK)
end

-- main routing logic
local function route_event(event)
  HALT_EVENT_ROUTING = false -- reset for each event

  -- First, we're going to handle every event that is possibly involved
  -- in widget routing
  if      event.type == 'MOUSEMOVE' then
    local cursor_pos = P.NewVecUnsafe(event.x, event.y)

    -- 1. keyfocus dispatch (don't dispatch)
    -- 2. mousefocus dispatch
    if MOUSE_FOCUSED  then MOUSE_FOCUSED:route(event) end

    -- 3. hover stack dispatch, and hover stack update
    local new_hover  = {}
    local hover_read = 1
    for w in WidgetsFrontToBack() do
      -- Are we over this widget?  Were we just over this widget?
      local curr_over = w:testPxBox(cursor_pos)
      local prev_over = HOVER_STACK[hover_read] == w
      -- adjust appropriately
      if curr_over then table.insert(new_hover, w)  end
      if prev_over then hover_read = hover_read + 1 end

      -- 3 cases:
      -- starts and remains over widget
      if      curr_over and prev_over then
        if w ~= MOUSE_FOCUSED and not HALT_EVENT_ROUTING then
          w:route(event)
        end
      -- entering widget
      elseif  curr_over and not prev_over then
        -- need to send a MOUSE_ENTER
        w:route( event:derive('MOUSE_ENTER') )
        if w ~= MOUSE_FOCUSED and not HALT_EVENT_ROUTING then
          w:route(event)
        end
      -- exiting widget
      elseif  not curr_over and prev_over then
        --if w ~= MOUSE_FOCUSED and not HALT_EVENT_ROUTING then
        --  w:route(event)
        --end
        -- need to send a MOUSE_LEAVE
        w:route( event:derive('MOUSE_LEAVE') )
      end
    end
    HOVER_STACK = new_hover
    if HALT_EVENT_ROUTING then return end -- exit if appropriate...

  -- actually we can just rely on mouse move events to generate
  -- per-widget mouse-enter events
  --elseif  event.type == 'MOUSE_ENTER' then
  elseif  event.type == 'MOUSE_LEAVE' then
    -- clear the hover stack
    for _,w in ipairs(HOVER_STACK) do
      w:route(event)
    end
    HOVER_STACK = {} -- cleared

  -- actually, we'll just rely on the user saying when a widget gains focus
  --elseif  event.type == 'KEY_FOCUS_GAINED' then
  elseif  event.type == 'KEY_FOCUS_LOST' then
    -- clear any key-focused widget
    if KEY_FOCUSED then
      KEY_FOCUSED:route(event)
      KEY_FOCUSED = nil
    end

  elseif  event.type == 'MOUSEDOWN'
      or  event.type == 'MOUSEUP'
      or  event.type == 'MOUSEWHEEL'
  then
    -- 1. keyfocus dispatch (don't dispatch)
    -- 2. mousefocus dispatch
    if MOUSE_FOCUSED  then MOUSE_FOCUSED:route(event) end
    if HALT_EVENT_ROUTING then return end

    -- 3. hover stack dispatch
    for w in HoverFrontToBack() do
      if w ~= MOUSE_FOCUSED then w:route(event) end
      if HALT_EVENT_ROUTING then return end
    end

  elseif  event.type == 'KEYDOWN' or event.type == 'KEYUP' then
    -- 1. keyfocus dispatch (don't dispatch)
    if KEY_FOCUSED  then KEY_FOCUSED:route(event) end
    if HALT_EVENT_ROUTING then return end
    -- 2. mousefocus dispatch
    if MOUSE_FOCUSED and MOUSE_FOCUSED ~= KEY_FOCUSED then
      MOUSE_FOCUSED:route(event)
    end
    if HALT_EVENT_ROUTING then return end

    -- 3. hover stack dispatch
    for w in HoverFrontToBack() do
      if w ~= MOUSE_FOCUSED and w ~= KEY_FOCUSED then w:route(event) end
      if HALT_EVENT_ROUTING then return end
    end

  elseif  event.type == 'TEXTINPUT' then
    if KEY_FOCUSED then KEY_FOCUSED:route(event) end
    if HALT_EVENT_ROUTING then return end
  end

  -- 4. route to the global handlers
  local handlers = EVENT_DISPATCH[event.type]
  if handlers then
    local cp = {}
    for i,h in ipairs(handlers) do cp[i] = h end
    for _,h in ipairs(cp)       do
      h(event)
      if HALT_EVENT_ROUTING then return end
    end
  end
end

function RawGUI.onEvent(event_name, clbk)
  if type(clbk) ~= 'function' then error('expecting callback function', 2) end
  local e_clbks = EVENT_DISPATCH[event_name]
  if e_clbks then
    table.insert(e_clbks, clbk)
  else
    EVENT_DISPATCH[event_name] = {clbk}
  end
end








---------------------------------------------
-- GUI Main Loop
---------------------------------------------



function RawGUI.setClearColor(color)
  CLEAR_COLOR = P.NewColor(color)
end

local function do_drawing()
  MAIN_WINDOW:cairoBegin()

    -- clear
    MAIN_WINDOW:setColor(CLEAR_COLOR:unpack())
    MAIN_WINDOW:clear()

    --local bounds = MAIN_WINDOW:getBounds()
    --print(bounds._2, bounds._3) -- w and h respectively

    -- dispatch drawing in back to front order
    for w in WidgetsBackToFront() do
      w:draw()
    end

  MAIN_WINDOW:cairoEnd()
end


local function quit_gui()
  for i=1,#ON_QUIT_CLBKS do
    local clbk = ON_QUIT_CLBKS[#ON_QUIT_CLBKS - i + 1]
    clbk()
  end
  if MAIN_WINDOW then
    MAIN_WINDOW:destroy()
    MAIN_WINDOW = nil
  end
  C.exit(0)
end

local timing_stats = {
  sum_event_time  = 0,
  sum_draw_time   = 0,
  sum_wait_time   = 0,
  n_waits     = 0,
  n_draws     = 0,
  n_events    = 0,
  last_draw_time  = nil,
  last_wait_time  = nil,
  last_event_time = nil,
}
function RawGUI.GetAverageEventTime()
  return timing_stats.sum_event_time / timing_stats.n_events
end
function RawGUI.GetAverageDrawTime()
  return timing_stats.sum_draw_time / timing_stats.n_draws
end
function RawGUI.GetAverageWaitTime()
  return timing_stats.sum_wait_time / timing_stats.n_waits
end
function RawGUI.GetEventCount()
  return timing_stats.n_events
end
function RawGUI.GetDrawCount()
  return timing_stats.n_draws
end
function RawGUI.GetWaitCount()
  return timing_stats.n_waits
end
function RawGUI.GetLastEventTime()
  return timing_stats.last_event_time
end
function RawGUI.GetLastDrawTime()
  return timing_stats.last_draw_time
end
function RawGUI.GetLastWaitTime()
  return timing_stats.last_wait_time
end

local function main_loop(opts)
  opts = opts or {}
  -- SETUP
  SDL.Init()

  local winargs = opts.winargs or {}
  MAIN_WINDOW = SDL.NewWindow(winargs)

  for _,clbk in ipairs(SETUP_CALLBACKS) do clbk() end

  -- LOOP
  while true do
    -- STATS
    local wait_start = terralib.currenttimeinseconds()

    -- EVENT DISPATCH
    for e in SDL.WaitForEvents() do if e then
      -- STATS
      local e_starttime = terralib.currenttimeinseconds()
      if wait_start then
        local wait_time = e_starttime - wait_start
        timing_stats.n_waits = timing_stats.n_waits + 1
        timing_stats.sum_wait_time = timing_stats.sum_wait_time + wait_time
        timing_stats.last_wait_time = wait_time
        wait_start = nil
      end

      --print('------', e.type, e.x, e.y)
      if e.type == 'QUIT' then
        RawGUI.Quit()
      else
        route_event(e)
      end

      -- STATS
      local e_time = terralib.currenttimeinseconds() - e_starttime
      timing_stats.n_events = timing_stats.n_events + 1
      timing_stats.sum_event_time = timing_stats.sum_event_time + e_time
      timing_stats.last_event_time = e_time
    end end

    -- STATS
    if wait_start then
      local wait_time = terralib.currenttimeinseconds() - wait_start
      timing_stats.n_waits = timing_stats.n_waits + 1
      timing_stats.sum_wait_time = timing_stats.sum_wait_time + wait_time
      timing_stats.last_wait_time = wait_time
      wait_start = nil
    end
    local draw_starttime = terralib.currenttimeinseconds()


    -- MIDLOOP COMPUTATION
    --for _,clbk in ipairs(MID_LOOP_CLBKS) do clbk() end

    -- DRAWING
    do_drawing()

    -- STATS
    local drawtime  = terralib.currenttimeinseconds() - draw_starttime
    timing_stats.n_draws = timing_stats.n_draws + 1
    timing_stats.sum_draw_time = timing_stats.sum_draw_time + drawtime
    timing_stats.last_draw_time = drawtime
  end
end

RawGUI.Quit       = quit_gui
RawGUI.StartLoop  = main_loop




--[[
function event_dispatch_table.QUIT(e)
  RawGUI.Quit()
end
function event_dispatch_table.WINDOW_SHOWN(e)
end
function event_dispatch_table.WINDOW_HIDDEN(e)
end
function event_dispatch_table.MOVE_WINDOW(e)
end
function event_dispatch_table.RESIZE_WINDOW(e)
end
function event_dispatch_table.MOUSE_ENTER(e)
end
function event_dispatch_table.MOUSE_LEAVE(e)
end
function event_dispatch_table.KEY_FOCUS_GAINED(e)
end
function event_dispatch_table.KEY_FOCUS_LOST(e)
end
function event_dispatch_table.WINDOW_CLOSE(e)
end
function event_dispatch_table.WINDOW_MINIMIZED(e)
end
function event_dispatch_table.WINDOW_MAXIMIZED(e)
end
  -- all have timestamp and window_id; nothing else

function event_dispatch_table.KEYDOWN(e)

end
function event_dispatch_table.KEYUP(e)

end
  -- timestamp and window_id
  -- 'key' holds a string of which key; 'scancode' is lower level name
  -- n_repeats has the number of times this event has sequentially repeated

function event_dispatch_table.MOUSEMOVE()

end
  -- timestamp and window_id
  -- x,y,dx,dy

function event_dispatch_table.MOUSEDOWN(e)

end
function event_dispatch_table.MOUSEUP(e)

end
  -- timestamp and window_id
  -- button is from ['left','middle','right','x1','x2']
  -- x,y position
  -- clicks gives a measurement of whether this is a double/triple/... click

function event_dispatch_table.MOUSEWHEEL(e)

end
  -- timestamp and window_id
  -- x,y are measurements of wheel movement

function event_dispatch_table.DROPFILE(e)

end
  -- timestamp (no window_id ???)
  -- filename string

function event_dispatch_table.TIMEOUT(e)

end
  -- timestamp and window_id
  -- is returned after any registered callbacks have executed
]]




---------------------------------------------------------------------------
--    Font Caching System
---------------------------------------------------------------------------

-- right now, never evict from the cache
-- also manage the cache hierarchically
local font_cache = {}
function RawGUI.CheckoutFont(spec)
  if not spec.file or not spec.pts then
    error('must supply "file" and "pts"', 2) end

  local stylestr  = tostring(spec.pts)
  if spec.italic        then stylestr = stylestr..'i' end
  if spec.bold          then stylestr = stylestr..'b' end
  if spec.underline     then stylestr = stylestr..'u' end
  if spec.strikethrough then stylestr = stylestr..'s' end
  stylestr        = stylestr..tostring(spec.outline)

  -- try looking up an existing font
  local lookup  = nil
  local flookup = font_cache[spec.file]
  if flookup then lookup = flookup[stylestr] end
  -- early exit
  if lookup then return lookup end

  -- Otherwise, we need to populate the cache
  -- create sub-cache-table if needed
  if not flookup then
    flookup = {}
    font_cache[spec.file] = flookup
  end
  -- construct the font object
  lookup = SDL.OpenFont(spec.file, spec.pts)
  if spec.italic        then lookup:setItalic(true)         end
  if spec.bold          then lookup:setBold(true)           end
  if spec.underline     then lookup:setUnderline(true)      end
  if spec.strikethrough then lookup:setStrikethrough(true)  end
  if spec.outline and spec.outline > 0 then
    lookup:setOutline(spec.outline)
  end
  -- write to cache
  flookup[stylestr] = lookup

  return lookup
end

function RawGUI.ReleaseFont(font)
  -- Stub for future use
end










