-- XP Bar Plus options window (/xpb)

local XBP = XPBarPlus
local panel
local refreshers = {}
local count = 0
local refreshing = false

local function NextName(kind)
  count = count + 1
  return "XPBarPlusOpt" .. kind .. count
end

local function Header(parent, label, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(label)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetTexture(1, 0.82, 0, 0.25)
  line:SetHeight(1)
  line:SetWidth(270)
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
  return fs
end

local function Check(parent, label, key, x, y, onChange)
  local name = NextName("Check")
  local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  cb:SetWidth(24); cb:SetHeight(24)
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  getglobal(name .. "Text"):SetText(label)
  cb:SetScript("OnClick", function()
    XBP.db[key] = this:GetChecked() and true or false
    if onChange then onChange(XBP.db[key]) end
    XBP:ApplyAll()
  end)
  table.insert(refreshers, function() cb:SetChecked(XBP.db[key] and 1 or nil) end)
  return cb
end

local function Slider(parent, label, key, minv, maxv, step, x, y, width)
  local name = NextName("Slider")
  local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  s:SetWidth(width or 250)
  s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  s:SetMinMaxValues(minv, maxv)
  s:SetValueStep(step)
  getglobal(name .. "Low"):SetText(minv)
  getglobal(name .. "High"):SetText(maxv)
  local title = getglobal(name .. "Text")
  local function show(v)
    if step < 1 then
      title:SetText(label .. ": " .. string.format("%.2f", v))
    else
      title:SetText(label .. ": " .. v)
    end
  end
  s:SetScript("OnValueChanged", function()
    if refreshing then show(XBP.db[key]); return end
    local v = math.floor(this:GetValue() / step + 0.5) * step
    if step >= 1 then v = math.floor(v + 0.5) end
    show(v)
    if XBP.db[key] ~= v then
      XBP.db[key] = v
      XBP:ApplyAll()
    end
  end)
  table.insert(refreshers, function() s:SetValue(XBP.db[key]); show(XBP.db[key]) end)
  return s
end

local function Cycle(parent, label, key, options, x, y, width)
  local b = CreateFrame("Button", NextName("Cycle"), parent, "UIPanelButtonTemplate")
  b:SetWidth(width or 250); b:SetHeight(22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local function index()
    for i = 1, table.getn(options) do
      if options[i][1] == XBP.db[key] then return i end
    end
    return 1
  end
  local function refresh() b:SetText(label .. ": " .. options[index()][2]) end
  b:SetScript("OnClick", function()
    local i, n = index(), table.getn(options)
    if arg1 == "RightButton" then
      i = i - 1; if i < 1 then i = n end
    else
      i = i + 1; if i > n then i = 1 end
    end
    XBP.db[key] = options[i][1]
    refresh()
    XBP:ApplyAll()
  end)
  table.insert(refreshers, refresh)
  return b
end

local function Button(parent, label, x, y, width, onClick)
  local b = CreateFrame("Button", NextName("Button"), parent, "UIPanelButtonTemplate")
  b:SetWidth(width or 120); b:SetHeight(22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function OpenColorPicker(c, hasAlpha, onChange)
  local pr, pg, pb, pa = c[1], c[2], c[3], c[4] or 1
  ColorPickerFrame:Hide()
  ColorPickerFrame.func = nil
  ColorPickerFrame.opacityFunc = nil
  ColorPickerFrame.cancelFunc = nil
  ColorPickerFrame.hasOpacity = hasAlpha
  ColorPickerFrame.opacity = 1 - pa
  ColorPickerFrame:SetColorRGB(pr, pg, pb)
  local function apply()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    c[1], c[2], c[3] = r, g, b
    if hasAlpha then c[4] = 1 - OpacitySliderFrame:GetValue() end
    onChange()
  end
  ColorPickerFrame.func = apply
  ColorPickerFrame.opacityFunc = apply
  ColorPickerFrame.cancelFunc = function()
    c[1], c[2], c[3], c[4] = pr, pg, pb, pa
    onChange()
  end
  ColorPickerFrame:Show()
end

local function Swatch(parent, label, ckey, hasAlpha, x, y)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(130); b:SetHeight(18)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local edge = b:CreateTexture(nil, "BACKGROUND")
  edge:SetWidth(18); edge:SetHeight(18)
  edge:SetPoint("LEFT", b, "LEFT", 0, 0)
  edge:SetTexture(0.8, 0.8, 0.8, 1)
  local check = b:CreateTexture(nil, "BORDER") -- dark backing so alpha is visible
  check:SetWidth(16); check:SetHeight(16)
  check:SetPoint("LEFT", b, "LEFT", 1, 0)
  check:SetTexture(0.1, 0.1, 0.1, 1)
  local sw = b:CreateTexture(nil, "ARTWORK")
  sw:SetWidth(16); sw:SetHeight(16)
  sw:SetPoint("LEFT", b, "LEFT", 1, 0)
  local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", b, "LEFT", 24, 0)
  fs:SetText(label)
  local function refresh()
    local c = XBP.db.colors[ckey]
    sw:SetTexture(c[1], c[2], c[3], c[4] or 1)
  end
  b:SetScript("OnClick", function()
    OpenColorPicker(XBP.db.colors[ckey], hasAlpha, function() refresh(); XBP:ApplyAll() end)
  end)
  b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1) end)
  table.insert(refreshers, refresh)
  return b
end

local function FormatBox(parent, label, key, x, y, width)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 4)
  fs:SetText(label)
  local eb = CreateFrame("EditBox", NextName("Edit"), parent, "InputBoxTemplate")
  eb:SetWidth(width); eb:SetHeight(20)
  eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 40, y)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(255)
  eb:SetScript("OnEnterPressed", function()
    XBP.db[key] = this:GetText()
    this:ClearFocus()
    XBP:ApplyAll()
  end)
  eb:SetScript("OnEscapePressed", function()
    this:SetText(XBP.db[key])
    this:ClearFocus()
  end)
  table.insert(refreshers, function() eb:SetText(XBP.db[key]) end)
  return eb
end

local function Build()
  panel = CreateFrame("Frame", "XPBarPlusOptions", UIParent)
  panel:SetWidth(620); panel:SetHeight(640)
  panel:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  panel:SetFrameStrata("HIGH")
  panel:SetToplevel(true)
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function() this:StartMoving() end)
  panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  table.insert(UISpecialFrames, "XPBarPlusOptions")

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", panel, "TOP", 0, -18)
  title:SetText("XP Bar Plus")

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)

  -- left column: the bar
  local L, R = 24, 326
  Header(panel, "Bar", L, -46)
  Slider(panel, "Width", "width", 50, 4000, 1, L + 6, -80)
  Slider(panel, "Height", "height", 2, 40, 1, L + 6, -118)
  Slider(panel, "Scale", "scale", 0.5, 2, 0.05, L + 6, -156)
  Slider(panel, "Opacity", "alpha", 0.1, 1, 0.05, L + 6, -194)
  Slider(panel, "Segments (0 = none)", "ticks", 0, 40, 1, L + 6, -232)
  local tex = {}
  for i = 1, table.getn(XBP.textures) do tex[i] = { i, XBP.textures[i].name } end
  Cycle(panel, "Texture", "texture", tex, L + 6, -266)
  Cycle(panel, "Shows", "mode", {
    { "auto", "Auto (XP, rep at 60)" }, { "xp", "Experience" }, { "rep", "Watched reputation" },
  }, L + 6, -292)

  Check(panel, "Lock position", "locked", L, -322)
  Check(panel, "Border", "border", L, -344)
  Check(panel, "Spark at the fill edge", "spark", L, -366)
  Check(panel, "Show rested XP overlay", "showRested", L, -388)
  Check(panel, "Use rested color while rested", "restColor", L, -410)
  Check(panel, "Color reputation by standing", "repByStanding", L, -432)
  Check(panel, "Tooltip on mouseover", "tooltip", L, -454)
  Check(panel, "Hide Blizzard XP / rep bars", "hideBlizzard", L, -476, function(on)
    if not on then XBP.Print("type /reload to bring the Blizzard bars back.") end
  end)

  -- right column: text and colors
  Header(panel, "Text", R, -46)
  Cycle(panel, "Show text", "textMode", {
    { "always", "Always" }, { "hover", "On mouseover" }, { "never", "Never" },
  }, R, -70)
  Cycle(panel, "Position", "textPos", {
    { "center", "Center" }, { "left", "Left" }, { "right", "Right" }, { "above", "Above" }, { "below", "Below" },
  }, R, -96)
  local fonts = {}
  for i = 1, table.getn(XBP.fonts) do fonts[i] = { i, XBP.fonts[i].name } end
  Cycle(panel, "Font", "font", fonts, R, -122)
  Slider(panel, "Font size", "fontSize", 6, 24, 1, R + 6, -160)
  Check(panel, "Outline", "outline", R, -186)
  Check(panel, "Short numbers (12.3k)", "shortNumbers", R + 130, -186)

  Header(panel, "Colors", R, -218)
  Swatch(panel, "Experience", "xp", false, R, -240)
  Swatch(panel, "Rested experience", "xpRested", false, R + 140, -240)
  Swatch(panel, "Rested overlay", "rested", true, R, -262)
  Swatch(panel, "Reputation", "rep", false, R + 140, -262)
  Swatch(panel, "Background", "bg", true, R, -284)
  Swatch(panel, "Border", "border", true, R + 140, -284)
  Swatch(panel, "Segments", "tick", true, R, -306)
  Swatch(panel, "Text", "text", false, R + 140, -306)

  Header(panel, "Placement", R, -340)
  Button(panel, "Center horizontally", R, -364, 130, function() XBP:CenterHorizontally() end)
  Button(panel, "Fit screen width", R + 140, -364, 130, function()
    XBP:FitScreenWidth()
    XBP:RefreshOptions()
  end)

  Header(panel, "Stats", R, -400)
  Button(panel, "Reset session", R, -424, 130, function()
    XBP:ResetSession(); XBP:Update()
    XBP.Print("session stats reset.")
  end)
  Button(panel, "Reset everything", R + 140, -424, 130, function()
    XBP:ResetAll()
    XBP.Print("all settings reset to defaults.")
  end)

  -- bottom: format strings
  Header(panel, "Text format  (press Enter to apply)", L, -512)
  local presetIndex = 0
  Button(panel, "Next preset", 476, -506, 120, function()
    presetIndex = presetIndex + 1
    if presetIndex > table.getn(XBP.presets) then presetIndex = 1 end
    XBP.db.xpFormat = XBP.presets[presetIndex]
    XBP:ApplyAll()
    XBP:RefreshOptions()
  end)
  FormatBox(panel, "XP", "xpFormat", L, -534, 520)
  FormatBox(panel, "Rep", "repFormat", L, -558, 520)

  local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", panel, "TOPLEFT", L, -586)
  help:SetWidth(572)
  help:SetJustifyH("LEFT")
  help:SetText("|cffffd100XP:|r [cur] [max] [rem] [pct] [rested] [restedpct] [lvl] [nextlvl] [bars] [session] [xph] [ttl] [kills]" ..
    "\n|cffffd100Rep:|r [name] [standing] [cur] [max] [rem] [pct]" ..
    "    Text inside { } is hidden while a token in it is empty.")

  panel:SetScript("OnShow", function() XBP:RefreshOptions() end)
  panel:Hide()
end

function XBP:RefreshOptions()
  if not panel then return end
  refreshing = true
  for i = 1, table.getn(refreshers) do refreshers[i]() end
  refreshing = false
end

function XBP:ToggleOptions()
  if not panel then Build() end
  if panel:IsShown() then panel:Hide() else panel:Show() end
end
