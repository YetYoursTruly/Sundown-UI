--// SUNDOWN UI Showcase - demonstrates every widget, no real functionality
--// Every callback just prints. Toggle the menu with Insert.

local SundownUI
do
    -- Option A: load from local executor workspace
    SundownUI = loadstring(readfile("SUNDOWN/sundown_ui.lua"))()

    -- Option B (if hosted): uncomment this instead
    -- SundownUI = loadstring(game:HttpGet("https://your.host/sundown_ui.lua"))()
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local win = SundownUI:CreateWindow({
    Title = "SUNDOWN SHOWCASE",
    ToggleKey = "Insert",   -- open/close the menu
    X = 80, Y = 100,
    Width = 480,
})

win:SetFooterText("Insert = menu   Everything here just prints")
win:SetVisible(true)

----------------------------------------------------------------------
-- MAIN tab: one of each widget type
----------------------------------------------------------------------
local main = win:AddTab("MAIN")

main:AddSeparator("Widgets")

local infoToggle = main:AddToggle("Example Toggle", false, function(v)
    print("[showcase] toggle:", v)
end)

main:AddSlider("Example Slider", 0, 100, 1, 50, function(v)
    print("[showcase] slider:", v)
end)

main:AddCycle("Example Cycle", { "Option A", "Option B", "Option C" }, "Option A", function(v)
    print("[showcase] cycle:", v)
end)

main:AddButton("> Example Button", function()
    print("[showcase] button clicked!")
end)

main:AddBind("Example Bind", "V", function(key)
    print("[showcase] bind set to:", key)
end)

----------------------------------------------------------------------
-- VISUAL tab: sliders of different ranges/steps + state reading
----------------------------------------------------------------------
local visual = win:AddTab("VISUAL")

visual:AddSeparator("Sliders")

visual:AddSlider("Float Slider", 0, 1, 0.05, 0.25, function(v)
    print("[showcase] float slider:", string.format("%.2f", v))
end)

visual:AddSlider("Big Range", 100, 5000, 50, 2000, function(v)
    print("[showcase] big slider:", v)
end)

visual:AddSeparator("Live State")

local stateLabel = visual:AddToggle("Watch The Console", true, function(v)
    print("[showcase] toggle:", v)
end)

-- every widget returns its object; read/write state anytime:
task.spawn(function()
    while SundownUI ~= nil do
        task.wait(5)
        if win:IsVisible() then
            print(string.format("[showcase] current state -> toggle: %s, slider: %s, cycle: %s, bind: %s",
                tostring(stateLabel.get()), tostring(infoToggle.get()), "n/a", "n/a"))
        end
    end
end)

----------------------------------------------------------------------
-- EXTRA tab: separator + button spam, shows scrolling
----------------------------------------------------------------------
local extra = win:AddTab("EXTRA")

extra:AddSeparator("Scroll Me")

for i = 1, 12 do
    extra:AddButton("> Row " .. i, function()
        print("[showcase] row button", i)
    end)
end

----------------------------------------------------------------------
-- MISC tab: cleanup demo
----------------------------------------------------------------------
local misc = win:AddTab("MISC")

misc:AddSeparator("Library")

misc:AddButton("> Unload Showcase + UI", function()
    print("[showcase] unloading...")
    SundownUI.Unload()
    SundownUI = nil
end)

print("[showcase] loaded - press Insert to toggle the menu")
