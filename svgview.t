--
--  svgview.t
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

local SVGView = {}
package.loaded['svgview'] = SVGView

---------------------------------------------

local RawGUI    = require 'rawgui'
local P         = require 'primitives'
local Viewport  = require 'viewport'
local SVG       = require 'svg'
local Vec       = P.Vec
local NVec      = P.NewVecUnsafe
local NewBox    = P.NewBox

-- ========================================================================= --

local Arc       = {}
Arc.__index     = Arc

local Bz        = {}
Bz.__index      = Bz

local Path      = {}
Path.__index    = Path

local function NewArc(p0,p1,p2)
  local a = setmetatable({
    p0 = p0,
    p1 = p1,
    p2 = p2,
  }, Arc)
  return a
end
function Arc:a0() return self.p0 end
function Arc:a1() return self.p2 end
function Arc:toBz()
  local b     = self.p2 - self.p0 -- b for base of triangle
  local e0    = self.p0 - self.p1
  local e2    = self.p2 - self.p1
  local denom = e0:len() + e2:len()
  if denom < 1e-6 then denom = 1e-6 end
  local w1    = b:len() / denom
  local beta  = (4.0/3.0) * w1 / (1+w1)

  local bp1   = (1-beta) * self.p0 + beta * self.p1
  local bp2   = (1-beta) * self.p2 + beta * self.p1
  return NewBz(self.p0, bp1, bp2, self.p2)
end

local function NewBz(p0,p1,p2,p3)
  local bz = setmetatable({
    p0 = p0,
    p1 = p1,
    p2 = p2,
    p3 = p3,
  }, Bz)
  return bz
end
local function NewBzLine(p0,p1)
  return NewBz(p0,p0,p1,p1)
end
function Bz:a0() return self.p0 end
function Bz:a1() return self.p3 end
function Bz:toBz()
  return self
end

local function NewPath(segs)
  local pstart  = segs[1]:a0()
  local pend    = segs[#segs]:a1()
  local path = setmetatable({
    _segs     = segs,
    _closed   = pstart == pend,
  }, Path)
  return path
end
function Path:isClosed() return self._closed end

-- ========================================================================= --

local function extract_path( results, svgnode, EPSILON )
  local currpt
  local segs = {}
  local cmds = svgnode.data

  local function flush_subpath()
    if #segs > 0 then
      table.insert(results, NewPath(segs))
    end
    segs = {}
  end

  for _,instr in ipairs(cmds) do
    local cmd, args = instr.cmd, instr.args

    if      cmd == 'm' or cmd == 'M' then
      -- flush any non-trivial path
      flush_subpath()
      -- set the current point and segment list state
      if cmd == 'm' then currpt = currpt + NVec(args[1], args[2])
                    else currpt = NVec(args[1], args[2]) end

    elseif  cmd == 'z' or cmd == 'Z' then
      -- if we can close this sub-path, then do so.
      -- Note this frequently introduces length zero edges
      local initpt  = #segs > 0 and segs[1]:a0()
      if initpt then
        table.insert(segs, NewBzLine(currpt, initpt))
        currpt = initpt
      end
      -- flush any valid sub-path we may have
      flush_subpath()

    elseif  cmd == 'l' or cmd == 'h' or cmd == 'v' or
            cmd == 'L' or cmd == 'H' or cmd == 'V' then
      local nextpt
      if      cmd == 'l' then nextpt = currpt + NVec(args[1], args[2])
      elseif  cmd == 'h' then nextpt = currpt + NVec(args[1], 0)
      elseif  cmd == 'v' then nextpt = currpt + NVec(0, args[1])
      elseif  cmd == 'L' then nextpt = NVec(args[1], args[2])
      elseif  cmd == 'H' then nextpt = NVec(args[1], currpt.y)
      elseif  cmd == 'V' then nextpt = NVec(currpt.x, args[1])
      end
      table.insert(segs, NewBzLine(currpt, nextpt))
      currpt = nextpt

    elseif  cmd == 'c' or cmd == 'C' then
      local p1, p2, p3 = NVec(args[1], args[2]),
                         NVec(args[3], args[4]),
                         NVec(args[5], args[6])
      if cmd == 'c' then
        p1 = p1 + currpt
        p2 = p2 + currpt
        p3 = p3 + currpt
      end
      table.insert(segs, NewBz(currpt, p1, p2, p3))
      currpt = p3

    elseif  cmd == 's' or cmd == 'S' then
      local p1      = currpt   -- default
      local prevseg = segs[#segs]
      if prevseg then p1 = currpt + (prevseg.p3 - prevseg.p2) end
      local p2, p3 = NVec(args[1], args[2]), NVec(args[3], args[4])
      if cmd == 's' then
        p2 = p2 + currpt
        p3 = p3 + currpt
      end
      table.insert(segs, NewBz(currpt, p1, p2, p3))
      currpt = p3

    elseif  cmd == 'q' or cmd == 'Q' or cmd == 't' or cmd == 'T' then
      error('INTERNAL: q/Q/t/T quadratic Bezier Path commands '..
            'are not implemented.')
    elseif  cmd == 'a' or cmd == 'A' then
      error('INTERNAL: a/A arc drawing Path commands are not implemented.')
    else
      error("INTERNAL ERROR: got unexpected path command "..tostring(cmd))
    end
  end

  -- we finished processing commands, but make sure we flush any
  -- remaining sub-paths
  flush_subpath()
end

local function extract_rect( results, svgnode, EPSILON )
  if (svgnode.rx and svgnode.rx > 0) or (svgnode.ry and svgnode.ry > 0) then
    assert(false, "ROUNDED CORNERS ON RECTANGLES ARE UNIMPLEMENTED")
  end
  local x,y,w,h = svgnode.x, svgnode.y, svgnode.width, svgnode.height
  local tl      = NVec(x,y)
  local tr      = tl + NVec(w,0)
  local br      = tl + NVec(w,h)
  local bl      = tl + NVec(0,h)

  local rect = NewPath({
    NewBzLine(br, bl),
    NewBzLine(bl, tl),
    NewBzLine(tl, tr),
    NewBzLine(tr, br),
  })
  table.insert(results, rect)
end
local function extract_circle( results, svgnode, EPSILON )
  local c     = NVec(svgnode.cx, svgnode.cy)
  local r     = svgnode.r

  -- 4 side / anchor points
  local pr    = c + NVec(r,0)
  local pb    = c + NVec(0,r)
  local pl    = c - NVec(r,0)
  local pt    = c - NVec(0,r)
  -- 4 corner points
  local pbr   = c + NVec( r, r)
  local pbl   = c + NVec(-r, r)
  local ptl   = c + NVec(-r,-r)
  local ptr   = c + NVec( r,-r)

  local circle = NewPath({
    NewArc(pr,pbr,pb),
    NewArc(pb,pbl,pl),
    NewArc(pl,ptl,pt),
    NewArc(pt,ptr,pr),
  })
  table.insert(results, circle)
end
local function extract_ellipse( results, svgnode, EPSILON )
  assert(false, "ELLIPSE EXTRACTION UNIMPLEMENTED")
end
local function extract_line( results, svgnode, EPSILON )
  assert(false, "LINE EXTRACTION UNIMPLEMENTED")
end
local function extract_polygon( results, svgnode, EPSILON )
  local segs    = {}
  local pts     = svgnode.points
  local prevpt  = pts[#pts]
  for k,currpt in ipairs(pts) do
    segs[k] = NewBzLine(prevpt, currpt)
    prevpt = currpt
  end
  local polygon = NewPath(segs)
  table.insert(results, polygon)
end
local function extract_polyline( results, svgnode, EPSILON )
  assert(false, "POLYLINE EXTRACTION UNIMPLEMENTED")
end

local function extract_tree( results, svgnode, EPSILON )
  local typ = svgnode.type

  if      typ == 'g' or typ == 'svg' then
    for _,c in ipairs(svgnode.children) do
      extract_tree( results, c, EPSILON )
    end
  elseif  typ == 'path' then
    extract_path( results, svgnode, EPSILON )
  elseif  typ == 'rect' then
    extract_rect( results, svgnode, EPSILON )
  elseif  typ == 'circle' then
    extract_circle( results, svgnode, EPSILON )
  elseif  typ == 'ellipse' then
    extract_ellipse( results, svgnode, EPSILON )
  elseif  typ == 'line' then
    extract_line( results, svgnode, EPSILON )
  elseif  typ == 'polygon' then
    extract_polygon( results, svgnode, EPSILON )
  elseif  typ == 'polyline' then
    extract_polyline( results, svgnode, EPSILON )
  else
    assert(false, "UNRECOGNIZED SVG NODE TYPE: "..tostring(typ))
  end
end


-- ========================================================================= --

local SVGObj    = {}
SVGObj.__index  = SVGObj

function SVGObj.New(args)
  local svgtree, errs= SVG.ParseSVG(args.filename, args.verbose)
  if not svgtree or errs then
    local errmsg = 'encountered errors during SVG file parsing:\n'
    for _,e in ipairs(errs) do
      errmsg = errmsg..' '..e
    end
    error(errmsg, 2)
  end
  assert(svgtree.type == 'svg')

  local obj = setmetatable({
    _width    = svgtree.width,
    _height   = svgtree.height,
    _attrs    = svgtree.attrs,
    _paths    = {},
  }, SVGObj)

  local EPSILON = math.min(obj:w(), obj:h()) * 1.0e-3
  extract_tree(obj._paths, svgtree, EPSILON)
  for _,p in ipairs(obj._paths) do
    if not p:isClosed() then
      error('Found unclosed path in input, aborting...')
    end
  end

  return obj
end

function SVGObj:w() return self._width  end
function SVGObj:h() return self._height end


-- New primitive shapes
--function SVGObj.NewBlank(args)
--  local obj = setmetatable({
--    _width    = args.width or 1,
--    _height   = args.height or 1,
--    _paths    = {},
--  }, SVGObj)
--
--  return obj
--end

function SVGObj:draw(win, view, opts)
  opts = opts or {}
  local color = P.NewColor(opts.color or {r=31,g=31,b=31})
  win:cairoSave()
    -- color
    win:setColor(color:unpack())

    -- draw the paths
    win:beginPath()
    for _,path in ipairs(self._paths) do
      local initpt = view:toPx(path._segs[1]:a0())
      win:moveTo(initpt.x, initpt.y)
      for _,seg in ipairs(path._segs) do
        local bz          = seg:toBz()
        local p1, p2, p3  = view:toPx(bz.p1),
                            view:toPx(bz.p2),
                            view:toPx(bz.p3)
        win:curveTo( p1.x, p1.y, p2.x, p2.y, p3.x, p3.y )
      end
      win:closePath()
    end
    win:fill()

  win:cairoRestore()
end




-- ========================================================================= --


local ConsoleWidget     = require 'consolewidget'
local AssortedWidgets   = require 'assortedwidgets'
local SpecialWidgets    = require 'specialwidgets'
local FTMonitor         = SpecialWidgets.FTMonitor
local FilePicker        = SpecialWidgets.FilePicker
local Panel             = AssortedWidgets.Panel

local function setupConsole(parent_layer)
  -- console and sizing
  local console_is_visible = false
  local console = ConsoleWidget.New {
    pxbox   = { l=0,t=0,w=420,h=200 },
    padding = 10,
    backcolor = {r=15,g=15,b=31,a=191},
  }
  local w = console:getWidthForNChars(80)
  local h = console:getHeightForNLines(14)
  console:setPxBox { l=0, t=0, w=w, h=h }

  -- ensure that the window can't get smaller than the console
  local wh = RawGUI.GetMainWindow():getMinWH()
  RawGUI.GetMainWindow():setMinWH(math.max(w, wh._0), math.max(h, wh._1))

  -- console comes equipped with a boilerplate evaluator
  console:onExecute(ConsoleWidget.DefaultLuaTerraEval)
  RawGUI.onEvent('KEYDOWN', function(ev)
    if ev.key == 'Escape' then
      if console_is_visible then
        parent_layer:RemoveWidget(console)
        console:ReleaseKeyFocus()
        console:ReleaseMouseFocus()
      else
        parent_layer:AddWidgetAtFront(console)
        console:GrabKeyFocus()
      end
      console_is_visible = not console_is_visible
    end
  end)

  return console
end

local MODAL_ACTIVE = false
local function modalFileDialog(do_save, onCancel,onConfirm)
  if MODAL_ACTIVE then return end -- don't allow re-entry
  MODAL_ACTIVE = true
  local win = RawGUI.GetMainWindow()
  local w,h = win:getBounds()._2, win:getBounds()._3

  -- dim everything else on the screen and block event routing!
  local screen = Panel.New {
    pxbox       = {l=0,t=0, w=w, h=h},
    fillcolor   = {r=0,g=0,b=0,a=127},
  }
  -- capture every event that hits the screen
  screen.testPxBox = RawGUI.Widget.testPxBox -- re-enable event routing
  screen.route = function(self, event)
    RawGUI.CaptureCurrentEvent()
  end
  RawGUI.AddWidgetAtFront(screen)

  -- Kill any existing focus when entering the dialog
  RawGUI.ReleaseKeyFocus()
  RawGUI.ReleaseMouseFocus()

  -- position the file loading dialog
  local x,y = math.floor(w*0.125),10
  local fchooser = FilePicker.New {
    pxbox = { l=x, t=y, w=math.floor(w*0.75), h=math.floor(h*0.66) },
    write = do_save,
  }
  RawGUI.AddWidgetAtFront(fchooser)

  -- dialog result scenarios
  local function onDialogExit()
    -- clear any persistent focus
    RawGUI.ReleaseKeyFocus()
    RawGUI.ReleaseMouseFocus()
    -- remove the widgets from the GUI
    RawGUI.RemoveWidget(fchooser)
    RawGUI.RemoveWidget(screen)
    fchooser:destroy()
    MODAL_ACTIVE = false
  end
  fchooser:onConfirm(function(filepath)
    onDialogExit()
    onConfirm(filepath)
  end)
  fchooser:onCancel(function()
    onDialogExit()
    onCancel()
  end)
end
local function loadFileDialog(oncancel,onconfirm)
  modalFileDialog(false, oncancel, onconfirm)
end
local function saveFileDialog(oncancel,onconfirm)
  modalFileDialog(true, oncancel, onconfirm)
end


local CURR_SVG
local VIEW
local function loadSVGFile(filepath, layer)
  if VIEW then
    VIEW:ReleaseMouseFocus()
    layer:RemoveWidget(VIEW)
    VIEW = nil
  end

  -- svg view
  xpcall(function()
    CURR_SVG = SVGObj.New {
      filename = tostring(filepath),
    }
  end, function(err)
    print(err)
  end)
  if not CURR_SVG then return end

  -- construct the view
  local win = RawGUI.GetMainWindow()
  local winw, winh = win:getBounds()._2, win:getBounds()._3
  VIEW = Viewport.New {
    pxbox     = { l=0, t=0, w=winw, h=winh },
    viewbox   = { l=0, t=0, w=CURR_SVG:w(), h = CURR_SVG:h() },
    pxmargin  = 10,
  }
  -- initially, center and enlarge the image
  -- then maintain a reasonable view when the window is resized
  VIEW:setViewAspectRatioFromPx()
  VIEW:zoomToFit()
  RawGUI.onEvent('RESIZE_WINDOW', function(ev)
    VIEW:setPxBox { l=0, t=0, w=ev.w, h=ev.h }
    VIEW:setViewAspectRatioFromPx()
    VIEW:restrictViewToWorld()
    
    local newbox = ftmonitor:getPxBox():translateCornerBy { l=0, b=ev.h }
    ftmonitor:setPxBox(newbox)
  end)

  -- drawing and routing behavior for the svg view
  VIEW.drawScene = function(self)
    CURR_SVG:draw(win, self)
    -- draw world boundary box for the drawing
    win:cairoSave()
      win:setColor(201,201,201)
      local origin  = VIEW:toPx(NVec(0,0))
      local wh      = VIEW:toPxD(NVec(CURR_SVG:w(),CURR_SVG:h()))
      win:rectangle( origin.x, origin.y, wh.x, wh.y )
      win:setLineWidth(1.5)
      win:stroke()
    win:cairoRestore()
  end
  -- any routing now?
  local view_state = 'plain'
  VIEW.route = function(self, event)
    local caught_event = true
    if event.type == 'MOUSEWHEEL' then
      -- seems like up is positive, down negative in event.y
      VIEW:doZoom(-event.y)
    
    elseif  event.type == 'MOUSEDOWN'         then
      view_state = 'press'
      self:GrabMouseFocus()
      -- drag start callback

    elseif  event.type == 'MOUSE_FOCUS_LOST'  then
      view_state = 'plain'
      -- drag stop callback

    elseif  event.type == 'MOUSEUP'           then
      self:ReleaseMouseFocus()

    elseif  event.type == 'MOUSEMOVE'
            and self:hasMouseFocus()          then
      -- drag move callback
      self:doPan(NVec(-event.dx, -event.dy))

    elseif  event.type == 'MOUSE_ENTER'       then

    else caught_event = false end
    if caught_event then RawGUI.CaptureCurrentEvent() end
  end
  layer:AddWidgetAtFront(VIEW)
end



RawGUI.onSetup(function()
  local win = RawGUI.GetMainWindow()
  RawGUI.setClearColor(P.NewColor(223,223,223))

  -- layers
  local docLayer        = RawGUI.NewLayer()
  local guiOverlay      = RawGUI.NewLayer()
  local consoleOverlay  = RawGUI.NewLayer()
  RawGUI.AddWidgetAtFront(docLayer)
  RawGUI.AddWidgetAtFront(guiOverlay)
  RawGUI.AddWidgetAtFront(consoleOverlay)

  -- console overlay
  local console = setupConsole(consoleOverlay)
  -- clear key focus if a click isn't captured
  RawGUI.onEvent('MOUSEDOWN', function(ev)
    console:ReleaseKeyFocus()
  end)

  -- Frametime metrics
  local winbd = win:getBounds()
  local ftmonitor = FTMonitor.New {
    pxbox = { l=0, b=winbd._3, w=120, h=50 },
  }
  guiOverlay:AddWidgetAtFront(ftmonitor)

  -- loading dialog
  RawGUI.onEvent('KEYDOWN', function(ev)
    if ev.key == 'R' then
      loadFileDialog(
        function() print('cancel load') end,
        function(filepath)
          print('load', filepath) 
          loadSVGFile(filepath, docLayer)
        end
      )
    end
  end)
end)

RawGUI.StartLoop {
  winargs = {
    resizable = true,
    minw = 100, minh = 100,
    --noborder = true,
  },
}




-- ========================================================================= --

-- non-visual unit test

local ffi = require 'ffi'

local lscmd
if ffi.os == "Windows" then
  lscmd = "cmd /c dir /b /s"
else
  lscmd = "find . | cut -c 3-"
end

local fileskiplist = {
  -- parser breaks on some filter
  ['testsvgs/diamond.svg'] = true,
  ['testsvgs/tablet-lg.svg'] = true,
  -- unhandled cases
  ['testsvgs/golf13.svg'] = true,
  ['testsvgs/remote2.svg'] = true,
  -- unclosed paths
  ['testsvgs/clock-lg.svg'] = true,
}

function SVG.RunTests()
  print('==============================')
  print('= Running SVG Viewport Tests =')
  print('==============================')
  for line in io.popen(lscmd):lines() do
    if ffi.os == "Windows" then
      local cwd = io.popen("cmd /c echo %cd%"):read()
      line = line:sub(cwd:len()+2)
      line = line:gsub("\\","/")
    end
    local filename  = line:match("^(testsvgs/.*%.svg)$")
    local out_file  = filename and
                      filename:gsub("/(.-)%.svg$", "/%1.lua")
    if filename and not fileskiplist[filename] then
      print(filename)
      local svgobj = SVGObj.New {
        filename  = filename,
        --verbose   = true,
      }
    end
  end
end

--SVG.RunTests()








