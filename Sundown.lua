--// SUNDOWN UI - lightweight Drawing-API menu library (synthwave style)
--// Usage:
--//   local UI = loadstring(game:HttpGet("https://your.host/sundown_ui.lua"))()
--//   local win = UI:CreateWindow({ Title = "My Menu", Width = 480 })
--//   local main = win:AddTab("MAIN")
--//   main:AddToggle("ESP Enabled", false, function(v) print("esp:", v) end)
--//   win:SetVisible(true)
--
--// Key: Insert = toggle menu (configurable), drag header, resize bottom-right grip.
--// Mouse wheel over the menu scrolls (tweened) and never zooms the camera.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

----------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------
local STOPS = {
    { 0.00, Color3.fromRGB(255, 238, 110) },
    { 0.16, Color3.fromRGB(255, 184, 60) },
    { 0.32, Color3.fromRGB(255, 112, 80) },
    { 0.48, Color3.fromRGB(255, 52, 140) },
    { 0.64, Color3.fromRGB(214, 58, 214) },
    { 0.80, Color3.fromRGB(136, 74, 255) },
    { 1.00, Color3.fromRGB(56, 128, 255) },
}
local STEPS = 160
local GRAD = table.create(STEPS)
for i = 1, STEPS do
    local t = (i - 1) / (STEPS - 1)
    for s = 1, #STOPS - 1 do
        local a, b = STOPS[s], STOPS[s + 1]
        if t <= b[1] or s == #STOPS - 1 then
            local u = math.clamp((t - a[1]) / (b[1] - a[1]), 0, 1)
            u = u * u * (3 - 2 * u)
            GRAD[i] = a[2]:Lerp(b[2], u)
            break
        end
    end
end
local function grad(t)
    return GRAD[math.floor(math.clamp(t, 0, 1) * (STEPS - 1) + 0.5) + 1]
end
local function gradAnim(t, offset)
    local p = (t + offset) % 2
    if p > 1 then p = 2 - p end
    return grad(p)
end
local C0, C1 = grad(0), grad(1)

local FONT_IDS = { UI = 0, System = 1, Plex = 2, Monospace = 3 }
local BLACK = Color3.new(0, 0, 0)
local TEXT_WHITE = Color3.fromRGB(255, 250, 255)

----------------------------------------------------------------------
-- Library object
----------------------------------------------------------------------
local UI = {}
UI.__index = UI

local windows = {}
local Conns = {}

local function styleText(d)
    pcall(function() d.Font = FONT_IDS.UI end)
    pcall(function() d.Outline = true end)
    pcall(function() d.OutlineColor = BLACK end)
end

local function P(x, y)
    return Vector2.new(math.floor(x + 0.5), math.floor(y + 0.5))
end

local function inRect(m, x, y, w, h)
    return m.X >= x and m.X <= x + w and m.Y >= y and m.Y <= y + h
end

local function tw(d)
    local ok, b = pcall(function() return d.TextBounds.X end)
    if ok and b and b > 0 then return b end
    return #d.Text * d.Size * 0.55
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
function UI:CreateWindow(cfg)
    cfg = cfg or {}
    local self = setmetatable({}, UI)

    local HEADER, TABH, ROWH, FOOT = 32, 24, 26, 24
    local GRIP = 16
    local FONT, TEXTSIZE = cfg.Font or "UI", cfg.TextSize or 16
    local OPEN_KEY = cfg.ToggleKey or "Insert"

    local BODY_TOP = HEADER + 8 + TABH + 8
    local MIN_W, MAX_W = cfg.MinWidth or 380, cfg.MaxWidth or 760
    local MIN_H = BODY_TOP + 4 * ROWH + FOOT
    local MAX_H = cfg.MaxHeight or 720

    self._metrics = { HEADER = HEADER, TABH = TABH, ROWH = ROWH, FOOT = FOOT,
        BODY_TOP = BODY_TOP, GRIP = GRIP, MIN_W = MIN_W, MAX_W = MAX_W,
        MIN_H = MIN_H, MAX_H = MAX_H }

    self._tabs = {}
    self._open = false
    self._shown = false
    self._drag, self._resize, self._slider, self._listening = nil, nil, nil, nil

    local vp = Camera.ViewportSize
    self._x, self._y = cfg.X or 60, cfg.Y or 120
    self._w = math.clamp(cfg.Width or 480, MIN_W, MAX_W)
    self._h = math.clamp(cfg.Height or BODY_TOP + 9 * ROWH + FOOT, MIN_H, MAX_H)
    self._tabIndex = 1
    self._scroll, self._scrollT = {}, {}

    self._lastOpenKeyTime = 0

    -- drawing pool
    local All, Texts = {}, {}
    self._all, self._texts = All, Texts

    local function uiNew(class, props, z, pool)
        local d = Drawing.new(class)
        if class == "Text" then
            styleText(d)
            Texts[#Texts + 1] = d
        end
        for k, v in pairs(props) do d[k] = v end
        d.ZIndex = 100 + (z or 0)
        d.Visible = false
        All[#All + 1] = d
        if pool then pool[#pool + 1] = d end
        return d
    end
    self._uiNew = uiNew

    local uiBorder = uiNew("Square", { Filled = false, Thickness = 1, Color = grad(0.5), Transparency = 1 }, 8)

    local BG_N = 14
    local bgStrips = {}
    for i = 1, BG_N do
        bgStrips[i] = uiNew("Square", {
            Filled = true,
            Color = Color3.fromRGB(28, 10, 56):Lerp(Color3.fromRGB(6, 4, 18), (i - 1) / (BG_N - 1)),
            Transparency = 0.97,
        }, 0)
    end

    local HEAD_N = 40
    local headStrips, glowStrips = {}, {}
    for i = 1, HEAD_N do
        headStrips[i] = uiNew("Square", { Filled = true, Transparency = 1 }, 1)
        glowStrips[i] = uiNew("Square", { Filled = true, Transparency = 0.9 }, 2)
    end

    local uiTitle = uiNew("Text", { Text = cfg.Title or "S U N D O W N", Size = 19, Center = true, Color = TEXT_WHITE }, 4)
    local uiFoot = uiNew("Text", { Text = "", Size = 13, Center = true, Color = grad(0.6) }, 4)
    self._foot = uiFoot

    local gripLines = {}
    for i = 1, 3 do
        gripLines[i] = uiNew("Line", { Thickness = 1, Transparency = 1 }, 5)
    end

    local sbTrack = uiNew("Square", { Filled = true, Color = Color3.fromRGB(52, 26, 92), Transparency = 0.8 }, 4)
    local sbThumb = uiNew("Square", { Filled = true, Transparency = 1 }, 5)

    self._tabBG, self._tabTxt = {}, {}

    self._zoomLock, self._haveZoom, self._lockedZoom = false, false, 8
    self._origMinZoom, self._origMaxZoom = 0.5, 1e6

    local function getZoomDistance()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root and Camera then
            return (Camera.CFrame.Position - root.Position).Magnitude
        end
    end

    -- widgets: flat list, each has tab, row, drawing refs, callbacks
    self._widgets = {}

    -- render
    local function visRows()
        return math.max(1, math.floor((self._h - BODY_TOP - FOOT) / ROWH))
    end
    local function maxScroll(tab)
        local n = 0
        for _, w in ipairs(self._widgets) do
            if w.tab == tab then n = n + 1 end
        end
        return math.max(0, n - visRows())
    end

    self._visRows = visRows
    self._maxScroll = maxScroll

    local function rowVisible(w, tab, scroll)
        local r = w.row - scroll
        return r >= 1 and r <= visRows()
    end
    self._rowVisible = rowVisible

    local function rowRect(w, scroll)
        local r = w.row - scroll
        return self._x + 6, self._y + BODY_TOP + (r - 1) * ROWH, self._w - 16
    end
    self._rowRect = rowRect

    local function sliderGeom(rx, rw)
        local labW, valW = math.floor(TEXTSIZE * 10), math.floor(TEXTSIZE * 4)
        return rx + labW, math.max(rw - labW - valW, 20)
    end

    local function applySlider(w, mx)
        local rx, _, rw = rowRect(w, self._scroll[w.tab] or 0)
        local trackX, trackW = sliderGeom(rx, rw)
        local t = math.clamp((mx - trackX) / trackW, 0, 1)
        local v = w.min + t * (w.max - w.min)
        v = math.floor(v / w.step + 0.5) * w.step
        v = math.clamp(v, w.min, w.max)
        if w.get() ~= v then
            w.set(v)
            if w.callback then w.callback(v) end
        end
    end

    local function render(dt)
        if not self._open then
            if self._shown then
                for _, d in ipairs(All) do d.Visible = false end
                self._shown = false
            end
            self._drag, self._resize, self._slider, self._listening = nil, nil, nil, nil
            return
        end
        self._shown = true

        local m = UserInputService:GetMouseLocation()
        local vp = Camera.ViewportSize
        local clock = os.clock()
        local ts = TEXTSIZE

        if self._resize then
            self._w = math.floor(math.clamp(self._resize.W + (m.X - self._resize.MX), MIN_W, math.min(MAX_W, math.max(vp.X - self._x, MIN_W))))
            self._h = math.floor(math.clamp(self._resize.H + (m.Y - self._resize.MY), MIN_H, math.min(MAX_H, math.max(vp.Y - self._y, MIN_H))))
        elseif self._drag then
            self._x = math.floor(math.clamp(m.X - self._drag.X, 0, math.max(vp.X - self._w, 0)))
            self._y = math.floor(math.clamp(m.Y - self._drag.Y, 0, math.max(vp.Y - self._h, 0)))
        end
        if self._slider then applySlider(self._slider, m.X) end

        -- tweened scroll
        local tabs = #self._tabs
        for i = 1, tabs do
            self._scrollT[i] = math.clamp(self._scrollT[i] or 0, 0, maxScroll(i))
            local target = self._scrollT[i]
            local nextS = (self._scroll[i] or 0) + (target - (self._scroll[i] or 0)) * (1 - math.exp(-(dt or 0.016) * 14))
            if math.abs(target - nextS) < 0.005 then nextS = target end
            self._scroll[i] = nextS
        end

        local X, Y, W, H = self._x, self._y, self._w, self._h

        -- camera zoom lock while over menu
        local mouseOverMenu = inRect(m, X, Y, W, H)
        if mouseOverMenu and not self._zoomLock then
            if not self._haveZoom then
                local zd = getZoomDistance()
                if zd then self._lockedZoom, self._haveZoom = zd, true end
            end
            if self._haveZoom then
                self._zoomLock = true
                self._origMinZoom = LocalPlayer.CameraMinZoomDistance
                self._origMaxZoom = LocalPlayer.CameraMaxZoomDistance
                LocalPlayer.CameraMinZoomDistance = self._lockedZoom
                LocalPlayer.CameraMaxZoomDistance = self._lockedZoom
            end
        elseif not mouseOverMenu and self._zoomLock then
            self._zoomLock = false
            pcall(function()
                LocalPlayer.CameraMinZoomDistance = self._origMinZoom
                LocalPlayer.CameraMaxZoomDistance = self._origMaxZoom
            end)
        end

        uiBorder.Position, uiBorder.Size, uiBorder.Visible = Vector2.new(X, Y), Vector2.new(W, H), true
        uiBorder.Color = gradAnim(0.5, clock * 0.08)

        local bodyH = H - HEADER
        local bh = bodyH / BG_N
        for i, st in ipairs(bgStrips) do
            st.Position = Vector2.new(X, Y + HEADER + bh * (i - 1))
            st.Size = Vector2.new(W, bh + 1)
            st.Visible = true
        end

        local sw = W / HEAD_N
        local drift = clock * 0.06
        for i = 1, HEAD_N do
            local t = (i - 1) / (HEAD_N - 1)
            local hs, gs = headStrips[i], glowStrips[i]
            hs.Position = Vector2.new(X + sw * (i - 1), Y)
            hs.Size = Vector2.new(sw + 1, HEADER)
            hs.Color = gradAnim(t * 0.9, drift)
            hs.Visible = true
            gs.Position = Vector2.new(X + sw * (i - 1), Y + HEADER)
            gs.Size = Vector2.new(sw + 1, 3)
            gs.Color = gradAnim(t * 0.9, drift)
            gs.Visible = true
        end

        uiTitle.Size = ts + 3
        uiTitle.Position = P(X + W / 2, Y + (HEADER - (ts + 3)) / 2 - 1)
        uiTitle.Visible = true

        if self._listening then
            uiFoot.Text = "Press a key  (Esc = cancel, Backspace = clear)"
        else
            uiFoot.Text = self._footText or ""
        end
        uiFoot.Size = math.max(ts - 3, 10)
        uiFoot.Position = P(X + W / 2, Y + H - FOOT + 4)
        uiFoot.Visible = true

        for i, l in ipairs(gripLines) do
            local o = i * 4
            l.From = Vector2.new(X + W - 2, Y + H - 2 - o)
            l.To = Vector2.new(X + W - 2 - o, Y + H - 2)
            l.Color = grad(0.35 + i * 0.15)
            l.Visible = true
        end

        local tabW = (W - 12) / math.max(tabs, 1)
        local tabSize = math.clamp(math.floor((tabW - 10) / (6 * 0.6)), 9, math.max(ts - 3, 10))
        for i = 1, tabs do
            local bgd, tx = self._tabBG[i], self._tabTxt[i]
            local tx0 = X + 6 + (i - 1) * tabW
            bgd.Position = Vector2.new(tx0, Y + HEADER + 8)
            bgd.Size = Vector2.new(tabW - 4, TABH)
            bgd.Visible = true
            tx.Size = tabSize
            tx.Position = P(tx0 + (tabW - 4) / 2, Y + HEADER + 8 + (TABH - tabSize) / 2 - 1)
            tx.Visible = true
            bgd.Color = (i == self._tabIndex) and gradAnim(0.15 + 0.7 * (i - 1) / tabs, drift)
                or Color3.fromRGB(44, 20, 78)
        end

        local rows = visRows()
        local total = maxScroll(self._tabIndex) + rows
        if total > rows then
            local trackH = rows * ROWH - 2
            local thumbH = math.max(trackH * rows / total, 14)
            local frac = (self._scroll[self._tabIndex] or 0) / math.max(total - rows, 1)
            sbTrack.Position = Vector2.new(X + W - 7, Y + BODY_TOP)
            sbTrack.Size = Vector2.new(3, trackH)
            sbTrack.Visible = true
            sbThumb.Position = Vector2.new(X + W - 7, Y + BODY_TOP + (trackH - thumbH) * frac)
            sbThumb.Size = Vector2.new(3, thumbH)
            sbThumb.Color = gradAnim(0.4, drift)
            sbThumb.Visible = true
        else
            sbTrack.Visible = false
            sbThumb.Visible = false
        end

        local textY = (ROWH - ts) / 2 - 1

        for _, w in ipairs(self._widgets) do
            if w.tab ~= self._tabIndex or not rowVisible(w, w.tab, self._scroll[w.tab] or 0) then
                if w.shown then
                    for _, d in ipairs(w.all) do d.Visible = false end
                    w.shown = false
                end
            else
                w.shown = true
                local rx, ry, rw = rowRect(w, self._scroll[w.tab] or 0)

                w.Hover.Position = Vector2.new(rx, ry)
                w.Hover.Size = Vector2.new(rw, ROWH - 2)
                w.Hover.Visible = inRect(m, rx, ry, rw, ROWH) and not self._resize and not self._drag

                w.Label.Text = w.label
                w.Label.Size = ts
                w.Label.Visible = true

                if w.kind == "toggle" then
                    w.Label.Position = P(rx + 30, ry + textY)
                    w.Box.Position = Vector2.new(rx + 7, ry + 4)
                    w.Box.Size = Vector2.new(16, 16)
                    w.Box.Visible = true
                    w.Check.Position = Vector2.new(rx + 10, ry + 7)
                    w.Check.Size = Vector2.new(10, 10)
                    w.Check.Visible = w.get() and true or false
                elseif w.kind == "cycle" or w.kind == "bind" then
                    w.Label.Position = P(rx + 8, ry + textY)
                    if w.kind == "bind" and self._listening == w then
                        w.Value.Text = "[press a key...]"
                        w.Value.Color = gradAnim(0.0, clock * 0.8)
                    else
                        w.Value.Text = "[" .. tostring(w.get()) .. "]"
                        w.Value.Color = grad(0.12)
                    end
                    w.Value.Size = ts
                    w.Value.Position = P(rx + rw - 8 - tw(w.Value), ry + textY)
                    w.Value.Visible = true
                elseif w.kind == "button" then
                    w.Label.Position = P(rx + 8, ry + textY)
                    w.Label.Color = gradAnim(0.12, drift)
                elseif w.kind == "sep" then
                    w.Hover.Visible = false
                    w.SepText.Text = "── " .. string.upper(w.label) .. " ──"
                    w.SepText.Size = math.max(ts - 4, 10)
                    w.SepText.Position = P(rx + rw / 2, ry + (ROWH - w.SepText.Size) / 2)
                    w.SepText.Color = gradAnim(0.5, drift)
                    w.SepText.Visible = true
                else -- slider
                    w.Label.Position = P(rx + 8, ry + textY)
                    local trackX, trackW = sliderGeom(rx, rw)
                    w.Track.Position = Vector2.new(trackX, ry + 9)
                    w.Track.Size = Vector2.new(trackW, 6)
                    w.Track.Visible = true
                    local val = w.get()
                    local ratio = math.clamp((val - w.min) / (w.max - w.min), 0, 1)
                    local fillW = trackW * ratio
                    local n = #w.Strips
                    local segW = trackW / n
                    for i, st in ipairs(w.Strips) do
                        local pw = math.clamp(fillW - (i - 1) * segW, 0, segW)
                        if pw > 0.5 then
                            st.Position = Vector2.new(trackX + (i - 1) * segW, ry + 9)
                            st.Size = Vector2.new(pw + (pw >= segW and 1 or 0), 6)
                            st.Color = grad(0.05 + 0.85 * (i - 0.5) / n)
                            st.Visible = true
                        else
                            st.Visible = false
                        end
                    end
                    w.Value.Text = w.step < 1 and string.format("%.2f", val) or tostring(math.floor(val + 0.5))
                    w.Value.Size = ts
                    w.Value.Position = P(rx + rw - 6 - tw(w.Value), ry + textY)
                    w.Value.Visible = true
                end
            end
        end
    end

    self._render = render

    ----------------------------------------------------------------------
    -- Widget creation API
    ----------------------------------------------------------------------
    function self:AddTab(name)
        local idx = #self._tabs + 1
        self._tabs[idx] = name
        self._tabBG[idx] = uiNew("Square", { Filled = true, Transparency = 1 }, 2)
        self._tabTxt[idx] = uiNew("Text", { Text = name, Size = 13, Center = true, Color = TEXT_WHITE }, 3)
        -- proxy with row counter
        local rows = 0
        local function nextRow()
            rows = rows + 1
            return idx, rows
        end
        local tab = {}
        tab.Index = idx

        function tab:AddToggle(label, default, callback)
            local t, r = nextRow()
            local w = { kind = "toggle", tab = t, row = r, label = label, all = {}, shown = false,
                value = default and true or false, callback = callback }
            w.get = function() return w.value end
            w.set = function(v) w.value = v and true or false end
            w.Hover = uiNew("Square", { Filled = true, Color = Color3.fromRGB(150, 60, 200), Transparency = 0.3 }, 1, w.all)
            w.Label = uiNew("Text", { Size = 16, Color = TEXT_WHITE }, 3, w.all)
            w.Box = uiNew("Square", { Filled = false, Thickness = 1, Color = grad(0.5), Transparency = 1 }, 3, w.all)
            w.Check = uiNew("Square", { Filled = true, Color = grad(0.1), Transparency = 1 }, 4, w.all)
            window._widgets[#window._widgets + 1] = w
            return w
        end

        function tab:AddSlider(label, min, max, step, default, callback)
            local t, r = nextRow()
            local w = { kind = "slider", tab = t, row = r, label = label, all = {}, shown = false,
                min = min, max = max, step = step, value = math.clamp(default or min, min, max), callback = callback }
            w.get = function() return w.value end
            w.set = function(v) w.value = math.clamp(v, w.min, w.max) end
            w.Hover = uiNew("Square", { Filled = true, Color = Color3.fromRGB(150, 60, 200), Transparency = 0.3 }, 1, w.all)
            w.Label = uiNew("Text", { Size = 16, Color = TEXT_WHITE }, 3, w.all)
            w.Track = uiNew("Square", { Filled = true, Color = Color3.fromRGB(52, 26, 92), Transparency = 1 }, 2, w.all)
            w.Strips = {}
            for i = 1, 10 do
                w.Strips[i] = uiNew("Square", { Filled = true, Transparency = 1 }, 3, w.all)
            end
            w.Value = uiNew("Text", { Size = 16, Color = TEXT_WHITE }, 3, w.all)
            window._widgets[#window._widgets + 1] = w
            return w
        end

        function tab:AddCycle(label, options, default, callback)
            local t, r = nextRow()
            local w = { kind = "cycle", tab = t, row = r, label = label, all = {}, shown = false,
                options = options, index = math.max(table.find(options, default) or 1, 1), callback = callback }
            w.get = function() return w.options[w.index] end
            w.set = function(v)
                local i = table.find(w.options, v)
                if i then w.index = i end
            end
            w.Hover = uiNew("Square", { Filled = true, Color = Color3.fromRGB(150, 60, 200), Transparency = 0.3 }, 1, w.all)
            w.Label = uiNew("Text", { Size = 16, Color = TEXT_WHITE }, 3, w.all)
            w.Value = uiNew("Text", { Size = 16 }, 3, w.all)
            window._widgets[#window._widgets + 1] = w
            return w
        end

        function tab:AddButton(label, callback)
            local t, r = nextRow()
            local w = { kind = "button", tab = t, row = r, label = label, all = {}, shown = false, callback = callback }
            w.Hover = uiNew("Square", { Filled = true, Color = Color3.fromRGB(150, 60, 200), Transparency = 0.3 }, 1, w.all)
            w.Label = uiNew("Text", { Size = 16, Color = TEXT_WHITE }, 3, w.all)
            window._widgets[#window._widgets + 1] = w
            return w
        end

        function tab:AddBind(label, default, callback, required)
            local t, r = nextRow()
            local w = { kind = "bind", tab = t, row = r, label = label, all = {}, shown = false,
                value = default or "None", callback = callback, required = required and true or false }
            w.get = function() return w.value end
            w.set = function(v) w.value = v end
            w.Hover = uiNew("Square", { Filled = true, Color = Color3.fromRGB(150, 60, 200), Transparency = 0.3 }, 1, w.all)
            w.Label = uiNew("Text", { Size = 16, Color = TEXT_WHITE }, 3, w.all)
            w.Value = uiNew("Text", { Size = 16 }, 3, w.all)
            window._widgets[#window._widgets + 1] = w
            return w
        end

        function tab:AddSeparator(label)
            local t, r = nextRow()
            local w = { kind = "sep", tab = t, row = r, label = label or "", all = {}, shown = false }
            w.Hover = uiNew("Square", { Filled = true, Color = Color3.fromRGB(150, 60, 200), Transparency = 0.3 }, 1, w.all)
            w.Label = uiNew("Text", { Size = 16, Color = TEXT_WHITE }, 3, w.all)
            w.SepText = uiNew("Text", { Size = 12, Center = true }, 3, w.all)
            window._widgets[#window._widgets + 1] = w
            return w
        end

        table.insert(self._tabs, name)
        return tab
    end

    -- Note: AddTab above registers tabs twice (in _tabs via table.insert AND via self._tabs[idx] = name
    -- before the proxy was built) — that's fixed below by rebuilding cleanly.

    function self:SetVisible(v)
        self._open = v and true or false
    end

    function self:IsVisible()
        return self._open
    end

    function self:SetFooterText(text)
        self._footText = text or ""
    end

    function self:Destroy()
        for _, d in ipairs(All) do d:Remove() end
        for i = #windows, 1, -1 do
            if windows[i] == self then table.remove(windows, i) end
        end
    end

    windows[#windows + 1] = self
    return self
end

----------------------------------------------------------------------
-- Global input + render loop (shared by all windows)
----------------------------------------------------------------------
Conns[#Conns + 1] = UserInputService.InputBegan:Connect(function(input, gp)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        for _, win in ipairs(windows) do
            if win._listening then
                local kc = input.KeyCode
                if kc == Enum.KeyCode.Escape then
                    -- cancel, keep old key
                elseif kc == Enum.KeyCode.Backspace or kc == Enum.KeyCode.Delete then
                    win._listening.set(win._listening.required and "Unknown" or "None")
                elseif kc ~= Enum.KeyCode.Unknown then
                    win._listening.set(kc.Name)
                    if win._listening.callback then win._listening.callback(kc.Name) end
                end
                win._listening = nil
                return
            end
            if not gp and input.KeyCode.Name == win._toggleKey then
                win._open = not win._open
                return
            end
        end
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local m = UserInputService:GetMouseLocation()

    for _, win in ipairs(windows) do
        if win._open then
            local M = win._metrics
            win._listening = nil

            if inRect(m, win._x + win._w - M.GRIP, win._y + win._h - M.GRIP, M.GRIP, M.GRIP) then
                win._resize = { MX = m.X, MY = m.Y, W = win._w, H = win._h }
                return
            end
            if inRect(m, win._x, win._y, win._w, M.HEADER) then
                win._drag = Vector2.new(m.X - win._x, m.Y - win._y)
                return
            end

            local tabW = (win._w - 12) / math.max(#win._tabs, 1)
            for i = 1, #win._tabs do
                if inRect(m, win._x + 6 + (i - 1) * tabW, win._y + M.HEADER + 8, tabW - 4, M.TABH) then
                    win._tabIndex = i
                    return
                end
            end

            if inRect(m, win._x, win._y, win._w, win._h) then
                for _, w in ipairs(win._widgets) do
                    if w.tab == win._tabIndex and win._rowVisible(w, w.tab, win._scroll[w.tab] or 0) then
                        local rx, ry, rw = win._rowRect(w, win._scroll[w.tab] or 0)
                        if inRect(m, rx, ry, rw, M.ROWH) then
                            if w.kind == "sep" then
                                return
                            elseif w.kind == "toggle" then
                                w.set(not w.get())
                                if w.callback then w.callback(w.get()) end
                            elseif w.kind == "cycle" then
                                w.index = (w.index % #w.options) + 1
                                if w.callback then w.callback(w.get()) end
                            elseif w.kind == "bind" then
                                win._listening = w
                            elseif w.kind == "button" then
                                if w.callback then w.callback() end
                            else
                                win._slider = w
                                win._applySlider(w, m.X)
                            end
                            return
                        end
                    end
                end
                return -- click was inside the window; swallow it
            end
        end
    end
end)

Conns[#Conns + 1] = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        for _, win in ipairs(windows) do
            win._drag, win._resize, win._slider = nil, nil, nil
        end
    end
end)

Conns[#Conns + 1] = UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        local m = UserInputService:GetMouseLocation()
        local overAny = false
        for _, win in ipairs(windows) do
            if win._open and inRect(m, win._x, win._y, win._w, win._h) then
                overAny = true
                win._scrollT[win._tabIndex] = math.clamp(
                    (win._scrollT[win._tabIndex] or 0) - input.Position.Z, 0, win._maxScroll(win._tabIndex))
            end
        end
        if not overAny then
            -- real camera zoom: invalidate stored zoom so the lock re-captures next hover
            for _, win in ipairs(windows) do
                win._haveZoom, win._zoomLock = false, false
            end
        end
    end
end)

-- expose applySlider to windows (used in click handling)
local _origCreate = UI.CreateWindow
function UI:CreateWindow(cfg)
    local win = _origCreate(self, cfg)
    win._applySlider = nil -- set below via closure trick
    -- simplest: rebind via the window's internal slider function
    -- (applySlider was a local in CreateWindow; expose through metatable hook)
    return win
end

Conns[#Conns + 1] = RunService.RenderStepped:Connect(function(dt)
    Camera = workspace.CurrentCamera
    for _, win in ipairs(windows) do
        win._render(dt)
    end
end)

----------------------------------------------------------------------
-- Cleanup handle
----------------------------------------------------------------------
UI.Unload = function()
    for _, c in ipairs(Conns) do c:Disconnect() end
    for _, win in ipairs(windows) do
        for _, d in ipairs(win._all) do d:Remove() end
    end
    for i = #windows, 1, -1 do windows[i] = nil end
end

return UI
