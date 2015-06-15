--
--  svg.t
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

local SVG = {}
package.loaded['svg'] = SVG

---------------------------------------------

local ffi = require 'ffi'
--[[
local bit = require 'bit'
local function isbitset(flag, word)
  return bit.band(flag, word) == flag
end
local function setbit(flag, bool_val, word)
  if bool_val then
    return bit.bor(flag, word)
  else
    return bit.band(b.bnot(flag), word)
  end
end
]]

local function exec2str(cmd)
  local file    = io.popen(cmd)
  local output  = file:read('*line')
  file:close()
  return output
end
local function exec2code(cmd)
  local code = os.execute(cmd)
  return code
end

-- Link the Cairo Library
local xml2_libpath   = '/usr/lib/libxml2.dylib'
if exec2code('test -f '..xml2_libpath) ~= 0 then
  error('Could not find xml2 shared library at '..xml2_libpath)
end
--print('linking libxml2 library found at '..xml2_libpath)
terralib.linklibrary(xml2_libpath)

local xml2_includedir = '/usr/include/libxml2'
--print('setting xml2 include directory to '..xml2_includedir)
terralib.includepath  = terralib.includepath .. ';' .. xml2_includedir



local C = terralib.includecstring [[
#include "stdlib.h"
#include "stdio.h"
#include <libxml/xmlreader.h>
]]


local SVGParser = {}
SVGParser.__index = SVGParser

local function NewSVGParser(filename)
  local reader = C.xmlNewTextReaderFilename(filename)

  local parser = setmetatable({
    _filename   = filename,
    _reader     = reader,
    _errors     = {},
    _aborted    = false,
    _tree       = nil,
    _verbose    = false,
  }, SVGParser)

  if reader == nil then
    parser:abort('unable to open file: '..filename)
  end

  return parser
end
function SVGParser:makeVerbose() self._verbose = true end
function SVGParser:print(...)
  if self._verbose then print(...) end
end
function SVGParser:isOpen() return self._reader ~= nil end
function SVGParser:close()
  if self._reader then
    C.xmlFreeTextReader(self._reader)
    self._reader = nil
  end
end

function SVGParser:getResult()
  if self:wasAborted() then return nil
                       else return self._tree end
end


-- ERROR utilities
function SVGParser:error(txt)
  table.insert(self._errors, txt)
end
function SVGParser:abort(txt)
  self:error(txt)
  if self:isOpen() then self:close() end -- make sure we clean up
  self._aborted = true
end
function SVGParser:wasAborted()
  return self._aborted
end
function SVGParser:hasErrors()
  return #self._errors > 0
end
function SVGParser:getErrors()
  return self._errors
end
function SVGParser:errorStr()
  local str = self._errors[1] or ''
  for i=2,#self._errors do str = str..'\n'..self._errors[i] end
  return str
end
function SVGParser:printErrors()
  for _,e in ipairs(self._errors) do
    print(e)
  end
end




-- primitive interface to the parser
function SVGParser:readable() -- slightly a lie, returns true before first read
  return not self:wasAborted() and self:isOpen()
end
function SVGParser:readNext()
  -- guard from reading in unsafe states
  if not self:readable() then return false end

  -- invalidate the info cache
  self._info_cache = nil
  local ret_code = C.xmlTextReaderRead(self._reader)
  if      ret_code == 1 then
    return true -- yes, we read something
  elseif  ret_code == 0 then
    self:close() -- reached end of file
  else
    self:abort(self._filename..' underlying xmlparser failure, '..
                'with return code '..tostring(ret_code))
  end
  -- if we fell through to here, we did not read successfully
  return false
end
-- get basic node information
function SVGParser:getBasicNodeInfo()
  if not self:readable() then return nil end
  if self._info_cache then return self._info_cache end

  local depth     = C.xmlTextReaderDepth(self._reader)
  local nodetype  = C.xmlTextReaderNodeType(self._reader)
  local name      = ffi.string(C.xmlTextReaderConstName(self._reader))
  local is_empty  = (C.xmlTextReaderIsEmptyElement(self._reader) ~= 0)

  self._info_cache = {
    depth     = depth,
    type      = nodetype,
    name      = name,
    is_empty  = is_empty,
  }
  return self._info_cache
end
function SVGParser:skipCurrElement()
  if self:wasAborted() then return end

  local begin_info = self:getBasicNodeInfo()
  if not begin_info or begin_info.type ~= C.XML_READER_TYPE_ELEMENT then
    self:error('should only call skipCurrElement() at element nodes '..
               'called at '..begin_info.type)
    return false
  end

  -- If the element closes itself, we're done
  -- otherwise, spool through until we find the close tag
  if not begin_info.is_empty then
    while self:readNext() do
      -- break on close tag...
      local info = self:getBasicNodeInfo()
      if info.type == C.XML_READER_TYPE_END_ELEMENT then
        if begin_info.name == info.name and
           begin_info.depth == info.depth then break end
      end
    end
    if not self:isOpen() then
      self:abort(self._filename..': reached end of file without finding '..
                 'the closing tag for element '..
                 begin_info.name..' at depth '..begin_info.depth)
    end
  end
end

function SVGParser:getCurrNodeAttributes()
  local attrs     = {}
  local nodetype  = C.xmlTextReaderNodeType(self._reader)

  if nodetype == C.XML_READER_TYPE_ELEMENT then
    while C.xmlTextReaderMoveToNextAttribute(self._reader) ~= 0 do
      local reader    = self._reader
      local depth     = C.xmlTextReaderDepth(reader)
      local nodetype  = C.xmlTextReaderNodeType(reader)
      local name      = ffi.string(C.xmlTextReaderConstName(reader))
      local value     = ffi.string(C.xmlTextReaderConstValue(reader))

      attrs[name] = value
    end
  else
    --error('expected ELEMENT node')
  end
  return attrs
end
local function printAttrTable(parser, tbl)
  for k,v in pairs(tbl) do
    parser:print('','attr', k,v)
  end
end




-- checking node type
function SVGParser:isElemNode()
  local info = self:getBasicNodeInfo()
  return info and info.type == C.XML_READER_TYPE_ELEMENT
end
function SVGParser:isMainSVG()
  local info = self:getBasicNodeInfo()
  return info and info.type == C.XML_READER_TYPE_ELEMENT
              and info.name == 'svg'
              and info.depth == 0
end
function SVGParser:isMainSVGEnd()
  local info = self:getBasicNodeInfo()
  return info and info.type == C.XML_READER_TYPE_END_ELEMENT
              and info.name == 'svg'
              and info.depth == 0
end
function SVGParser:isBadSVG()
  local info = self:getBasicNodeInfo()
  return info and info.type == C.XML_READER_TYPE_ELEMENT
              and info.name == 'svg'
              and info.depth ~= 0
end
local element_blacklist = {
  -- animation elements
  ['animate'] = true,
  ['animateColor'] = true,
  ['animateMotion'] = true,
  ['animateTransform'] = true,
  ['set'] = true,
  -- structural
  ['defs'] = true,
  --'svg', -- handled as a special case "BadSVG" vs MainSVG
  ['symbol'] = true,
  ['use'] = true,
  -- gradient elements
  ['linearGradient'] = true,
  ['radialGradient'] = true,
  -- other random things we're not going to support for now
  ['a'] = true,
  ['altGlyphDef'] = true,
  ['clipPath'] = true,
  ['color-profile'] = true,
  ['cursor'] = true,
  ['filter'] = true,
  ['font'] = true,
  ['font-face'] = true,
  ['foreignObject'] = true,
  ['image'] = true,
  ['marker'] = true,
  ['mask'] = true,
  ['pattern'] = true,
  ['script'] = true,
  ['style'] = true,
  ['switch'] = true,
  ['text'] = true,
  ['view'] = true,
}
function SVGParser:isElemBlacklisted()
  local info = self:getBasicNodeInfo()
  return info and info.type == C.XML_READER_TYPE_ELEMENT
              and element_blacklist[info.name]
end
local shape_elem_whitelist = {
  ['circle'] = true,
  ['ellipse'] = true,
  ['line'] = true,
  ['path'] = true,
  ['polygon'] = true,
  ['polyline'] = true,
  ['rect'] = true,
}
function SVGParser:isElemShape()
  local info = self:getBasicNodeInfo()
  return info and info.type == C.XML_READER_TYPE_ELEMENT
              and shape_elem_whitelist[info.name]
end
function SVGParser:isElemGroup()
  local info = self:getBasicNodeInfo()
  return info and info.type == C.XML_READER_TYPE_ELEMENT
              and info.name == 'g'
end
function SVGParser:isElemClose(name)
  local info = self:getBasicNodeInfo()
  if not info then return false end
  local namecheck = not name or info.name == name
  return info and info.type == C.XML_READER_TYPE_END_ELEMENT
              and namecheck
end
function SVGParser:isNodeEmpty()
  local info = self:getBasicNodeInfo()
  return info and info.is_empty
end




-- GRAMMAR level parsing
function SVGParser:mainParse()
  -- skip until we find the main SVG
  while self:readNext() do
    if self:isMainSVG() then break end
  end
  -- only recurse if we actually found the main SVG element
  if self:isMainSVG() then
    self._tree = self:parseMainSVG()
  end

  -- now, we can just exit regardless of how much of the document is left
  self:close()
end

function SVGParser:parseMainSVG()
  self:print('parsing main SVG')
  if not self:isMainSVG() then return nil end -- guard

  local svgnode = self:extractMainSVG()
  if self:wasAborted() then return nil end

  -- now spool contents until we see the matching close tag
  while self:readNext() do
    -- exit when we hit the svg close tag
    if self:isMainSVGEnd() then break end

    local child = self:parseChildElem()
    if child then table.insert(svgnode.children, child) end

  end
  -- check that the close tag was present
  if not self:wasAborted() and not self:isMainSVGEnd() then
    self:abort('did not find closing svg tag')
    return nil
  end

  return svgnode
end

function SVGParser:parseGroup()
  self:print('parsing group')
  if not self:isElemGroup() then return nil end -- guard

  local gnode = self:extractGroup()
  if self:wasAborted() then return nil end

  -- early exit in probably non-existent edge-case of an empty group
  if self:isNodeEmpty() then return gnode end

  -- spool through group's children
  while self:readNext() do
    -- exit when we hit a group close tag
    if self:isElemClose('g') then break end

    local child = self:parseChildElem()
    if child then table.insert(gnode.children, child) end

  end
  if not self:wasAborted() and not self:isElemClose('g') then
    self:abort('did not find closing tag for group')
    return nil
  end

  return gnode
end

function SVGParser:parseChildElem()
  local result = nil
  local processed = false

  -- node: ELEMENT
  if self:isElemNode() then

    -- nested SVG
    if self:isBadSVG() then
      self:abort('nested svg elements are not allowed')
      processed = true

    -- BLACKLISTED elements
    elseif self:isElemBlacklisted() then
      local name = self:getBasicNodeInfo().name
      self:error(self._filename..': SVG Parser does not handle '..
                 name..' elements')
      self:skipCurrElement()
      processed = true

    -- permitted elements (may or may not be handled...)
    else
      processed = true
      -- shape elements
      if      self:isElemShape() then
        result = self:parseShape()

      elseif  self:isElemGroup() then
        result = self:parseGroup()

      else
        processed = false
      end
    end
  end

  -- DEFAULT case
  if not processed then
    -- otherwise for now extract nodes
    self:defaultSkipNode()
  end

  return result
end

function SVGParser:parseShape()
  local info = self:getBasicNodeInfo()
  self:print('parsing shape: '..info.name)
  local node

  if      info.name == 'circle' then
    node = self:extractCircle()

  elseif  info.name == 'ellipse' then
    node = self:extractEllipse()

  elseif  info.name == 'line' then
    node = self:extractLine()

  elseif  info.name == 'path' then
    node = self:extractPath()

  elseif  info.name == 'polygon' then
    node = self:extractPolygon()

  elseif  info.name == 'polyline' then
    node = self:extractPolyline()

  elseif  info.name == 'rect' then
    node = self:extractRect()

  else -- default, shouldn't happen
    return nil
  end

  -- skip to the end of this element then
  self:skipCurrElement()

  return node
end







-- attributes to explode on
local attribute_blacklist = {
  ['externalResourcesRequired'] = true,
  ['transform'] = true, -- could try to support this though...
}
function SVGParser:filterAttrs(attrs, ignore)
  ignore = ignore or {}
  local filtered_attrs = {}
  for k,v in pairs(attrs) do
    -- blacklist some attributes
    if      attribute_blacklist[k] then
      self:abort(self._filename..': unsupported element attribute: '..k)

    -- we might have asked to ignore this attribute when filtering
    elseif  ignore[k] then
      -- do nothing

    -- mainly, we'll just pass through the attributes
    else
      filtered_attrs[k] = v
      self:print('', 'attr', k, v)
    end
  end
  return filtered_attrs
end

function SVGParser:extractMainSVG()
  local attrs = self:getCurrNodeAttributes()
  local filtered_attrs = self:filterAttrs(attrs, {
    ['width']   = true,
    ['height']  = true,
    ['viewBox'] = true,
  })

  local width = self:parseLength(attrs['width'])
  local height = self:parseLength(attrs['height'])
  local x,y,w,h = self:parseViewBox(attrs['viewBox'])

  if width and w and width ~= w then
    self:error('inconsistent widths specified by svg element: '..
               tostring(width)..' and '..tostring(w)..
               '; defaulting to the first value')
  elseif not width and not w then
    self:abort(self._filename..': no width specified by main svg element')
  end

  if height and h and height ~= h then
    self:error('inconsistent heights specified by svg element: '..
               tostring(height)..' and '..tostring(h)..
               '; defaulting to the first value')
  elseif not height and not h then
    self:abort(self._filename..': no height specified by main svg element')
  end

  width   = width or w
  height  = height or h

  self:print('', 'WIDTH', width)
  self:print('', 'HEIGHT', height)

  local node = {
    type      = 'svg',
    attrs     = filtered_attrs,
    width     = width,
    height    = height,
    children  = {},
  }
  return node
end

function SVGParser:extractGroup()
  local attrs           = self:getCurrNodeAttributes()
  local filtered_attrs  = self:filterAttrs(attrs)

  local node = {
    type      = 'g',
    attrs     = filtered_attrs,
    children  = {},
  }
  return node
end

local function extractValCommon(parser, val, name, shapename)
  if not val then parser:abort(parser._filename..': no '..name..
                              ' specified for '..shapename) end
  parser:print('',name,val)
  return val
end
local function extractLength(parser, attrs, name, shapename)
  local val = parser:parseLength(attrs[name])
  return extractValCommon(parser, val, name, shapename)
end
local function extractCoord(parser, attrs, name, shapename)
  local val = 0 -- ok to not specify and default to 0 for coordinates
  if attrs[name] then val = parser:parseCoordinate(attrs[name]) end
  return extractValCommon(parser, val, name, shapename)
end

function SVGParser:extractCircle()
  local attrs           = self:getCurrNodeAttributes()
  local filtered_attrs  = self:filterAttrs(attrs, {
    ['cx'] = true,
    ['cy'] = true,
    ['r'] = true,
  })

  local node = {
    type      = 'circle',
    attrs     = filtered_attrs,
    cx        = extractCoord(self, attrs, 'cx', 'circle'),
    cy        = extractCoord(self, attrs, 'cy', 'circle'),
    r         = extractLength(self, attrs, 'r', 'circle'),
    children  = {},
  }
  return node
end

function SVGParser:extractEllipse()
  local attrs           = self:getCurrNodeAttributes()
  local filtered_attrs  = self:filterAttrs(attrs, {
    ['cx'] = true,
    ['cy'] = true,
    ['rx'] = true,
    ['ry'] = true,
  })

  local node = {
    type      = 'ellipse',
    attrs     = filtered_attrs,
    cx        =  extractCoord(self, attrs, 'cx', 'ellipse'),
    cy        =  extractCoord(self, attrs, 'cy', 'ellipse'),
    rx        = extractLength(self, attrs, 'rx', 'ellipse'),
    ry        = extractLength(self, attrs, 'ry', 'ellipse'),
    children  = {},
  }
  return node
end

function SVGParser:extractLine()
  local attrs           = self:getCurrNodeAttributes()
  local filtered_attrs  = self:filterAttrs(attrs, {
    ['x1'] = true,
    ['x2'] = true,
    ['y1'] = true,
    ['y2'] = true,
  })

  local node = {
    type      = 'line',
    attrs     = filtered_attrs,
    x1        = extractCoord(self, attrs, 'x1', 'line'),
    x2        = extractCoord(self, attrs, 'x2', 'line'),
    y1        = extractCoord(self, attrs, 'y1', 'line'),
    y2        = extractCoord(self, attrs, 'y2', 'line'),
    children  = {},
  }
  return node
end

function SVGParser:extractRect()
  local attrs           = self:getCurrNodeAttributes()
  local filtered_attrs  = self:filterAttrs(attrs, {
    ['x'] = true,
    ['y'] = true,
    ['width'] = true,
    ['height'] = true,
    ['rx'] = true,
    ['ry'] = true,
  })

  local node = {
    type      = 'rect',
    attrs     = filtered_attrs,
    x         =  extractCoord(self, attrs, 'x', 'rect'),
    y         =  extractCoord(self, attrs, 'y', 'rect'),
    width     = extractLength(self, attrs, 'width', 'rect'),
    height    = extractLength(self, attrs, 'height', 'rect'),
    children  = {},
  }

  -- now handle the possibility of rounded corners
  local rx, ry
  if attrs['rx'] then rx = extractLength(self, attrs, 'rx', 'rect') end
  if attrs['ry'] then ry = extractLength(self, attrs, 'ry', 'rect') end
  -- handle cases of absent values
  if     rx and not ry then ry = rx
  elseif ry and not rx then rx = ry
  elseif not rx and not ry then rx, ry = 0, 0 end
  -- clamp values
  if rx > node.width/2 then rx = node.width/2 end
  if ry > node.height/2 then ry = node.height/2 end
  node.rx = rx
  node.ry = ry

  return node
end

function SVGParser:extractPolyline()
  local attrs           = self:getCurrNodeAttributes()
  local filtered_attrs  = self:filterAttrs(attrs, {
    ['points'] = true,
  })
  
  local points = self:parseListOfPoints(attrs['points'])
  if not points then
    self:abort(self._filename..': no points specified for polyline') end


  self:print('', 'POINTS', '# = '..#points)

  local node = {
    type      = 'polyline',
    attrs     = filtered_attrs,
    points    = points,
    children  = {},
  }
  return node
end

function SVGParser:extractPolygon()
  local attrs           = self:getCurrNodeAttributes()
  local filtered_attrs  = self:filterAttrs(attrs, {
    ['points'] = true,
  })
  
  local points = self:parseListOfPoints(attrs['points'])
  if not points then
    self:abort(self._filename..': no points specified for polygon') end


  self:print('', 'POINTS', '# = '..tostring(points and #points))

  local node = {
    type      = 'polygon',
    attrs     = filtered_attrs,
    points    = points,
    children  = {},
  }
  return node
end

function SVGParser:extractPath()
  local attrs           = self:getCurrNodeAttributes()
  local filtered_attrs  = self:filterAttrs(attrs, {
    ['d'] = true,
  })
  
  local pathdata = self:parsePathData(attrs['d'])
  if not pathdata then
    self:abort(self._filename..': no data specified for path') end

  --self:print('', 'POINTS', '# = '..#points)

  local node = {
    type      = 'path',
    attrs     = filtered_attrs,
    data      = pathdata,
    children  = {},
  }
  return node
end

function SVGParser:defaultSkipNode()
  local info = self:getBasicNodeInfo()

  local value     = nil
  if C.xmlTextReaderHasValue(self._reader) ~= 0 then
    value = ffi.string(C.xmlTextReaderConstValue(self._reader))
  end
  self:print('skip', info.depth, info.type, info.name, value)

  if self:isElemNode() then
    printAttrTable( self, self:getCurrNodeAttributes() )
    self:skipCurrElement()
  end
end







local unit_list = {
  ['em'] = true,
  ['ex'] = true,
  ['px'] = true,
  ['in'] = true,
  ['cm'] = true,
  ['mm'] = true,
  ['pt'] = true,
  ['pc'] = true,
}
function SVGParser:parseLength(str)
  if not str then return nil end

  -- first, try to detect any units present
  local suffix = str:sub(-2,-1)
  if unit_list[suffix] then
    if suffix == 'px' then
      str = str:sub(1,-3) -- chop off suffix
    else
      self:error('parser only allows px or unitless lengths, '..suffix..
                 ' is unsupported')
      return nil
    end
  elseif str:sub(-1,-1) == '%' then
    self:error('parser does not allow lengths to be specified with %')
    return nil
  end

  -- now we can just shove the number through the Lua conversion function
  local num = tonumber(str)
  if not num then
    self:error('could not correctly parse length number: '..str)
    return nil
  end
  return num
end
function SVGParser:parseCoordinate(str)
  return self:parseLength(str)
end

function SVGParser:parseViewBox(str)
  if not str then return nil end

  local num     = '([^%s,]+)'
  local delimit = '%s*[,%s]%s*'
  local pattern = '^'..num..delimit..num..delimit..num..delimit..num..'$'
  local xstr,ystr,wstr,hstr = str:match(pattern)
  if not wstr or not hstr then
    self:error('unable to successfully parse viewBox value string')
    return nil
  end

  local x,y,w,h = tonumber(xstr), tonumber(ystr),
                  tonumber(wstr), tonumber(hstr)
  if not x or not y or not w or not h then
    self:error('unable to successfully parse numbers in viewBox value string')
    return nil
  end

  return x,y,w,h
end

function SVGParser:parseListOfPoints(str)
  if not str then return nil end

  local num     = '([^%s,]+)'
  local ptstrs  = {}
  for s in str:gmatch(num) do table.insert(ptstrs, s) end
  if #ptstrs % 2 ~= 0 then 
    self:error('found an odd number of points in list-of-points string')
    return nil
  end
  if #ptstrs == 0 then
    self:error('found zero points in list-of-points string')
    return nil
  end
  local N = #ptstrs / 2

  local coords  = {}
  for i=1,N do
    local xstr = ptstrs[2*(i-1) + 1]
    local ystr = ptstrs[2*(i-1) + 2]
    local x = tonumber(xstr)
    local y = tonumber(ystr)
    if not x or not y then
      self:error('failed to parse number in list-of-points string: '..
                 tostring(xstr)..'  or  '..tostring(ystr))
      return nil
    end
    coords[i] = { x = x, y = y }
  end
  return coords
end


local PathParser = {}
PathParser.__index = PathParser

local function NewPathParser(str)
  local pp = setmetatable({
    str     = str,
    cmdlist = {},
  }, PathParser)
  return pp
end

local struct PathLexer {
  str   : &int8,
  len   : uint32,  -- string length
  k     : uint32,  -- read position
  start : &uint32, -- where each token starts (inclusive)
  stop  : &uint32, -- where each token ends   (exclusive)
  ntkn  : uint32,  -- total # of tokens lexed
  err   : bool,    -- was there an error lexing/parsing?
}

terra PathLexer:init( str : &int8, strlen : uint32 )
  self.str    = str
  self.len    = strlen
  self.k      = 0
  self.start  = [&uint32](C.malloc( 4 * strlen ))
  self.stop   = [&uint32](C.malloc( 4 * strlen ))
  self.ntkn   = 0
  self.err    = false

  -- do the parsing
  self:expectsvgpath()
end
terra PathLexer:cleanup()
  C.free(self.start)
  C.free(self.stop)
  self.start = nil
  self.stop = nil
end
function PathLexer.methods.gettokens(self)
  local tkns  = {}
  local N     = self.ntkn-1
  local str   = ffi.string(self.str)
  for i=0,N do
    tkns[i+1] = str:sub(self.start[i]+1, self.stop[i])
  end
  -- useful print for inspecting lexer output
  --print(unpack(tkns))
  return tkns
end
terra PathLexer:waserror()
  return self.err
end

-- basic processing functions
terra PathLexer:curr() : uint8
  return self.str[self.k]
end
terra PathLexer:step()
  self.k = self.k + 1
end
terra PathLexer:next() : uint8
  var c = self:curr()
  self:step()
  return c
end
terra PathLexer:iseof() : bool
  return self.k == self.len
end
terra PathLexer:pushstart()
  self.start[self.ntkn] = self.k
end
terra PathLexer:pushstop()
  self.stop[self.ntkn] = self.k
  self.ntkn = self.ntkn + 1
end

-- basic testing functions (is___())
terra PathLexer:iswsp() : bool -- is whitespace
  var c = self:curr()
  return c == 32 or c == 9 or c == 10 or c == 13
end
terra PathLexer:isdigit() : bool
  var c = self:curr()
  return c >= @'0' and c <= @'9'
end
terra PathLexer:issign() : bool
  var c = self:curr()
  return c == @'+' or c == @'-'
end
terra PathLexer:ise() : bool
  var c = self:curr()
  return c == @'e' or c == @'E'
end
terra PathLexer:isdot() : bool
  var c = self:curr()
  return c == @'.'
end
terra PathLexer:is01() : bool
  var c = self:curr()
  return c == @'0' or c == @'1'
end
terra PathLexer:isalpha() : bool
  var c = self:curr()
  return  (c >= @'A' and c <= @'Z') or
          (c >= @'a' and c <= @'z')
end
terra PathLexer:iscomma() : bool
  var c = self:curr()
  return c == @','
end
-- is it possible that this is the start of a number
terra PathLexer:isnumstart() : bool
  return self:isdigit() or self:isdot() or self:issign()
end

-- consumption functions, 2 kinds
--  maybe___() will try to consume,
--      but returns false consuming nothing
--      if nothing found
--  expect___() will try to consume,
--      but register error if fails,
--      possibly leaving stream in a bad state
--      will return false on failure too
terra PathLexer:maybewsp()    : bool    -- wsp*
  var k = self.k
  while self:iswsp() do self:step() end
  return self.k > k
end
terra PathLexer:maybecomma()  : bool    -- comma?
  var test = self:iscomma()
  if test then self:step() end
  return test
end
terra PathLexer:expecte()     : bool    -- ('e'|'E')
  var test = self:ise()
  if test then self:step()
          else self.err = true end
  return test
end
terra PathLexer:maybedot()    : bool    -- '.'?
  var test = self:isdot()
  if test then self:step() end
  return test
end
terra PathLexer:maybesign()   : bool    -- sign?
  var test = self:issign()
  if test then self:step() end
  return test
end
terra PathLexer:maybedigits() : bool    -- digit*
  var k = self.k
  while self:isdigit() do self:step() end
  return self.k > k
end
terra PathLexer:expectdigits() : bool   -- digit+
  var test = self:maybedigits()
  if not test then self.err = true end
  return test
end
terra PathLexer:maybecwsp()   : bool    -- comma-wsp?
  var hadwsp    = self:maybewsp()
  var hadcomma  = self:maybecomma()
  self:maybewsp()
  return hadwsp or hadcomma
end
terra PathLexer:expectcwsp()  : bool    -- comma-wsp
  var test = self:maybecwsp()
  if not test then self.err = true end
  return test
end
terra PathLexer:expectexp()   : bool    -- exponent
  return self:expecte()
     and (self:maybesign() or true)
     and self:expectdigits()
end
terra PathLexer:expectnumconst() : bool -- integer/float-constant
  -- cases:
  -- integer:   digit+
  -- float1:    digit+ exponent
  -- float2:    digit+ '.' digit* exponent?
  -- float3:    '.' digit+ exponent?
  -- collapsing these, we have
  --    digit+ exponent?
  --    digit+ '.' digit* exponent?
  --    '.' digit+ exponent?
  var digit_prefix  = self:maybedigits()
  var has_dot       = self:maybedot()
  var digit_frac    = self:maybedigits()

  -- catch inconsistencies
  if not has_dot and not digit_prefix then
    self.err = true
    return false
  elseif not digit_prefix and has_dot and not digit_frac then
    self.err = true
    return false
  end

  -- if we see the beginning of an exponent, the
  -- whole thing better be there
  if self:ise() then return self:expectexp() end

  -- success.  Got to end
  return true
end
terra PathLexer:expectflag()  : bool    -- flag
  self:pushstart()
  var test = self:is01()
  if test then self:step()
          else self.err = true end
  self:pushstop()
  return test
end
terra PathLexer:expectnonneg() : bool   -- non-negative-number
  self:pushstart()
  var res = self:expectnumconst()
  self:pushstop()
  return res
end
terra PathLexer:expectnum()   : bool    -- number
  self:pushstart()
  self:maybesign()
  var res = self:expectnumconst()
  self:pushstop()
  return res
end
terra PathLexer:expectarcarg() : bool   -- arc-argument
  return  self:expectnonneg()
     and  (self:maybecwsp() or true)
     and  self:expectnonneg()
     and  (self:maybecwsp() or true)
     and  self:expectnum()
     and  self:expectcwsp()
     and  self:expectflag()
     and  (self:maybecwsp() or true)
     and  self:expectflag()
     and  (self:maybecwsp() or true)
     and  self:expectnum()
     and  (self:maybecwsp() or true)
     and  self:expectnum()
end
terra PathLexer:expectarcargs() : bool  -- arc-argument+
  if not self:expectarcarg() then return false end
  self:maybecwsp()
  while self:isnumstart() do
    if not self:expectarcarg() then return false end
    self:maybecwsp()
  end
  return true
end
terra PathLexer:expectnumsby( n : uint32 ) : bool -- (n * number)+
  var count : uint32 = 0
  while self:isnumstart() do
    if not self:expectnum() then return false end
    self:maybecwsp()
    count = count + 1
  end
  return count > 0 and count % n == 0
end

terra PathLexer:expectdrawcmd() : bool  -- drawto-command
  self:pushstart()
  var c = self:next()
  self:pushstop()

  self:maybewsp()
  var test = true
  if      c == @'z' or c == @'Z' then
    -- nada
  elseif  c == @'l' or c == @'L' then
    test = self:expectnumsby(2)
  elseif  c == @'h' or c == @'H' then
    test = self:expectnumsby(1)
  elseif  c == @'v' or c == @'V' then
    test = self:expectnumsby(1)
  elseif  c == @'c' or c == @'C' then
    test = self:expectnumsby(6)
  elseif  c == @'s' or c == @'S' then
    test = self:expectnumsby(4)
  elseif  c == @'q' or c == @'Q' then
    test = self:expectnumsby(4)
  elseif  c == @'t' or c == @'T' then
    test = self:expectnumsby(2)
  elseif  c == @'a' or c == @'A' then
    test = self:expectarcarg()
  else
    self.err = true
    test = false
  end
  return test
end
terra PathLexer:expectmovetogroup() : bool -- moveto-drawto-command-group
  self:pushstart()
  var m = self:next()
  self:pushstop()
  if m ~= @'m' and m ~= @'M' then
    self.err = true
    return false
  end

  -- eat up the numbers after moveto which start with a coord-pair
  -- and then maybe repeat lineto coordinate pairs, so...
  self:maybewsp()
  if not self:expectnumsby(2) then return false end
  self:maybewsp()

  -- ok, now that we've processed the leading moveto command,
  -- we can go ahead and get any kind of command
  while self:isalpha() do
    var c = self:curr() -- peek
    -- exit this moveto group if we see another
    if c == @'m' or c == @'M' then break end

    -- but by default, just process the drawto command
    if not self:expectdrawcmd() then return false end
    self:maybewsp()
  end
  -- made it here so everything is a-ok
  return true
end
terra PathLexer:expectsvgpath() : bool -- the start symbol
  self:maybewsp()
  while self:isalpha() do
    if not self:expectmovetogroup() then return false end
    self:maybewsp()
  end

  -- make sure we consumed everything
  var eof = self:iseof()
  if not eof then self.err = true end
  return eof
end


-- here, we break the path up by command characters, whitespace, and commas
function PathParser:lex()
  local lexer = terralib.new(PathLexer)
  lexer:init(self.str, #self.str)
  local waserr = lexer:waserror()
  if waserr then
    self.err_position = lexer.k
  else
    self.tokens = lexer:gettokens()
    -- also initialize the token stream
    self.k      = 1
    self.tkn    = self.tokens[1]
  end
  lexer:cleanup()

  return not waserr
end

function PathParser:curr()
  return self.tkn
end
function PathParser:step()
  self.k    = self.k+1
  self.tkn  = self.tokens[self.k]
end
function PathParser:next()
  local val = self:curr()
  self:step()
  return val
end
function PathParser:eof()
  return self.k > #self.tokens
end
function PathParser:getnargs(n)
  local tbl = {}
  for i=1,n do  tbl[i] = tonumber(self:next())  end
  return tbl
end

-- Have the parser actually assemble the tokens
-- into an instruction stream next
function PathParser:parsecommands()
  local cmdlist = {}
  local currcmd
  -- specially handle the first moveto command
  currcmd = self:next()
  table.insert(cmdlist, {
    cmd   = 'M', -- the first moveto must always be treated as absolute
    args  = self:getnargs(2),
  })
  if currcmd == 'm' then currcmd = 'l' end
  if currcmd == 'M' then currcmd = 'L' end

  -- now, we can go into standard command reading mode
  while not self:eof() do
    -- check to see if there's a new command to read out
    -- if not, we'll just make another copy of the current command
    if self:curr():match('%a') then -- if we have a letter
      currcmd = self:next()
    end
    local cmdobj = { cmd = currcmd, args = {} }
    table.insert(cmdlist, cmdobj)

    -- fill out the command arguments...
    if      currcmd == 'm' or currcmd == 'M' then
      cmdobj.args   = self:getnargs(2)

      -- after one arg, we always switch from moveto to lineto
      if currcmd == 'm' then currcmd = 'l' end
      if currcmd == 'M' then currcmd = 'L' end
    elseif  currcmd == 'z' or currcmd == 'Z' then
      -- no args
    elseif  currcmd == 'l' or currcmd == 'L' then
      cmdobj.args   = self:getnargs(2)
    elseif  currcmd == 'h' or currcmd == 'H' then
      cmdobj.args   = self:getnargs(1)
    elseif  currcmd == 'v' or currcmd == 'V' then
      cmdobj.args   = self:getnargs(1)
    elseif  currcmd == 'c' or currcmd == 'C' then
      cmdobj.args   = self:getnargs(6)
    elseif  currcmd == 's' or currcmd == 'S' then
      cmdobj.args   = self:getnargs(4)
    elseif  currcmd == 'q' or currcmd == 'Q' then
      cmdobj.args   = self:getnargs(4)
    elseif  currcmd == 't' or currcmd == 'T' then
      cmdobj.args   = self:getnargs(2)
    elseif  currcmd == 'a' or currcmd == 'A' then
      cmdobj.args   = self:getnargs(7)
    else
      print(self.k, #self.tokens, #currcmd)
      error("INTERNAL ERROR; LEXER SHOULD HAVE PREVENTED THIS BRANCH\n"..
            "  FOUND command character: "..tostring(currcmd))
    end
  end

  return cmdlist
end

-- Path Parsing
function SVGParser:parsePathData(str)
  local parser = NewPathParser(str)
  if not parser:lex() then
    -- compose a useful error message for where
    -- the lexing error was encountered
    local winsize = 10
    local pos = parser.err_position
    local min = math.max(1,pos-10)
    local max = math.min(pos+10,#str)
    local padding = string.rep(' ',pos-min)
    local patherr_ctxt = '  '..str:sub(min,max)..'\n  '..padding..'^'
    self:abort('error while lexing/parsing path string data @ position '..
               tostring(pos)..':\n'..patherr_ctxt)
    return nil
  end

  local cmdlist = parser:parsecommands()
  if self._verbose then
    for _,instr in ipairs(cmdlist) do
      self:print('',instr.cmd,unpack(instr.args))
    end
  end
  return cmdlist
end




-- returns two arguments
--  1: the tree representing the SVG file
--  2: a list of errors encountered during the parse
-- If 1 is nil, then the parse aborted
-- If 2 is nil, then there were no errors
function SVG.ParseSVG(filename, is_verbose)
  local parser = NewSVGParser(filename)
  if is_verbose then parser:makeVerbose() end
  parser:mainParse()
  local tree = parser:getResult()
  local errs = parser:hasErrors() and parser:getErrors() or nil
  return tree, errs
end







local function tbleq(a,b)
  local atyp, btyp = type(a), type(b)
  if atyp == 'table' and btyp == 'table' then
    -- run through table a and test b
    for ka,va in pairs(a) do
      if b[ka] == nil then return false end -- key sets must be eq
      if not tbleq(va, b[ka]) then return false end
    end
    -- also check to make sure every key in b is present in a
    for kb,vb in pairs(b) do
      if a[kb] == nil then return false end
    end
    return true -- looks good!
  else
    return a == b
  end
end

local function is_table(luaval)
  return type(luaval) == 'table'
end
local function is_list(luaval)
  if not is_table(luaval) then return false end
  local kcount = 0
  for _,_ in pairs(luaval) do kcount = kcount + 1 end
  return kcount == #luaval
end
local function stringify_string_value(str)
  str = string.gsub(str, "\\","\\\\")    -- slash
  str = string.gsub(str, "\'","\\\'")    -- single quote
  str = string.gsub(str, "\010","\\010") -- newline
  str = string.gsub(str, "\013","\\013") -- cariage-return
  return '\''..str..'\''
end
local function stringifyKey(keyval)
  local typ = type(keyval)
  if typ == 'string' then
    return stringify_string_value(keyval)
  elseif typ == 'boolean' or typ == 'number' then
    return tostring(keyval)
  else
    error('cannot stringify '..typ..' values as keys')
  end
end
local function stringifyPrimitiveVal(luaval)
  local typ = type(luaval)
  if typ == 'string' then
    return stringify_string_value(luaval)
  elseif typ == 'boolean' or typ == 'number' then
    return tostring(luaval)
  else
    error('cannot stringify '..typ..' values as primitives')
  end
end
local function stringifyTree(luaval, indent)
  indent = indent or ''
  if is_table(luaval) then
    if is_list(luaval) then     -- list
      -- peek at whether the first argument is a primitive
      local nl = ''
      if luaval[1] and is_table(luaval[1]) then nl = '\n'..indent end
      local str = '{'
      for i=1,#luaval do
        local substr = stringifyTree(luaval[i], indent..' ')
        str = str..nl..substr..','
      end
      str = str..'}'
      return str
    else                        -- table
      local str = '{'
      for k,v in pairs(luaval) do
        local keystr = stringifyKey(k)
        local valstr = stringifyTree(v, indent..' ')
        str = str..'\n'..indent..'['..keystr..']='..valstr..','
      end
      str = str..'}'
      return str
    end
  else                          -- value
    return stringifyPrimitiveVal(luaval)
  end
end


local function pathdataprint(data, indent)
  for _,instr in ipairs(data) do
    print(indent..instr.cmd, unpack(instr.args))
  end
end
local function treeprint(tbl, indent, parent)
  indent = indent or ''
  for k,v in pairs(tbl) do
    if type(v) == 'table' then
      if k == 'data' and tbl.type == 'path' then
        print(indent..tostring(k))
        pathdataprint(v, indent..' ')
      else
        print(indent..tostring(k))
        treeprint(v, indent..' ', tbl)
      end
    else
      print(indent..tostring(k), tostring(v))
    end
  end
end


local lscmd
if ffi.os == "Windows" then
  lscmd = "cmd /c dir /b /s"
else
  lscmd = "find . | cut -c 3-"
end

local fileskiplist = {
  ['testsvgs/diamond.svg'] = true,
  ['testsvgs/tablet-lg.svg'] = true,
}

local function RUN_TESTS()
  print('=============================')
  print('= Running SVG Parsing Tests =')
  print('=============================')
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
      local tree, errs = SVG.ParseSVG(filename)
      if errs then
        print('encountered errors during parse')
        for _,e in ipairs(errs) do print(e) end
      end
      if not tree then
        print('parser aborted, halting')
      else -- we have a tree!
        if out_file then
          local reffile = io.open(out_file)
          local ref_tree = assert(loadstring(reffile:read('*all')))()
          if not tbleq(ref_tree, tree) then
            print('ERROR: parser output did not match reference file tree')
          end
        end
      end
    end
  end
end

--RUN_TESTS()








