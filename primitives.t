--
--  primitives.t
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

local Export = {}
package.loaded['primitives'] = Export

---------------------------------------------



local Vec = {}
Vec.__index = Vec

local function NewVecUnsafe(x,y)
  return setmetatable({x=x,y=y}, Vec)
end
local function NewVec(x,y) -- slightly safer
  if getmetatable(x) == Vec then
    return x:clone()
  elseif type(x) == 'table' then
    y = x.y
    x = x.x
  end
  return NewVecUnsafe(x or 0, y or 0)
end
function Vec:clone()
  return NewVecUnsafe( self.x, self.y )
end
function Vec:unpack()
  return self.x, self.y
end

function Vec:__unm()
  return NewVecUnsafe( -self.x, -self.y )
end
function Vec.__add(lhs, rhs)
  return NewVecUnsafe( lhs.x + rhs.x, lhs.y + rhs.y )
end
function Vec.__sub(lhs, rhs)
  return NewVecUnsafe( lhs.x - rhs.x, lhs.y - rhs.y )
end
function Vec.__mul(lhs, rhs)
  if type(rhs) == 'number' then
    return NewVecUnsafe( lhs.x * rhs, lhs.y * rhs )
  elseif type(lhs) == 'number' then
    return NewVecUnsafe( lhs * rhs.x, lhs * rhs.y )
  end
end
function Vec.__div(lhs, rhs)
  local invrhs = 1/rhs
  return NewVecUnsafe( invrhs * lhs.x, invrhs * lhs.y )
end
function Vec.__eq(lhs, rhs)
  return lhs.x == rhs.x and lhs.y == rhs.y
end
function Vec:dot(rhs)
  return self.x * rhs.x + self.y * rhs.y
end
function Vec:cross(rhs)
  return self.x * rhs.y - self.y * rhs.x
end
function Vec.area(a,b,c)
  return (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x)
end
function Vec:len2()
  return self.x*self.x + self.y*self.y
end
function Vec:len()
  return math.sqrt(self.x*self.x + self.y*self.y)
end
function Vec:normalized()
  local  invlen = 1/self:len()
  return NewVecUnsafe( self.x * invlen, self.y * invlen )
end
function Vec:max(rhs)
  return NewVecUnsafe( math.max(self.x, rhs.x), math.max(self.y, rhs.y) )
end
function Vec:min(rhs)
  return NewVecUnsafe( math.min(self.x, rhs.x), math.min(self.y, rhs.y) )
end


local Box   = {}
Box.__index = Box

local function NewBoxUnsafe(l,r,t,b,w,h)
  return setmetatable({ l=l, r=r, t=t, b=b, w=w, h=h }, Box)
end
local function NewBox(params)
  local b = setmetatable({}, Box)

  params = params or {}
  local count

  b.l = params.l or params.x
  b.r = params.r
  b.w = params.w
  count = (b.l and 1 or 0) + (b.r and 1 or 0) + (b.w and 1 or 0)
  if count == 3 then
    if b.w ~= b.r - b.l then
      error('inconsistent values for r,l,w\n'..
            '  r-l = '..tostring(b.r)..'-'..tostring(b.l)..' = '..
            tostring(b.r-b.l)..' ~= '..tostring(b.w)..' = w', 2)
    end
  elseif count == 2 then
    if     not b.l then b.l = b.r - b.w
    elseif not b.r then b.r = b.l + b.w
                   else b.w = b.r - b.l end
  else
    error('must specify at least 2 of l, r, w when creating a box\n'..
          ' got l,r,w = '..tostring(b.l)..','..tostring(b.r)..
          ','..tostring(b.w), 2)
  end

  b.t = params.t or params.y
  b.b = params.b
  b.h = params.h
  count = (b.t and 1 or 0) + (b.b and 1 or 0) + (b.h and 1 or 0)
  if count == 3 then
    if b.h ~= b.b - b.t then
      error('inconsistent values for t,b,h\n'..
            '  b-t = '..tostring(b.b)..'-'..tostring(b.t)..' = '..
            tostring(b.b-b.t)..' ~= '..tostring(b.h)..' = h', 2)
    end
  elseif count == 2 then
    if     not b.t then b.t = b.b - b.h
    elseif not b.b then b.b = b.t + b.h
                   else b.h = b.b - b.t end
  else
    error('must specify at least 2 of t, b, h when creating a box\n'..
          ' got t,b,h = '..tostring(b.t)..','..tostring(b.b)..
          ','..tostring(b.h), 2)
  end

  return b
end
local function NewEmptyBox()
  return NewBoxUnsafe( math.huge, -math.huge,
                       math.huge, -math.huge,
                       math.huge, math.huge )
end
local function NewBoxFromVec(v)
  return NewBoxUnsafe( v.x, v.x, v.y, v.y, 0, 0 )
end
local function NewBoxAroundVecs(a,b)
  local min = a:min(b)
  local max = a:max(b)
  return NewBoxUnsafe( min.x, min.y, max.x, max.y, max.x-min.x, max.y-min.y )
end
function Box:clone()
  return NewBoxUnsafe( self.l, self.r, self.t, self.b, self.w, self.h )
end
function Box:wh()
  return NewVecUnsafe(self.w, self.h)
end
function Box:minvec()
  return NewVecUnsafe(self.l, self.t)
end
function Box:maxvec()
  return NewVecUnsafe(self.r, self.b)
end
function Box:isEmpty(eps)
  eps = eps or 0
  return self.w <= eps or self.h <= eps
end
function Box:convex(rhs)
  local xmin = math.min(self.l, rhs.l)
  local xmax = math.max(self.r, rhs.r)
  local ymin = math.min(self.t, rhs.t)
  local ymax = math.max(self.b, rhs.b)
  return NewBoxUnsafe( xmin, xmax, ymin, ymax, xmax-xmin, ymax-ymin )
end
function Box:isct(rhs)
  local l = math.max(self.l, rhs.l)
  local r = math.min(self.r, rhs.r)
  local t = math.max(self.t, rhs.t)
  local b = math.min(self.b, rhs.b)
  return NewBoxUnsafe( l, r, t, b, r-l, b-t )
end
function Box:isIsct(rhs, eps)
  return not self:isct(rhs):isEmpty(eps)
end
function Box:containsPoint(vec, eps)
  eps = eps or 0
  if self.l - vec.x > eps or vec.x - self.r > eps then return false end
  if self.t - vec.y > eps or vec.y - self.b > eps then return false end
  return true
end
function Box:center()
  return NewVecUnsafe( 0.5*(self.l + self.r), 0.5*(self.t + self.b) )
end
function Box:translateBy(vec)
  return NewBoxUnsafe( self.l + vec.x, self.r + vec.x,
                       self.t + vec.y, self.b + vec.y, self.w, self.h )
end
function Box:centerScaleBy(mw, mh)
  return self:centerScaleTo( mw * self.w, mh * self.h )
end
function Box:centerScaleTo(w,h)
  local c = self:center()
  return NewBoxUnsafe( c.x - 0.5*w, c.x + 0.5*w,
                       c.y - 0.5*h, c.y + 0.5*h, w, h )
end

-- useful manipulations
function Box:setBounds(bd)
  local l = bd.l or self.l
  local r = bd.r or self.r
  local t = bd.t or self.t
  local b = bd.b or self.b
  return NewBoxUnsafe(l, r, t, b, r-l, b-t)
end
function Box:expandBy(px)
  return NewBoxUnsafe(  self.l - px, self.r + px,
                        self.t - px, self.b + px,
                        self.w + 2*px, self.h + 2*px )
end
function Box:translateCornerBy(bd)
  local dxy = NewVecUnsafe(0,0)
  if      bd.l then dxy.x = bd.l - self.l
  elseif  bd.r then dxy.x = bd.r - self.r end
  if      bd.t then dxy.y = bd.t - self.t
  elseif  bd.b then dxy.y = bd.b - self.b end
  return self:translateBy(dxy)
end
function Box:lt() return NewVecUnsafe(self.l, self.t) end
function Box:lb() return NewVecUnsafe(self.l, self.b) end
function Box:rt() return NewVecUnsafe(self.r, self.t) end
function Box:rb() return NewVecUnsafe(self.r, self.b) end
function Box:unpack_ltwh()
  return self.l, self.t, self.w, self.h
end


local Color = {}
Color.__index = Color

local function NewColorUnsafe(r,g,b,a)
  return setmetatable({r=r,g=g,b=b,a=a}, Color)
end
local function NewColor(r,g,b,a)
  if getmetatable(r) == Color then
    return r:clone()
  elseif type(r) == 'table' then
    a = r.a
    b = r.b
    g = r.g
    r = r.r
  end
  return NewColorUnsafe(r or 0, g or 0, b or 0, a or 255)
end
function Color:clone()
  return NewColorUnsafe( self.r, self.g, self.b, self.a )
end
function Color:unpack()
  return self.r, self.g, self.b, self.a
end

function Color:withAlpha(a)
  return NewColorUnsafe( self.r, self.g, self.b, a )
end


-- expose things from the module
Export.NewVec               = NewVec
Export.NewVecUnsafe         = NewVecUnsafe

Export.NewBox               = NewBox
Export.NewBoxUnsafe         = NewBoxUnsafe
Export.NewEmptyBox          = NewEmptyBox
Export.NewBoxFromVec        = NewBoxFromVec
Export.NewBoxAroundVecs     = NewBoxAroundVecs

Export.NewColor             = NewColor
Export.NewColorUnsafe       = NewColorUnsafe

function Export.isVec(obj)    return getmetatable(obj) == Vec   end
function Export.isBox(obj)    return getmetatable(obj) == Box   end
function Export.isColor(obj)  return getmetatable(obj) == Color end




