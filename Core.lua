-- XP Bar Plus: a customizable experience / reputation bar
-- Written for the 1.12 client (OctoWoW), Lua 5.0.

XPBarPlus = {}
local XBP = XPBarPlus
local ADDON = "XPBarPlus"
local MAXLEVEL = 60

XBP.textures = {
  { name = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
  { name = "Glossy",   path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
  { name = "Flat",     path = "Interface\\Buttons\\WHITE8X8" },
}

XBP.fonts = {
  { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
  { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
  { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
  { name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
}

XBP.presets = {
  "Lv [lvl]  -  [cur] / [max]  ([pct]){  -  [rested] rested}",
  "[cur] / [max]  ([pct])",
  "[pct]{  -  [restedpct] rested}",
  "[rem] to go  ([bars] bars){  -  [kills] kills}",
  "[cur] / [max]{  -  [xph] xp/h}{  -  level in [ttl]}",
  "Lv [lvl]  [pct]{  +[restedpct] rested}{  -  [xph]/h}{  -  [ttl]}",
}

XBP.defaults = {
  width = 1024, height = 12, scale = 1, alpha = 1,
  locked = false,
  texture = 1, ticks = 20,
  border = true, spark = true,
  mode = "auto",              -- auto | xp | rep
  showRested = true,          -- rested overlay
  restColor = true,           -- blue bar while rested
  repByStanding = true,
  hideBlizzard = false,
  tooltip = true,
  textMode = "always",        -- always | hover | never
  textPos = "center",         -- center | left | right | above | below
  font = 1, fontSize = 10, outline = true,
  shortNumbers = false,
  xpFormat = "Lv [lvl]  -  [cur] / [max]  ([pct]){  -  [rested] rested}",
  repFormat = "[name]: [standing]  -  [cur] / [max]  ([pct])",
  colors = {
    xp       = { 0.58, 0.0, 0.55, 1 },
    xpRested = { 0.0, 0.39, 0.88, 1 },
    rested   = { 0.25, 0.45, 1.0, 0.35 },
    rep      = { 0.0, 0.6, 0.1, 1 },
    bg       = { 0, 0, 0, 0.55 },
    border   = { 0, 0, 0, 1 },
    tick     = { 0, 0, 0, 0.6 },
    text     = { 1, 1, 1, 1 },
  },
}

local STANDING_COLORS = {
  [1] = { r = 0.8, g = 0.3, b = 0.22 }, [2] = { r = 0.8, g = 0.3, b = 0.22 },
  [3] = { r = 0.75, g = 0.27, b = 0 },  [4] = { r = 0.9, g = 0.7, b = 0 },
  [5] = { r = 0, g = 0.6, b = 0.1 },    [6] = { r = 0, g = 0.6, b = 0.1 },
  [7] = { r = 0, g = 0.6, b = 0.1 },    [8] = { r = 0, g = 0.6, b = 0.1 },
}

-- session stats (not saved)
local session = { start = nil, xp = 0, lastXP = nil, lastMax = nil, lastLevel = nil, lastKill = 0 }

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff9966ffXP Bar Plus:|r " .. msg)
end
XBP.Print = Print

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local function Commas(n)
  local s = tostring(math.floor(n + 0.5))
  local k
  while true do
    s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then break end
  end
  return s
end

local function Num(n)
  if XBP.db.shortNumbers then
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n + 0.5))
  end
  return Commas(n)
end
XBP.Num = Num

local function TimeText(s)
  s = math.floor(s)
  if s >= 3600 then
    return string.format("%dh %02dm", math.floor(s / 3600), math.floor(math.mod(s, 3600) / 60))
  elseif s >= 60 then
    return string.format("%dm", math.floor(s / 60))
  end
  return "<1m"
end

-- Replaces [token]s. Text inside { } is dropped when any token in it is empty.
local function FillFormat(fmt, v)
  local function sub(str)
    local empty = false
    local out = string.gsub(str, "%[(%a+)%]", function(tok)
      local val = v[string.lower(tok)]
      if val == nil then return "[" .. tok .. "]" end
      if val == "" then empty = true end
      return val
    end)
    return out, empty
  end
  local result = string.gsub(fmt, "{([^{}]*)}", function(group)
    local out, empty = sub(group)
    if empty then return "" end
    return out
  end)
  local out = sub(result)
  return out
end
XBP.FillFormat = FillFormat

----------------------------------------------------------------------
-- data
----------------------------------------------------------------------
function XBP:XPRate()
  if not session.start or session.xp <= 0 then return 0 end
  local elapsed = GetTime() - session.start
  if elapsed < 60 then return 0 end
  return session.xp / elapsed * 3600
end

function XBP:XPValues()
  local cur, max = UnitXP("player"), UnitXPMax("player")
  if not max or max <= 0 then max = 1 end
  local rest = GetXPExhaustion() or 0
  local rem = max - cur
  local rate = self:XPRate()
  local lvl = UnitLevel("player")
  return {
    cur = Num(cur), max = Num(max), rem = Num(rem),
    pct = string.format("%.1f%%", cur / max * 100),
    rested = rest > 0 and Num(rest) or "",
    restedpct = rest > 0 and string.format("%.0f%%", rest / max * 100) or "",
    lvl = tostring(lvl), nextlvl = tostring(lvl + 1),
    bars = string.format("%.1f", rem / max * 20),
    session = session.xp > 0 and Num(session.xp) or "",
    xph = rate > 0 and Num(rate) or "",
    ttl = rate > 0 and TimeText(rem / rate * 3600) or "",
    kills = session.lastKill > 0 and Commas(math.ceil(rem / session.lastKill)) or "",
  }, cur, max, rest
end

function XBP:RepValues()
  local name, reaction, minv, maxv, value = GetWatchedFactionInfo()
  if not name then return nil end
  local cur, max = value - minv, maxv - minv
  if max <= 0 then max = 1 end
  local standing = getglobal("FACTION_STANDING_LABEL" .. reaction) or "?"
  return {
    name = name, standing = standing,
    cur = Num(cur), max = Num(max), rem = Num(max - cur),
    pct = string.format("%.1f%%", cur / max * 100),
    lvl = tostring(UnitLevel("player")),
  }, cur, max, reaction
end

function XBP:CurrentMode()
  local watched = GetWatchedFactionInfo()
  local maxed = UnitLevel("player") >= MAXLEVEL
  local m = self.db.mode
  if m == "rep" then
    if watched then return "rep" end
    return maxed and "max" or "xp"
  elseif m == "xp" then
    return maxed and "max" or "xp"
  end
  if maxed then return watched and "rep" or "max" end
  return "xp"
end

----------------------------------------------------------------------
-- frames
----------------------------------------------------------------------
local f = CreateFrame("Frame", "XPBarPlusFrame", UIParent)
XBP.frame = f
f:SetWidth(1024); f:SetHeight(12)
f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 90)
f:SetMovable(true)
f:EnableMouse(true)
if f.SetClampedToScreen then f:SetClampedToScreen(true) end
f:RegisterForDrag("LeftButton")
f:Hide()

local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

local restBar = CreateFrame("StatusBar", nil, f)
restBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
restBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
restBar:SetFrameLevel(f:GetFrameLevel() + 1)

local bar = CreateFrame("StatusBar", nil, f)
bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
bar:SetFrameLevel(f:GetFrameLevel() + 2)

local over = CreateFrame("Frame", nil, f)
over:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
over:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
over:SetFrameLevel(f:GetFrameLevel() + 3)

local spark = over:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetBlendMode("ADD")
spark:SetWidth(12)

local borders = {}
for i = 1, 4 do borders[i] = over:CreateTexture(nil, "BORDER") end
borders[1]:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -1, 0)
borders[1]:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 1, 0)
borders[1]:SetHeight(1)
borders[2]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -1, 0)
borders[2]:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 1, 0)
borders[2]:SetHeight(1)
borders[3]:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0)
borders[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0)
borders[3]:SetWidth(1)
borders[4]:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
borders[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0)
borders[4]:SetWidth(1)

local ticks = {}

local text = over:CreateFontString(nil, "OVERLAY")
text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")

-- shown while unlocked
local moveHint = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
moveHint:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 4)
moveHint:SetText("XP Bar Plus: drag to move, right-click for options")
local moveGlow = over:CreateTexture(nil, "ARTWORK")
moveGlow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
moveGlow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
moveGlow:SetTexture(0.2, 1, 0.4, 0.25)

----------------------------------------------------------------------
-- layout
----------------------------------------------------------------------
function XBP:SavePosition()
  local x, y = f:GetCenter()
  if not x then return end
  self.db.x, self.db.y = x, y
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

function XBP:ApplyPosition()
  f:ClearAllPoints()
  if self.db.x and self.db.y then
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", self.db.x, self.db.y)
  else
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 90)
  end
end

function XBP:SetScaleKeepCenter(newScale)
  local old = f:GetScale()
  local x, y = f:GetCenter()
  f:SetScale(newScale)
  if x and self.db.x then
    self.db.x, self.db.y = x * old / newScale, y * old / newScale
  end
  self:ApplyPosition()
end

function XBP:CenterHorizontally()
  local _, y = f:GetCenter()
  if not y then return end
  self.db.x = UIParent:GetWidth() / 2 / f:GetScale()
  self.db.y = y
  self:ApplyPosition()
end

function XBP:FitScreenWidth()
  self.db.width = math.floor(UIParent:GetWidth() / f:GetScale())
  self:Layout()
  self:CenterHorizontally()
  self:Update()
end

local function SetColor(tex, c)
  tex:SetTexture(c[1], c[2], c[3], c[4] or 1)
end

local blizzHidden = false
local function HideBlizzard()
  if blizzHidden then return end
  blizzHidden = true
  local names = { "MainMenuExpBar", "ReputationWatchBar", "ExhaustionTick" }
  for _, name in ipairs(names) do
    local fr = getglobal(name)
    if fr then
      fr:Hide()
      fr:SetScript("OnShow", function() this:Hide() end)
    end
  end
end

function XBP:Layout()
  local db = self.db
  if math.abs(f:GetScale() - db.scale) > 0.001 then self:SetScaleKeepCenter(db.scale) end
  f:SetWidth(db.width)
  f:SetHeight(db.height)
  f:SetAlpha(db.alpha)

  local tex = (self.textures[db.texture] or self.textures[1]).path
  bar:SetStatusBarTexture(tex)
  restBar:SetStatusBarTexture(tex)
  local rc = db.colors.rested
  restBar:SetStatusBarColor(rc[1], rc[2], rc[3], rc[4])
  SetColor(bg, db.colors.bg)

  for i = 1, 4 do
    if db.border then
      SetColor(borders[i], db.colors.border)
      borders[i]:Show()
    else
      borders[i]:Hide()
    end
  end

  -- segment ticks
  local n = db.ticks
  for i = 1, math.max(n - 1, table.getn(ticks)) do
    local t = ticks[i]
    if i < n then
      if not t then
        t = over:CreateTexture(nil, "ARTWORK")
        ticks[i] = t
      end
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", f, "TOPLEFT", math.floor(db.width * i / n), 0)
      t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", math.floor(db.width * i / n), 0)
      t:SetWidth(1)
      SetColor(t, db.colors.tick)
      t:Show()
    elseif t then
      t:Hide()
    end
  end

  spark:SetHeight(math.max(db.height * 2.2, 16))

  local font = (self.fonts[db.font] or self.fonts[1]).path
  text:SetFont(font, db.fontSize, db.outline and "OUTLINE" or "")
  local tc = db.colors.text
  text:SetTextColor(tc[1], tc[2], tc[3], tc[4])
  text:ClearAllPoints()
  local pos = db.textPos
  if pos == "left" then
    text:SetPoint("LEFT", f, "LEFT", 4, 0); text:SetJustifyH("LEFT")
  elseif pos == "right" then
    text:SetPoint("RIGHT", f, "RIGHT", -4, 0); text:SetJustifyH("RIGHT")
  elseif pos == "above" then
    text:SetPoint("BOTTOM", f, "TOP", 0, 3); text:SetJustifyH("CENTER")
  elseif pos == "below" then
    text:SetPoint("TOP", f, "BOTTOM", 0, -3); text:SetJustifyH("CENTER")
  else
    text:SetPoint("CENTER", f, "CENTER", 0, 0); text:SetJustifyH("CENTER")
  end

  if db.locked then
    moveHint:Hide(); moveGlow:Hide()
  else
    moveHint:Show(); moveGlow:Show()
  end

  if db.hideBlizzard then HideBlizzard() end
  self:UpdateTextVisibility()
end

function XBP:UpdateTextVisibility()
  local m = self.db.textMode
  if m == "always" or (m == "hover" and self.hovering) then
    text:Show()
  else
    text:Hide()
  end
end

----------------------------------------------------------------------
-- update
----------------------------------------------------------------------
function XBP:Update()
  if not self.db then return end
  local db = self.db
  local mode = self:CurrentMode()
  self.mode = mode
  local value, max

  if mode == "xp" then
    local v, cur, mx, rest = self:XPValues()
    value, max = cur, mx
    local c = (db.restColor and GetRestState() == 1) and db.colors.xpRested or db.colors.xp
    bar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    if db.showRested and rest > 0 then
      restBar:SetMinMaxValues(0, mx)
      restBar:SetValue(math.min(cur + rest, mx))
      restBar:Show()
    else
      restBar:Hide()
    end
    text:SetText(FillFormat(db.xpFormat, v))
  elseif mode == "rep" then
    local v, cur, mx, reaction = self:RepValues()
    value, max = cur, mx
    local c = db.colors.rep
    if db.repByStanding then
      local sc = (FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]) or STANDING_COLORS[reaction]
      if sc then c = { sc.r, sc.g, sc.b, 1 } end
    end
    bar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    restBar:Hide()
    text:SetText(FillFormat(db.repFormat, v))
  else
    value, max = 1, 1
    local c = db.colors.xp
    bar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    restBar:Hide()
    text:SetText("Level " .. UnitLevel("player"))
  end

  bar:SetMinMaxValues(0, max)
  bar:SetValue(value)

  local frac = value / max
  if db.spark and frac > 0.002 and frac < 0.998 then
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", f, "LEFT", db.width * frac, 0)
    spark:Show()
  else
    spark:Hide()
  end

  if self.hovering then self:ShowTooltip() end
end

----------------------------------------------------------------------
-- tooltip
----------------------------------------------------------------------
function XBP:ShowTooltip()
  if not self.db.tooltip then return end
  local _, cy = f:GetCenter()
  GameTooltip:SetOwner(f, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  if cy and cy * f:GetScale() < UIParent:GetHeight() / 2 then
    GameTooltip:SetPoint("BOTTOM", f, "TOP", 0, 6)
  else
    GameTooltip:SetPoint("TOP", f, "BOTTOM", 0, -6)
  end

  local W, G = 1, 0.82
  if self.mode == "rep" then
    local v, cur, mx = self:RepValues()
    GameTooltip:AddLine(v.name)
    GameTooltip:AddDoubleLine("Standing", v.standing, G, G, G, W, W, W)
    GameTooltip:AddDoubleLine("Progress", v.cur .. " / " .. v.max .. "  (" .. v.pct .. ")", G, G, G, W, W, W)
    GameTooltip:AddDoubleLine("Remaining", v.rem, G, G, G, W, W, W)
  elseif self.mode == "xp" then
    local v, cur, mx, rest = self:XPValues()
    GameTooltip:AddLine("Experience")
    GameTooltip:AddDoubleLine("Level", v.lvl .. "  >  " .. v.nextlvl, G, G, G, W, W, W)
    GameTooltip:AddDoubleLine("Current", v.cur .. " / " .. v.max .. "  (" .. v.pct .. ")", G, G, G, W, W, W)
    GameTooltip:AddDoubleLine("Remaining", v.rem .. "  (" .. v.bars .. " bars)", G, G, G, W, W, W)
    if rest > 0 then
      GameTooltip:AddDoubleLine("Rested", v.rested .. "  (" .. v.restedpct .. " of level)", G, G, G, 0.4, 0.6, 1)
    else
      GameTooltip:AddDoubleLine("Rested", "none", G, G, G, 0.6, 0.6, 0.6)
    end
    if IsResting() then
      GameTooltip:AddLine("You are resting and earning rested XP.", 0.4, 0.6, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("This session", v.session ~= "" and v.session or "0", G, G, G, W, W, W)
    GameTooltip:AddDoubleLine("XP per hour", v.xph ~= "" and v.xph or "-", G, G, G, W, W, W)
    GameTooltip:AddDoubleLine("Time to level", v.ttl ~= "" and v.ttl or "-", G, G, G, W, W, W)
    if session.lastKill > 0 then
      GameTooltip:AddDoubleLine("Kills to level", v.kills .. "  (" .. Num(session.lastKill) .. " xp each)", G, G, G, W, W, W)
    end
  else
    GameTooltip:AddLine("Level " .. UnitLevel("player"))
    GameTooltip:AddLine("Watch a faction in the Reputation tab to track it here.", G, G, G, 1)
  end
  GameTooltip:AddLine(" ")
  if self.db.locked then
    GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
  else
    GameTooltip:AddLine("Drag to move. Right-click for options", 0.5, 0.5, 0.5)
  end
  GameTooltip:Show()
end

f:SetScript("OnEnter", function()
  XBP.hovering = true
  XBP:UpdateTextVisibility()
  XBP:ShowTooltip()
end)
f:SetScript("OnLeave", function()
  XBP.hovering = false
  XBP:UpdateTextVisibility()
  GameTooltip:Hide()
end)
f:SetScript("OnDragStart", function()
  if not XBP.db.locked then
    GameTooltip:Hide()
    this:StartMoving()
  end
end)
f:SetScript("OnDragStop", function()
  this:StopMovingOrSizing()
  XBP:SavePosition()
end)
f:SetScript("OnMouseUp", function()
  if arg1 == "RightButton" then XBP:ToggleOptions() end
end)

-- refresh the time-based tokens (xp/hour, time to level) now and then
local elapsedSince = 0
f:SetScript("OnUpdate", function()
  elapsedSince = elapsedSince + arg1
  if elapsedSince > 5 then
    elapsedSince = 0
    if XBP.mode == "xp" then XBP:Update() end
  end
end)

----------------------------------------------------------------------
-- session tracking
----------------------------------------------------------------------
function XBP:ResetSession()
  session.start = GetTime()
  session.xp = 0
  session.lastKill = 0
  session.lastXP = UnitXP("player")
  session.lastMax = UnitXPMax("player")
  session.lastLevel = UnitLevel("player")
end

local function TrackXP()
  local cur, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if session.lastXP and session.lastLevel then
    local gained
    if lvl > session.lastLevel then
      gained = (session.lastMax - session.lastXP) + cur
    else
      gained = cur - session.lastXP
    end
    if gained > 0 then session.xp = session.xp + gained end
  end
  session.lastXP, session.lastMax, session.lastLevel = cur, max, lvl
end

----------------------------------------------------------------------
-- events / slash
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("UPDATE_EXHAUSTION")
ev:RegisterEvent("PLAYER_UPDATE_RESTING")
ev:RegisterEvent("UPDATE_FACTION")
ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
ev:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    if type(XPBarPlusDB) ~= "table" then XPBarPlusDB = {} end
    CopyDefaults(XBP.defaults, XPBarPlusDB)
    XBP.db = XPBarPlusDB
    f:SetScale(XBP.db.scale)
    XBP:ApplyPosition()
    XBP:Layout()
    f:Show()
    return
  end
  if not XBP.db then return end
  if event == "PLAYER_ENTERING_WORLD" then
    if not session.start then XBP:ResetSession() end
    XBP:Layout()
  elseif event == "PLAYER_XP_UPDATE" then
    TrackXP()
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    if arg1 and string.find(arg1, "dies") then
      local _, _, xp = string.find(arg1, "gain (%d+) experience")
      if xp then session.lastKill = tonumber(xp) end
    end
  end
  XBP:Update()
end)

SLASH_XPBARPLUS1 = "/xpb"
SLASH_XPBARPLUS2 = "/xpbar"
SlashCmdList["XPBARPLUS"] = function(msg)
  msg = string.lower(msg or "")
  local _, _, cmd, rest = string.find(msg, "^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd or ""
  if cmd == "" or cmd == "config" or cmd == "options" then
    XBP:ToggleOptions()
  elseif cmd == "lock" or cmd == "unlock" then
    XBP.db.locked = (cmd == "lock")
    XBP:Layout()
    Print(XBP.db.locked and "bar locked." or "bar unlocked, drag it to move.")
  elseif cmd == "mode" and (rest == "xp" or rest == "rep" or rest == "auto") then
    XBP.db.mode = rest
    XBP:Update()
    local names = { auto = "Auto", xp = "Experience", rep = "Reputation" }
    Print("now showing: " .. names[rest] .. ".")
  elseif cmd == "session" then
    XBP:ResetSession(); XBP:Update()
    Print("session stats reset.")
  elseif cmd == "reset" then
    XBP:ResetAll()
    Print("all settings reset to defaults.")
  else
    Print("commands:")
    Print("/xpb - open the options window")
    Print("/xpb lock, /xpb unlock - lock or unlock the bar")
    Print("/xpb mode auto, xp or rep - what the bar shows")
    Print("/xpb session - reset xp/hour and kill tracking")
    Print("/xpb reset - restore every setting to default")
  end
end

function XBP:ResetAll()
  XPBarPlusDB = {}
  CopyDefaults(self.defaults, XPBarPlusDB)
  self.db = XPBarPlusDB
  f:SetScale(self.db.scale)
  self:ApplyPosition()
  self:Layout()
  self:Update()
  if self.RefreshOptions then self:RefreshOptions() end
end

function XBP:ApplyAll()
  self:Layout()
  self:Update()
end
