--
--  demo.t
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


SDL     = require 'SDL'
RawGUI  = require 'rawgui'
ConsoleWidget = require 'consolewidget'
P       = require 'primitives'

local AssortedWidgets = require 'assortedwidgets'


Label         = AssortedWidgets.Label
SignalMonitor = AssortedWidgets.SignalMonitor
Panel         = AssortedWidgets.Panel
ViewPanel     = AssortedWidgets.ViewPanel
Button        = AssortedWidgets.Button
ToggleButton  = AssortedWidgets.ToggleButton
Slider        = AssortedWidgets.Slider


local Viewport = require 'viewport'













local function FrameTimeGraph(box, layer)
  if not P.isBox(box) then
    box = P.NewBox(box)
  end

  local gray = { r=127, g=127, b=127, a=127 }
  local label = Label.New {
    text='ms/frame',
    pos = box:rt(),
    bold = true,
    textcolor = gray,
  }
  local textw = label:getPxBox().w
  label:setPos(P.NewVecUnsafe(box.r - textw, box.t))
  layer:AddWidgetAtFront(label)

  local monitor = SignalMonitor.New {
    pxbox       = box,
    linecolor   = gray,
    textcolor   = gray,
  }
  monitor:setMinMax(0, 60)
  monitor:onDraw(function()
    local frametime = RawGUI.GetLastDrawTime()
    if frametime then monitor:addSample(1.0e3 * frametime) end
  end)
  layer:AddWidgetAtFront(monitor)

  return {monitor=monitor, label=label}
end

fpsgraph = nil
console = nil
panel = nil
button = nil
toggle = nil
slider = nil
view   = nil
mainLayer       = RawGUI.NewLayer()
consoleOverlay  = RawGUI.NewLayer()
console_is_up   = true
RawGUI.onSetup(function()
  -- slightly gray background
  RawGUI.setClearColor(P.NewColor(223,223,223))

  -- setup layers
  RawGUI.AddWidgetAtFront(mainLayer)
  RawGUI.AddWidgetAtFront(consoleOverlay)

  -- console and sizing
  local h = 250
  local y = 30
  console = ConsoleWidget.New {
    pxbox   = { l=0,t=0,w=420,h=h },
    padding = 10,
    backcolor = {r=15,g=15,b=31,a=191},
  }
  local w = console:getWidthForNChars(80)
  console:setPxBox { l=0, t=0, w=w, h=h }

  -- console comes equipped with a boilerplate evaluator
  console:onExecute(ConsoleWidget.DefaultLuaTerraEval)
  consoleOverlay:AddWidgetAtFront(console)
  -- clear key focus if a click isn't captured
  RawGUI.onEvent('MOUSEDOWN', function(ev)
    console:ReleaseKeyFocus()
  end)
  RawGUI.onEvent('KEYDOWN', function(ev)
    if ev.key == 'Escape' then
      if console_is_up then
        consoleOverlay:RemoveWidget(console)
        console:ReleaseKeyFocus()
        console:ReleaseMouseFocus()
      else
        consoleOverlay:AddWidgetAtFront(console)
        console:GrabKeyFocus()
      end
      console_is_up = not console_is_up
    end
  end)



  fpsgraph = FrameTimeGraph({ l=30, t=y+60, w=120, h=60 }, mainLayer)

  local x = 180
  panel = Panel.New { pxbox = { l=x, t=y+60, w=60, h=60 },
                      fillcolor = {r=192,g=127,b=127},
                      strokecolor = {r=127,g=127,b=127},
                    }
  mainLayer:AddWidgetAtFront(panel)
  x = x + 90

  button = Button.New { pxbox = { l=x, t=y+60, w=60, h=60 } }
  button:onPress(function() print('button pressed') end)
  mainLayer:AddWidgetAtFront(button)
  x = x + 90

  toggle = ToggleButton.New { pxbox = { l=x, t=y+60, w=60, h=60 } }
  toggle:onToggle(function(val) print('toggled to ', val) end)
  mainLayer:AddWidgetAtFront(toggle)
  x = x + 90

  slider = Slider.New { pxbox = { l=x, t =y+60, w=22, h = 90 }}
  slider:onDragStart(function(new,old) slider:setValue(new) end)
  slider:onDragMove(function(new,old) slider:setValue(new) end)
  mainLayer:AddWidgetAtFront(slider)
  x = x + 22

  y = y + 90 + 30
  x = 30

  view = Viewport.New { pxbox = { l=x, t=y+240, w=320, h=240} }
  view.drawScene  = function() end
  view.route      = function() end
  mainLayer:AddWidgetAtFront(view)
  y = y + 240 + 30

  RawGUI.GetMainWindow():setMinWH(w, math.max(y,h))

end)

RawGUI.StartLoop {
  winargs = {
    resizable = true,
    minw = 100,
    minh = 100,
    noborder = true,
  },
}



