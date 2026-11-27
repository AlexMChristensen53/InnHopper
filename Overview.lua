-- Beacon overview: lists the towns that currently have an available beacon.
-- Temporary and self-contained: removing this file, its .toc entry and the
-- ns.Overview* hooks in InnHopper.lua, Options.lua and Beacons.lua restores
-- the previous behaviour.
--
-- Protocol (hidden addon messages in a temporary channel):
--   "L"                    a viewer asks which beacons are available.
--   "B<auto>|<zone>|<sub>|<level>|<class file>"
--                          an available beacon answers after a random delay, and
--                          announces itself at once when it becomes available.
--   "X"                    a beacon withdraws when it stops being available.
-- Every InnHopper user takes part: the channel is joined after login.
local ADDON, ns = ...

local PREFIX = "IHBOARD"
local CHANNEL = "IHBeaconBoard"
local POLL = 10          -- seconds between viewer queries while the window is open
local EXPIRE = 25        -- seconds an announcement stays valid
local REPLY_MIN = 5      -- minimum seconds between two announcements of one beacon
local REPLY_JITTER = 3   -- maximum random reply delay in seconds
local MAX_ENTRIES = 300
local JOIN_TRIES = 10

local registerPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local sendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if registerPrefix then registerPrefix(PREFIX) end

local function Known(v)
  return not (issecretvalue and issecretvalue(v))
end

local function Dbg(text)
  if ns.Dbg then ns.Dbg("overview: " .. text) end
end

local function Short(name)
  return string.lower(Ambiguate(name, "short"))
end

------------------------------------------------------------------
-- Settings
------------------------------------------------------------------
function ns.OverviewEnabled()
  return true
end

local Sync, Reconcile

------------------------------------------------------------------
-- Channel
------------------------------------------------------------------
local joined, joining = false, false

local function ChannelId()
  local id = GetChannelName(CHANNEL)
  if id and id > 0 then return id end
  return nil
end

-- Keeps the channel out of every chat window.
local function HideFromChat()
  if not ChatFrame_RemoveChannel then return end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local frame = _G["ChatFrame" .. i]
    if frame then ChatFrame_RemoveChannel(frame, CHANNEL) end
  end
end

local function JoinChannel()
  if joined or joining then return end
  if ChannelId() then
    joined = true
    HideFromChat()
    return
  end
  joining = true
  local join = JoinTemporaryChannel or JoinChannelByName
  if not join then joining = false return end
  join(CHANNEL)
  local tries = 0
  local function wait()
    if ChannelId() then
      joined, joining = true, false
      HideFromChat()
      Dbg("joined")
      if Reconcile then Reconcile() end
      return
    end
    tries = tries + 1
    if tries < JOIN_TRIES then
      C_Timer.After(1, wait)
    else
      joining = false
      Dbg("join failed")
    end
  end
  C_Timer.After(1, wait)
end

-- Suppresses the join and leave notices of the channel.
local function NoticeFilter(_, _, _, _, _, channelString, _, _, _, _, channelName)
  if channelName == CHANNEL then return true end
  if Known(channelString) and type(channelString) == "string" and string.find(channelString, CHANNEL, 1, true) then
    return true
  end
  return false
end
if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", NoticeFilter)
  ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", NoticeFilter)
end

local stats = { sent = 0, lastResult = "none", gotL = 0, gotB = 0, ignored = 0 }

local function Send(text)
  local id = ChannelId()
  if not id or not sendAddon then
    stats.lastResult = "no channel"
    return false
  end
  stats.sent = stats.sent + 1
  stats.lastResult = tostring(sendAddon(PREFIX, text, "CHANNEL", id))
  Dbg("sent " .. string.sub(text, 1, 1) .. " -> " .. stats.lastResult)
  return true
end

------------------------------------------------------------------
-- Viewer: announcements and counts per town
------------------------------------------------------------------
local store = {}
local nEntries = 0
local counts, countsDirty = {}, true

local function Prune()
  local now = GetTime()
  for key, e in pairs(store) do
    if now - e.t > EXPIRE then
      store[key] = nil
      nEntries = nEntries - 1
      countsDirty = true
    end
  end
end

-- Towns by their own name and by zone, built once on first use.
local byName, byZone

local function BuildLookup()
  byName, byZone = {}, {}
  for _, list in pairs({ ns.DEST.Alliance, ns.DEST.Horde, ns.DEST.Neutral }) do
    for i = 1, #list do
      local t = list[i]
      byName[t[1]] = true
      byZone[t[2]] = byZone[t[2]] or {}
      table.insert(byZone[t[2]], t[1])
    end
  end
end

-- Calls fn(town) for every town an announcement belongs to: the town named by its
-- sub-zone or zone, else every town in its zone.
local function EachTown(e, fn)
  if byName[e.sub] then
    fn(e.sub)
    if e.zone ~= e.sub and byName[e.zone] then fn(e.zone) end
  elseif byName[e.zone] then
    fn(e.zone)
  elseif byZone[e.zone] then
    for _, town in ipairs(byZone[e.zone]) do fn(town) end
  end
end

local function Bump(town)
  counts[town] = (counts[town] or 0) + 1
end

local function Rebuild()
  if not byName then BuildLookup() end
  counts = {}
  for _, e in pairs(store) do EachTown(e, Bump) end
  countsDirty = false
end

-- Available beacons in a town, independent of any /who result.
function ns.OverviewBeacons(dest)
  Prune()
  if not byName then BuildLookup() end
  local out, target, hit = {}, dest[1], false
  local function Hit(town) if town == target then hit = true end end
  for _, e in pairs(store) do
    hit = false
    EachTown(e, Hit)
    if hit then
      local cf = e.classFile
      out[#out + 1] = { name = e.name, short = Ambiguate(e.name, "short"), auto = e.auto,
                        area = e.sub ~= "" and e.sub or e.zone, level = e.level, classFile = cf,
                        class = cf and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf] or cf }
    end
  end
  return out
end

function ns.OverviewCount(town)
  if countsDirty then Rebuild() end
  return counts[town[1]] or 0
end

-- True while the town list shows the beacon column.
function ns.OverviewOn()
  return ns.OverviewEnabled()
end

local refreshQueued = false
local function QueueRefresh()
  if refreshQueued then return end
  refreshQueued = true
  C_Timer.After(0.5, function()
    refreshQueued = false
    if ns.frame and ns.frame:IsShown() and ns.RefreshMain then
      ns.RefreshMain()
    end
  end)
end

------------------------------------------------------------------
-- Beacon: announce when asked
------------------------------------------------------------------
local lastAnnounce = 0

local announcedKey   -- what this beacon last announced; nil while not announcing

-- The announcement for the current place, or nil while the zone is unknown.
local function Message()
  local zone = GetRealZoneText() or ""
  if zone == "" then return nil end
  local _, classFile = UnitClass("player")
  return "B" .. (ns.GetBeaconAutoInvite() and "1" or "0") .. "|" .. zone .. "|" .. (GetSubZoneText() or "")
    .. "|" .. (UnitLevel("player") or 0) .. "|" .. (classFile or "")
end

local function Announce()
  local msg = Message()
  if not msg or not Send(msg) then return false end
  announcedKey = msg
  lastAnnounce = GetTime()
  return true
end

-- Announces at once when this player becomes an available beacon or changes place,
-- and withdraws when it stops being one.
Reconcile = function()
  if ns.BeaconActive() then
    if Message() ~= announcedKey then Announce() end
  elseif announcedKey then
    if Send("X") or not ChannelId() then announcedKey = nil end
  end
end

local function OnQuery()
  if not ns.BeaconActive() then return end
  local now = GetTime()
  if now - lastAnnounce < REPLY_MIN then return end
  lastAnnounce = now
  C_Timer.After(math.random() * REPLY_JITTER, function()
    if ns.BeaconActive() then Announce() end
  end)
end

local queued = false
local function QueueReconcile()
  if queued then return end
  if not announcedKey and ns.GetBeaconMode() ~= "on" then return end
  queued = true
  C_Timer.After(0.5, function()
    queued = false
    Reconcile()
  end)
end

local state = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_UPDATE_RESTING", "GROUP_ROSTER_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
  state:RegisterEvent(ev)
end
state:RegisterUnitEvent("UNIT_AURA", "player")
state:SetScript("OnEvent", QueueReconcile)

local rx = CreateFrame("Frame")
rx:RegisterEvent("CHAT_MSG_ADDON")
rx:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
  if prefix ~= PREFIX then return end
  if channel ~= "CHANNEL" then
    stats.ignored = stats.ignored + 1
    Dbg("ignored message via " .. tostring(channel))
    return
  end
  if not Known(text) or not Known(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  local me = UnitName("player")
  if not me or Short(sender) == string.lower(me) then return end
  if text == "X" then
    local key = Short(sender)
    if store[key] then
      store[key] = nil
      nEntries = nEntries - 1
      countsDirty = true
      QueueRefresh()
    end
  elseif text == "L" then
    stats.gotL = stats.gotL + 1
    Dbg("query from " .. sender)
    OnQuery()
  else
    stats.gotB = stats.gotB + 1
    Dbg("announcement from " .. sender .. ": " .. text)
    local auto, zone, sub, level, classFile = string.match(text, "^B([01])|([^|]*)|([^|]*)|?(%d*)|?(%u*)$")
    if not zone then return end
    local key = Short(sender)
    if not store[key] then
      if nEntries >= MAX_ENTRIES then return end
      nEntries = nEntries + 1
    end
    store[key] = { zone = zone, sub = sub, auto = auto == "1", t = GetTime(), name = sender,
                   level = (tonumber(level) or 0) > 0 and tonumber(level) or nil, classFile = classFile ~= "" and classFile or nil }
    countsDirty = true
    QueueRefresh()
  end
end)

------------------------------------------------------------------
-- Viewer: periodic query while the window is open
------------------------------------------------------------------
local ticker

local function Poll()
  if not (ns.frame and ns.frame:IsShown()) then return end
  Prune()
  if ChannelId() then Send("L") end
  QueueRefresh()
end

-- Joins the channel and starts polling.
Sync = function()
  JoinChannel()
  if not ticker then ticker = C_Timer.NewTicker(POLL, Poll) end
end

-- Diagnostic summary for Debug.lua.
function ns.OverviewState()
  Prune()
  local lines = { "channel id " .. tostring(ChannelId()) .. ", joined " .. tostring(joined)
    .. ", enabled " .. tostring(ns.OverviewEnabled()) .. ", entries " .. nEntries,
    "beacon mode " .. tostring(ns.GetBeaconMode()) .. ", active " .. tostring(ns.BeaconActive()),
    "sent " .. stats.sent .. " (last result " .. stats.lastResult .. "), queries received " .. stats.gotL
      .. ", announcements received " .. stats.gotB .. ", other " .. stats.ignored }
  if GetChannelList then
    local list = { GetChannelList() }
    local names = {}
    for i = 1, #list, 3 do table.insert(names, tostring(list[i]) .. "=" .. tostring(list[i + 1])) end
    table.insert(lines, "channels: " .. table.concat(names, ", "))
  end
  for key, e in pairs(store) do
    table.insert(lines, "  " .. key .. ": " .. e.zone .. " / " .. e.sub .. " (" .. string.format("%.0f", GetTime() - e.t) .. " s ago)")
  end
  return lines
end

-- Sends a query immediately (Debug.lua).
function ns.OverviewQuery()
  Send("L")
end

if ns.OnBeaconChange then
  ns.OnBeaconChange(function()
    Reconcile()
    Sync()
  end)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  -- Channels are not ready right at login.
  C_Timer.After(8, function()
    Sync()
    if ns.frame then
      ns.frame:HookScript("OnShow", function()
        Prune()
        QueueRefresh()
        if ChannelId() then Send("L") end
      end)
    end
  end)
end)
