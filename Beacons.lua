-- Beacons: eligibility of the player as a teleport destination.
local ADDON, ns = ...

-- Spell id of the aura applied by a sleeping bag.
local SLEEPING_BAG_AURA = 1331671

local function Known(v)
  return not (issecretvalue and issecretvalue(v))
end

-- Returns true when the player has the aura with the given spell id.
-- Returns nil when the aura list cannot be read.
local function HasAura(spellId)
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not data then return false end
      if not Known(data.spellId) then return nil end
      if data.spellId == spellId then return true end
    end
    return false
  elseif UnitBuff then
    for i = 1, 40 do
      local name, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
      if not name then return false end
      if not Known(id) then return nil end
      if id == spellId then return true end
    end
    return false
  end
  return nil
end

-- Returns eligible (boolean) and a reason code:
-- "ok", "not_resting", "sleeping_bag", "unknown".
function ns.BeaconEligible()
  local resting = IsResting()
  if not Known(resting) then return false, "unknown" end
  if not resting then return false, "not_resting" end
  local bag = HasAura(SLEEPING_BAG_AURA)
  if bag == nil then return false, "unknown" end
  if bag then return false, "sleeping_bag" end
  return true, "ok"
end

-- Beacon protocol: hidden addon whispers.
-- "Q" asks a player whether they are an active beacon; "R" confirms.
-- "J" asks an active beacon to invite the sender; only valid shortly after an "R".
-- Players that are not active beacons never reply.
local PREFIX = "IHBEACON"
local QUERY_TIMEOUT = 3
local REPLY_COOLDOWN = 2
local REPLY_CAP = 30
local REPLY_WINDOW = 10
local JOIN_WINDOW = 60
local STORE_LIMIT = 100
local MAX_PARTY = 5
local SCAN_LIMIT = 50
local SCAN_TICK = 0.25
local SCAN_PER_TICK = 2
local SCAN_MAX_TIME = 30
local THROTTLE_BACKOFF = 1
local CACHE_TTL = 30
local THROTTLED = (Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle) or 3

local registerPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local sendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if registerPrefix then registerPrefix(PREFIX) end

local MODES = { on = true, off = true }
local pending = {}
local quiet = {}
local windowStart, windowCount = 0, 0

local function Trace(text)
  if ns.Dbg then ns.Dbg("beacon: " .. text) end
end

local function Key(name)
  return string.lower(Ambiguate(name, "none"))
end

-- Bounded key/value store; cleared when the entry limit is exceeded.
local function NewStore()
  return { n = 0, t = {} }
end

local function StoreSet(store, key, value)
  if store.t[key] == nil then
    store.n = store.n + 1
    if store.n > STORE_LIMIT then
      wipe(store.t)
      store.n = 1
    end
  end
  store.t[key] = value
end

local lastReply = NewStore()
local answered = NewStore()

-- "auto" is the stored value of earlier builds and means on; any other value means off.
local function NormalizeMode(mode)
  if mode == "auto" then return "on" end
  return MODES[mode] and mode or "off"
end

local listeners = {}

-- Registers fn to be called whenever the beacon mode or its settings change.
function ns.OnBeaconChange(fn)
  table.insert(listeners, fn)
end

local function NotifyMode()
  if ns.BeaconButtonUpdate then ns.BeaconButtonUpdate() end
  for _, fn in ipairs(listeners) do fn() end
end

function ns.GetBeaconConfirm()
  return not (QuickTeleportDB and QuickTeleportDB.beaconConfirm == false)
end

function ns.SetBeaconConfirm(on)
  QuickTeleportDB.beaconConfirm = on and true or false
  NotifyMode()
end

function ns.GetBeaconButtonShown()
  return not (QuickTeleportDB and QuickTeleportDB.beaconButtonShown == false)
end

function ns.SetBeaconButtonShown(on)
  QuickTeleportDB.beaconButtonShown = on and true or false
  NotifyMode()
end

function ns.GetBeaconMode()
  return NormalizeMode(QuickTeleportDB and QuickTeleportDB.beaconMode)
end

function ns.GetBeaconAutoInvite()
  return not (QuickTeleportDB and QuickTeleportDB.beaconAutoInvite == false)
end

function ns.SetBeaconAutoInvite(on)
  QuickTeleportDB.beaconAutoInvite = on and true or false
  NotifyMode()
end

function ns.SetBeaconMode(mode)
  mode = NormalizeMode(mode)
  QuickTeleportDB.beaconMode = mode
  NotifyMode()
  return true
end

-- A ticked "Remember my choice" disables the dialog; the setting can be restored in the options.
local function RememberChoice(dialog)
  if dialog and dialog.ihRemember and dialog.ihRemember:GetChecked() then
    QuickTeleportDB.beaconConfirm = false
  end
end

-- Consent dialog shown when beacon mode is switched on.
StaticPopupDialogs["INNHOPPER_BEACON"] = {
  text = "Beacon mode answers requests from other InnHopper players. Unless you choose otherwise, "
    .. "players who ask to join are invited to your party automatically until it is full.\n\n"
    .. "Your zone is shared with InnHopper players who use the beacon overview.\n\n"
    .. "This can be changed at any time.",
  button1 = "Enable",
  button2 = CANCEL,
  button3 = "Without auto-invite",
  OnShow = function(self)
    if not self.ihRemember then
      local cb = CreateFrame("CheckButton", nil, self, "UICheckButtonTemplate")
      cb:SetSize(24, 24)
      cb.text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
      cb.text:SetText("Remember my choice")
      self.ihRemember = cb
    end
    self.ihRemember:SetChecked(false)
    self.ihRemember:ClearAllPoints()
    self.ihRemember:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 24, 46)
    self.ihRemember:Show()
    self:SetHeight(self:GetHeight() + 28)
  end,
  OnHide = function(self)
    if self.ihRemember then self.ihRemember:Hide() end
  end,
  OnAccept = function(self, data)
    RememberChoice(self)
    ns.SetBeaconAutoInvite(true)
    ns.SetBeaconMode(data.mode)
    if data.done then data.done(true) end
  end,
  OnAlt = function(self, data)
    RememberChoice(self)
    ns.SetBeaconAutoInvite(false)
    ns.SetBeaconMode(data.mode)
    if data.done then data.done(true) end
  end,
  OnCancel = function(_, data)
    if data.done then data.done(false) end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- Changes the mode. Switching from off to an active mode requires consent.
-- done(changed) is called once the outcome is known.
function ns.RequestBeaconMode(mode, done)
  mode = NormalizeMode(mode)
  if mode == "off" or ns.GetBeaconMode() ~= "off" or not ns.GetBeaconConfirm() then
    ns.SetBeaconMode(mode)
    if done then done(true) end
    return
  end
  StaticPopup_Show("INNHOPPER_BEACON", nil, nil, { mode = mode, done = done })
end

-- True when the party state permits inviting: solo, or leading a party with a free slot.
function ns.BeaconPartyOpen()
  if not IsInGroup() then return true end
  if IsInRaid() or not UnitIsGroupLeader("player") then return false end
  return GetNumGroupMembers() < MAX_PARTY
end

-- Returns true when the player currently answers beacon queries.
function ns.BeaconActive()
  if ns.GetBeaconMode() == "off" then return false end
  if not ns.BeaconEligible() then return false end
  return ns.BeaconPartyOpen()
end

local function ReplyBudget()
  local now = GetTime()
  if now - windowStart >= REPLY_WINDOW then
    windowStart, windowCount = now, 0
  end
  if windowCount >= REPLY_CAP then return false end
  windowCount = windowCount + 1
  return true
end

-- Sends one query. Returns "sent", "throttled" or "failed".
-- With join set, a query already waiting for the same player is shared instead of refused.
local function SendQuery(name, callback, join)
  local key = Key(name)
  local waiting = pending[key]
  if waiting then
    if not join then return "failed" end
    waiting.callbacks[#waiting.callbacks + 1] = callback
    return "sent"
  end
  local ok, result = pcall(sendAddon, PREFIX, "Q", "WHISPER", name)
  Trace("query to " .. name .. " (key " .. key .. "): ok=" .. tostring(ok) .. " result=" .. tostring(result))
  if not ok then return "failed" end
  if result == THROTTLED then return "throttled" end
  if result ~= nil and result ~= 0 and result ~= true then return "failed" end
  local entry = { callbacks = { callback } }
  pending[key] = entry
  quiet[key] = GetTime() + QUERY_TIMEOUT + 2
  C_Timer.After(QUERY_TIMEOUT, function()
    if pending[key] == entry then
      pending[key] = nil
      for _, cb in ipairs(entry.callbacks) do cb(false, false) end
    end
  end)
  return "sent"
end

-- Sends a query to the named player. callback(true, autoInvite) on reply, callback(false) on timeout.
-- Returns false when no query was sent.
function ns.BeaconQuery(name, callback)
  if not sendAddon then return false end
  return SendQuery(name, callback or function() end, false) == "sent"
end

-- Scans a list of players. Queries are paced, results are cached for CACHE_TTL seconds
-- and at most SCAN_LIMIT players are queried. onResult(name, found, auto) is called per player;
-- onDone(stats) once every player is resolved. A new scan cancels the previous one.
local cache = NewStore()
local scan

local function Finish(s)
  if s.done then return end
  s.done = true
  if s.ticker then s.ticker:Cancel() end
  if scan == s then scan = nil end
  s.stats.elapsed = GetTime() - s.started
  if s.onDone then s.onDone(s.stats) end
end

local function Resolve(s, item, found, auto, fromCache)
  if not fromCache then StoreSet(cache, item.key, { found = found, auto = auto, at = GetTime() }) end
  if s.done or s.resolved[item.key] then return end
  s.resolved[item.key] = true
  s.stats.resolved = s.stats.resolved + 1
  if found then s.stats.found = s.stats.found + 1 end
  if s.onResult then s.onResult(item.name, found, auto) end
  if s.stats.resolved >= s.stats.total then Finish(s) end
end

local function Pump(s)
  if s.done then return end
  if GetTime() - s.started > SCAN_MAX_TIME then
    for i = s.index, #s.queue do Resolve(s, s.queue[i], false, false) end
    s.index = #s.queue + 1
    return
  end
  if s.pause and GetTime() < s.pause then return end
  local sentNow = 0
  while sentNow < SCAN_PER_TICK and s.index <= #s.queue do
    local item = s.queue[s.index]
    local status = SendQuery(item.name, function(found, auto) Resolve(s, item, found, auto) end, true)
    if status == "throttled" then
      s.stats.throttled = s.stats.throttled + 1
      s.pause = GetTime() + THROTTLE_BACKOFF
      return
    end
    s.index = s.index + 1
    if status == "sent" then
      s.stats.sent = s.stats.sent + 1
      sentNow = sentNow + 1
    else
      Resolve(s, item, false, false)
    end
  end
  if s.index > #s.queue and s.ticker then s.ticker:Cancel() s.ticker = nil end
end

function ns.BeaconScanCancel()
  if scan then
    local s = scan
    s.done = true
    if s.ticker then s.ticker:Cancel() end
    scan = nil
  end
end

-- Returns false when no scan was started.
function ns.BeaconScan(names, onResult, onDone)
  if not sendAddon then return false end
  ns.BeaconScanCancel()
  local s = {
    queue = {}, resolved = {}, index = 1, started = GetTime(),
    onResult = onResult, onDone = onDone,
    stats = { total = 0, resolved = 0, found = 0, sent = 0, cached = 0, throttled = 0, skipped = 0 },
  }
  local seen = {}
  local cached = {}
  for _, name in ipairs(names) do
    local key = Key(name)
    if not seen[key] then
      seen[key] = true
      if s.stats.total >= SCAN_LIMIT then
        s.stats.skipped = s.stats.skipped + 1
      else
        s.stats.total = s.stats.total + 1
        local hit = cache.t[key]
        if hit and GetTime() - hit.at < CACHE_TTL then
          cached[#cached + 1] = { name = name, key = key, found = hit.found, auto = hit.auto }
        else
          s.queue[#s.queue + 1] = { name = name, key = key }
        end
      end
    end
  end
  scan = s
  for _, hit in ipairs(cached) do
    s.stats.cached = s.stats.cached + 1
    Resolve(s, hit, hit.found, hit.auto, true)
    if s.done then return true end
  end
  if #s.queue == 0 then
    Finish(s)
    return true
  end
  s.ticker = C_Timer.NewTicker(SCAN_TICK, function() Pump(s) end)
  Pump(s)
  return true
end

-- Asks a beacon to invite the player. Returns false when nothing was sent.
function ns.BeaconJoin(name)
  if not sendAddon then return false end
  local ok = pcall(sendAddon, PREFIX, "J", "WHISPER", name)
  Trace("join request sent to " .. name .. ", ok=" .. tostring(ok))
  return ok
end

local function Reply(sender)
  local now = GetTime()
  local key = Key(sender)
  local last = lastReply.t[key]
  if last and now - last < REPLY_COOLDOWN then
    Trace("reply suppressed by cooldown")
    return
  end
  StoreSet(lastReply, key, now)
  local active = ns.BeaconActive()
  Trace("mode " .. ns.GetBeaconMode() .. ", active " .. tostring(active))
  if not active then return end
  if not ReplyBudget() then
    Trace("reply suppressed by reply cap")
    return
  end
  local payload = ns.GetBeaconAutoInvite() and "R1" or "R0"
  if pcall(sendAddon, PREFIX, payload, "WHISPER", sender) then
    StoreSet(answered, key, now)
  end
end

local function Join(sender)
  local key = Key(sender)
  local at = answered.t[key]
  if not at or GetTime() - at > JOIN_WINDOW then
    Trace("join request ignored: no recent reply to " .. sender)
    return
  end
  answered.t[key] = nil
  if not ns.GetBeaconAutoInvite() then
    Trace("join request ignored: auto-invite off")
    return
  end
  if not ns.BeaconActive() then
    Trace("join request ignored: not active")
    return
  end
  local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  if invite then
    pcall(invite, sender)
    Trace("invited " .. sender)
  end
end

local rx = CreateFrame("Frame")
rx:RegisterEvent("CHAT_MSG_ADDON")
rx:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
  if prefix ~= PREFIX then return end
  if not Known(text) or not Known(sender) then return end
  Trace("received " .. tostring(text) .. " from " .. sender .. " (key " .. Key(sender) .. ") via " .. tostring(channel))
  if channel ~= "WHISPER" then return end
  if text == "Q" then
    if ns.GetBeaconMode() ~= "off" then Reply(sender) end
  elseif text == "J" then
    if ns.GetBeaconMode() ~= "off" then Join(sender) end
  elseif string.sub(text, 1, 1) == "R" then
    local auto = string.sub(text, 2, 2) == "1"
    local key = Key(sender)
    local entry = pending[key]
    if entry then
      pending[key] = nil
      for _, cb in ipairs(entry.callbacks) do cb(true, auto) end
    end
  end
end)

-- Hides the server notice for a query sent to an offline player.
local notFound = ERR_CHAT_PLAYER_NOT_FOUND_S
if notFound and ChatFrame_AddMessageEventFilter then
  local escaped = string.gsub(notFound, "([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
  local pattern = "^" .. string.gsub(escaped, "%%%%s", "(.+)") .. "$"
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, message)
    if not Known(message) then return false end
    local name = string.match(message, pattern)
    if name then
      local expiry = quiet[Key(name)]
      if expiry and GetTime() < expiry then return true end
    end
    return false
  end)
end

------------------------------------------------------------------
-- Beacon button: grey = off, full colour = on. Click toggles; drag moves.
------------------------------------------------------------------
local button = CreateFrame("Button", "InnHopperBeaconButton", UIParent)
button:SetSize(36, 36)
button:SetFrameStrata("MEDIUM")
button:SetClampedToScreen(true)
button:SetMovable(true)
button:EnableMouse(true)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetPoint("CENTER", UIParent, "CENTER", 0, -200)

local back = button:CreateTexture(nil, "BACKGROUND")
back:SetPoint("TOPLEFT", -1, 1)
back:SetPoint("BOTTOMRIGHT", 1, -1)
back:SetColorTexture(0, 0, 0, 0.8)

local face = button:CreateTexture(nil, "ARTWORK")
face:SetAllPoints()
face:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Textures\\logo")
face:SetTexCoord(0.06, 0.94, 0.06, 0.94)

button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

function ns.BeaconButtonUpdate()
  local on = ns.GetBeaconMode() == "on"
  button:SetShown(ns.GetBeaconButtonShown())
  face:SetDesaturated(not on)
  if on then face:SetVertexColor(1, 1, 1, 1) else face:SetVertexColor(0.6, 0.6, 0.6, 0.9) end
end

button:SetScript("OnClick", function(_, mouseButton)
  if mouseButton == "RightButton" then
    ns.RequestBeaconMode(ns.GetBeaconMode() == "on" and "off" or "on")
  elseif ns.Toggle then
    ns.Toggle()
  end
end)
button:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("InnHopper beacon", 1, 0.82, 0)
  GameTooltip:AddLine("Left click: open InnHopper", 1, 1, 1)
  GameTooltip:AddLine("Right click: beacon on / off", 1, 1, 1)
  GameTooltip:AddLine("Shift + drag: move", 1, 1, 1)
  GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)
button:SetScript("OnDragStart", function(self)
  if IsShiftKeyDown() then
    GameTooltip:Hide()
    self:StartMoving()
  end
end)
button:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relPoint, x, y = self:GetPoint(1)
  QuickTeleportDB.beaconButton = { point = point, relPoint = relPoint, x = x, y = y }
end)

local place = CreateFrame("Frame")
place:RegisterEvent("PLAYER_LOGIN")
place:SetScript("OnEvent", function()
  if ns.InitDB then ns.InitDB() end
  local pos = QuickTeleportDB.beaconButton
  if pos and pos.point then
    button:ClearAllPoints()
    button:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  end
  ns.BeaconButtonUpdate()
end)
ns.BeaconButtonUpdate()
