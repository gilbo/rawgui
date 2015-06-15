--
--  viewport.t
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

local Viewport = {}
package.loaded['viewport'] = Viewport

---------------------------------------------

local RawGUI  = require 'rawgui'
local P       = require 'primitives'
local Vec     = P.Vec
local NVec    = P.NewVecUnsafe
local NewBox  = P.NewBox


---------------------------------------------
-- Setting up Scene Objects
---------------------------------------------

local CoordFrame    = {}
CoordFrame.__index  = CoordFrame

-- to inherit from; call this to set-up
local function NewCoordFrame()
  return setmetatable({},CoordFrame):_initialize()
end
function CoordFrame:_initialize()
  self._origin = NVec(0,0)
  self._scale        = 1
  self._scale_inv    = 1
  return self
end
function CoordFrame:toLocal( pt )
  return self._scale * pt + self._origin
end
function CoordFrame:toGlobal( pt )
  return self._scale_inv * ( pt - self._origin )
end
function CoordFrame:tangentToLocal( tangent )
  return self._scale * tangent
end
function CoordFrame:tangentToGlobal( tangent )
  return self._scale_inv * tangent
end





RawGUI.SubClassWidget(Viewport, 'Viewport')

function Viewport:_initialize(opts)
  opts = opts or {}
  -- check args
  local argerr = [[
  When initializing a Viewport, you must provide...
    'pxbox'   : a box specifying the position of the viewport in pixel space
    'viewbox' : a box specifying the position of the viewport in
                a local coordinate system called view-space.
      --  The Viewport as a coordinate frame translates from
      --      PX   SPACE (the global space) to
      --      VIEW SPACE (the local space)
    'worldbounds' : (optional) limits on how the viewbox is allowed to move.
    'px_margin'   : when enforcing worldbounds, allow this much slack in px]]
  if not opts.pxbox then error(argerr, 2) end

  self._transform           = NewCoordFrame()
  self._transform_listeners = {}
  self._keypress_handlers   = {}
  self._px_margin           = opts.pxmargin or 0

  self._viewbox       = NewBox { l=0, t=0, w=1, h=1 } -- to avoid error
  self:setPxBox(opts.pxbox)
  if opts.viewbox then self:setViewBox(opts.viewbox) end

  self._padding       = opts.padding or 0
  local worldbounds   = opts.worldbounds or self._viewbox
  self:setWorldBounds(worldbounds)

  return self
end
function Viewport.New(opts)
  local view = setmetatable({}, Viewport)
  return view:_initialize(opts)
end

function Viewport:setPxBox(box)
  self._pxbox = NewBox(box)
  if self._pxbox.h < 1 or self._pxbox.w < 1 then
    error('pixel box must be at least 1 pixel wide & tall', 2)
  end
  self:_refreshTransform()
end
function Viewport:setViewBox(box)
  self._viewbox = NewBox(box)
  if self._viewbox.h <= 0 or self._viewbox.w <= 0 then
    error('the view must be wider & taller than 0', 2)
  end
  self:_refreshTransform()
end
function Viewport:_refreshTransform()
  local scale                 = self._viewbox.h / self._pxbox.h
  self._transform._scale      = scale
  self._transform._scale_inv  = 1.0 / scale
  self._transform._origin     = self._viewbox:lt() - scale * self._pxbox:lt()
  self:_exec_transform_listeners()
end

function Viewport:setWorldBounds(box)
  self._worldbounds = NewBox(box)
  if self._worldbounds.h <= 0 or self._worldbounds.w <= 0 then
    error('world bounds must be wider & taller than 0', 2)
  end
  self:restrictViewToWorld()
end
function Viewport:setPxMargin(val)
  self._px_margin = val
  self:restrictViewToWorld()
end
function Viewport:restrictViewToWorld()
  local WM    = self._transform:tangentToLocal(NVec(self._px_margin, 0)).x
  local wbd   = self._worldbounds
  local vbx   = self._viewbox

  -- default centering for being too small in a dimension
  local d = wbd:center() - vbx:center()

  -- if the view is wide enough snap in horizontally
  if wbd.w + 2*WM >= vbx.w then
    local dl = (wbd.l - WM) - vbx.l
    local dr = vbx.r - (wbd.r + WM)
    if      dl > 0  then  d.x =  dl
    elseif  dr > 0  then  d.x = -dr
    else                  d.x =  0  end -- case: no adjustment needed
  end

  -- if the view is tall enough snap in vertically
  if wbd.h + 2*WM >= vbx.h then
    local dt = (wbd.t - WM) - vbx.t
    local db = vbx.b - (wbd.b + WM)
    if      dt > 0  then  d.y =  dt
    elseif  db > 0  then  d.y = -db
    else                  d.y =  0  end -- case: no adjustment needed
  end

  self._viewbox = self._viewbox:translateBy(d)
  self:_refreshTransform()
end
function Viewport:zoomToFit()
  local PXM = self._px_margin
  local wbd = self._worldbounds
  local pxb = self._pxbox

  -- We want to ensure the entire world fits inside the viewbox,
  --   (accounting for the additional pixel margin)
  --   but otherwise that the viewbox is as small as possible
  -- Therefore,
  --      wbd.w <= toLocal(pxb.w - 2*PXM) = SCALE * (pxb.w - 2*PXM)
  --      wbd.h <= toLocal(pxb.h - 2*PXM) = SCALE * (pxb.h - 2*PXM)
  -- If we solve for two scales, then we need to use the larger of the
  -- two or else we'll end up violating the inequality
  local xscale  = wbd.w / (pxb.w - 2*PXM)
  local yscale  = wbd.h / (pxb.h - 2*PXM)
  local scale   = math.max(xscale, yscale)
  -- Now, we know that we should set
  --    view.w = SCALE * pxb.w   (and similarly for h)
  self._viewbox = self._viewbox:centerScaleTo( pxb.w * scale, pxb.h * scale )
  self:restrictViewToWorld()
end
function Viewport:setViewAspectRatio(aspect) -- w / h
  local h = self._viewbox.h
  local w = h * aspect
  self._viewbox = self._viewbox:centerScaleTo( w, h )
  self:restrictViewToWorld()
end
function Viewport:setViewAspectRatioFromPx()
  local aspect = self._pxbox.w / self._pxbox.h
  self:setViewAspectRatio(aspect)
end


function Viewport:addTransformListener(key, clbk)
  if not self._transform_listeners[key] then
    self._transform_listeners[key] = {}
  end
  table.insert(self._transform_listeners[key], clbk)
end
function Viewport:_exec_transform_listeners()
  for _,cs in pairs(self._transform_listeners) do
    for _,clbk in ipairs(cs) do
      clbk()
    end
  end
end
function Viewport:removeTransformListeners(key)
  self._transform_listeners[key] = nil
end


function Viewport:doPan( px_offset )
  local v_off = self._transform:tangentToLocal( px_offset )
  self._viewbox = self._viewbox:translateBy( v_off )
  self:restrictViewToWorld()
end
Viewport._zoom_resistance = 40.0
function Viewport.GetZoomResistance()  return Viewport._zoom_resistance end
function Viewport.SetZoomResistance(r) Viewport._zoom_resistance = r    end
function Viewport:doZoom( dval )
  local scaling = math.pow(2, dval/Viewport._zoom_resistance)
  self._viewbox = self._viewbox:centerScaleBy(scaling, scaling)
  self:restrictViewToWorld()
end

function Viewport:toPx( pt )    return self._transform:toGlobal(pt) end
function Viewport:toView( pt )  return self._transform:toLocal(pt)  end
function Viewport:toPxD( pt )   return self._transform:tangentToGlobal(pt) end
function Viewport:toViewD( pt ) return self._transform:tangentToLocal(pt)  end

-- dispatch to drawScene
function Viewport:drawScene()
  error('drawScene() unimplemented for subclass of Viewport') end
function Viewport:draw()
  self:drawScene()
end






















