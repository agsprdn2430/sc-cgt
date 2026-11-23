local Cfg = {
  BackgroundID     = 12840,
  VerticalPNB      = false,
  PublicPNB        = true,
  BypassPaywall    = true,
  BypassWayBlock   = false,
  pnbX             = 195,
  pnbY             = 198,
  TelX             = 0,
  TelY             = 0,
  AutoBuyWL        = false,
  ConvertBGL       = true,
  ConvertDLBGL     = true,
  MaxGems          = 200000,
  ConsumeArroz     = true,
  ConsumeClover    = false,
  ConsumeSongpyeon = true,
  TakeConsumable   = false,
  WorldConsume     = "",
  DelayTake        = 1000,
  AutoBuff         = true,
  AutoRemote       = true,
  EmptyUseAutoRemote = true,
  RespawnOnStop    = false,
  EmptyWaitSec     = 60,
  AutoBuyCheats    = true,
  SuckBgems        = false,
  SuckThreshold    = 100000,
  SuckCooldown     = 6000,
  NoGemsDrop       = true,
  AutoDontDrop     = true,
  BGemID           = 0,
  PGemID           = 0,
  IGemID           = 0,
  IgnoreOther      = false,
  MirrorPNB        = false,
  WebhookPNB       = false,
  WebhookUrl       = "",
  DiscordID        = "",
}

EditToggle("Indexed sprite rendering", true)

local USAGE_WEBHOOK = "https://discord.com/api/webhooks/1572572421393879061/sMefexYUUJ88ZUALKOh_YItv1AXp298oAAtI4bRke2JJHsKGttiIrKA_fk2tQl0r6AaT"
local SCRIPT_VERSION = "ALPHA"

local Defaults = {}
for k, v in pairs(Cfg) do Defaults[k] = v end

local Mag, Now = {}, 1
local ScriptRunning, StartRequested = false, false
local WorldName, Nick = "", "Unknown"
local GetRemote, MagW, Taking = false, false, false
local CheatOn, CheatOff, CheatStopped, PendingCheatOn = false, false, true, false
local Ghost, ghost, BlockSB = false, true, false
local reconnect, ReconnectWebhook, AllMagEmpty = false, false, false
local arroz, clover, cheat = false, false, false
local JoinRequested = false
local LastTime, LastJoin, IsJoining = 0, -8000, false
local JoinDelay = 8000
local StartTime, StartTotalLocks = 0, 0
local EarnedBGLTotal, EarnedDLTotal = 0, 0
local PinkGems, BlackGems, InfinityGems = 0, 0, 0
local PGems, BGems, IGems = 0, 0, 0
local CheckBuff, CheckRemote, CheckGems, CheckIgnore = 0, 0, 0, 0
local ConsumableID = {}
local PASSED_BLOCKS = {}
local WrenchTry, PathTry, WrenchFor = 0, 0, nil
local LastDDCheck, LastGemObjs, LastDDForce = -100000, 0, 0
local FirstEmpty, LastEmpty, NeedReassert, LastReassert = nil, 0, false, -100000
local PathFails, PathBlockUntil, WalkOffSent = 0, {}, false
local CPBlock, CPCalls = {}, 0
local CPLeft, SizeCache = math.huge, nil

local function toint(v)
  return math.floor(tonumber(v) or 0)
end

local function truthy(v)
  return v == true or v == 1 or v == "1" or v == "true"
end

local function Say(msg)
  LogToConsole("`b[PNB]`` " .. msg)
end

function TextOverlay(text)
  SendVariantList({[0] = "OnTextOverlay", [1] = text})
end

local function WorldInfo()
  local ok, w = pcall(GetWorld)
  if ok and type(w) == "table" and w.name and w.name ~= "" then return w end
  return nil
end

local function InWorld()
  return WorldInfo() ~= nil
end

local function MyPos()
  local ok, me = pcall(GetLocal)
  if not ok or type(me) ~= "table" or not me.pos then return nil end
  return math.floor(me.pos.x / 32), math.floor(me.pos.y / 32)
end

local function SafeTile(x, y)
  local ok, t = pcall(GetTile, x, y)
  if ok then return t end
  return nil
end

local function Raw(p)
  if p.state ~= nil then
    p.flags = p.state
    p.state = nil
  end
  SendPacketRaw(false, p)
end

local function GetGems()
  local ok, info = pcall(GetPlayerInfo)
  if ok and type(info) == "table" then return info.gems or 0 end
  return 0
end

local function jesc(s)
  return (tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

function inv(id)
  local ok, list = pcall(GetInventory)
  if not ok or type(list) ~= "table" then return 0 end
  for _, item in ipairs(list) do
    if item.id == id then return item.amount end
  end
  return 0
end

function obj(id)
  if not id then return 0 end
  local ok, list = pcall(Client.GetObjects)
  if not ok or type(list) ~= "table" then return 0 end
  local total = 0
  for _, o in ipairs(list) do
    if o.id == id then total = total + o.amount end
  end
  return total
end

function RefreshChecks()
  CheckIgnore = Cfg.IgnoreOther and 1 or 0
  CheckBuff   = Cfg.AutoBuff and 1 or 0
  CheckRemote = Cfg.AutoRemote and 1 or 0
  CheckGems   = Cfg.NoGemsDrop and 1 or 0
end

function GetMag()
  local tiles = {}
  local w = WorldInfo()
  if not w then return tiles end
  local step = 100
  for cy = 0, w.height - 1, step do
    for cx = 0, w.width - 1, step do
      local cw = math.min(step, w.width - cx)
      local ch = math.min(step, w.height - cy)
      local ok, list = pcall(Client.GetTiles, cx, cy, cw, ch)
      if ok and type(list) == "table" then
        for _, t in ipairs(list) do
          if t.fg == 5638 and t.bg == Cfg.BackgroundID then
            table.insert(tiles, {x = t.x, y = t.y})
          end
        end
      else
        for y = cy, cy + ch - 1 do
          if ScriptRunning and y % 10 == 0 then Sleep(1) end
          for x = cx, cx + cw - 1 do
            local t = SafeTile(x, y)
            if t and t.fg == 5638 and t.bg == Cfg.BackgroundID then
              table.insert(tiles, {x = x, y = y})
            end
          end
        end
      end
    end
  end
  table.sort(tiles, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
  end)
  return tiles
end

local function RecalcMag()
  Mag = GetMag()
  Now = 1
  Say("`2" .. #Mag .. " magplant (bg " .. Cfg.BackgroundID .. ")")
  return #Mag
end

function FindTPVertical(x, y)
  Raw({state = 32, x = x * 32 - 1, y = y * 32 - 1, px = -1, py = -1})
end

function FindTPLeft(x, y)
  Raw({state = 48, x = x * 32, y = y * 32, px = x, py = y})
end

function Wrench(x, y, try)
  try = try or 1
  local px, py = x * 32, y * 32
  if try % 2 == 1 then
    local ok, me = pcall(GetLocal)
    if ok and type(me) == "table" and me.pos then px, py = me.pos.x, me.pos.y end
  end
  local st = (try % 3 == 0) and 48 or 32
  Raw({type = 3, state = st, value = 32, px = x, py = y, x = px, y = py})
end

function CheatTurnOff()
  SendPacket(2, "action|dialog_return\ndialog_name|cheats\n" ..
    "check_autofarm|0\ncheck_bfg|0\ncheck_gems|" .. CheckGems .. "\n" ..
    "check_lonely|" .. CheckIgnore .. "\n" ..
    "check_ignoreo|" .. CheckIgnore .. "\n" ..
    "check_ignoref|" .. CheckIgnore)
end

function CheatTurnOn()
  if not ScriptRunning then return end
  SendPacket(2, "action|dialog_return\ndialog_name|cheats\n" ..
    "check_autofarm|1\ncheck_bfg|1\n" ..
    "check_autobuff|" .. CheckBuff .. "\n" ..
    "check_autoremote|" .. CheckRemote .. "\n" ..
    "check_gems|" .. CheckGems .. "\n" ..
    "check_lonely|" .. CheckIgnore .. "\n" ..
    "check_ignoreo|" .. CheckIgnore .. "\n" ..
    "check_ignoref|" .. CheckIgnore)
end

function SendWebhook(url, data)
  if not url or url == "" or type(MakeRequest) ~= "function" then return end
  pcall(MakeRequest, url, "POST", {["Content-Type"] = "application/json"}, data)
end

function SendUsageNotice()
  if type(MakeRequest) ~= "function" then return end
  local line = "PNB CGT Usage | GrowID: " .. jesc(Nick) .. " | World: " .. jesc(WorldName) ..
    " | " .. SCRIPT_VERSION .. " | <t:" .. os.time() .. ":F>"
  SendWebhook(USAGE_WEBHOOK, '{"content":"' .. line .. '"}')
end

function CheckTime()
  local now = os.time()
  if now - LastTime >= 300 and InWorld() and GetRemote and Cfg.WebhookPNB then
    SendInfoPNB()
    Sleep(1000)
    LastTime = now
  end
end

function SafeJoin(world)
  local now = Script.GetTime()
  if IsJoining then return end
  if now - LastJoin < JoinDelay then return end
  IsJoining = true
  LastJoin = now
  SendPacket(3, "action|join_request\nname|" .. world .. "|\ninvitedWorld|0")
  Sleep(6000)
  IsJoining = false
end

function GoPath(t, s, v, x, y)
  if not InWorld() then return end
  Raw({type = t, state = s, value = v, px = x, py = y, x = x * 32, y = y * 32})
  if t == nil then
    pcall(SetLocalPos, x * 32, y * 32)
  end
end

function PrivatePath(x, y)
  if not InWorld() then return end
  local delay = 100
  local iX, iY = MyPos()
  if not iX then return end
  local function step(dx, dy, n)
    for _ = 1, n do
      iX, iY = iX + dx, iY + dy
      GoPath(3, 1, 0, iX, iY)
      GoPath(nil, nil, nil, iX, iY)
      Sleep(delay)
    end
  end
  local distX, distY = x - iX, y - iY
  if distY > 1 then step(0, 1, distY) elseif distY < -1 then step(0, -1, -distY) end
  if distX > 1 then step(1, 0, distX) elseif distX < -1 then step(-1, 0, -distX) end
  local ok, has = pcall(CheckPath, x, y)
  if ok and not has then Say("`9No Path Found!") end
  FindPath(x, y, 550)
  Sleep(delay)
end

function GetWorldSize()
  local w = WorldInfo()
  if not w then return nil end
  return w.width - 1, w.height - 1
end

local PAYWALL_BLOCK = 16308
local ALLOWED_BLOCKS = {[0] = true, [3898] = true, [15858] = true}
local NOT_ALLOWED_BLOCKS = {[3796] = true}

local function UpdatePaywallBlocks(verbose)
  if Cfg.BypassPaywall then
    ALLOWED_BLOCKS[PAYWALL_BLOCK] = true
    NOT_ALLOWED_BLOCKS[PAYWALL_BLOCK] = nil
  else
    ALLOWED_BLOCKS[PAYWALL_BLOCK] = nil
    NOT_ALLOWED_BLOCKS[PAYWALL_BLOCK] = true
  end
  if Cfg.BypassWayBlock then
    ALLOWED_BLOCKS[3796] = true
    NOT_ALLOWED_BLOCKS[3796] = nil
  else
    ALLOWED_BLOCKS[3796] = nil
    NOT_ALLOWED_BLOCKS[3796] = true
  end
  if verbose then
    Say("Paywall " .. (Cfg.BypassPaywall and "`2allowed" or "`4blocked") ..
        "`` | One way " .. (Cfg.BypassWayBlock and "`2allowed" or "`4blocked"))
  end
end

local function GetTileBlockId(tile)
  if not tile then return 0 end
  if tile.fg and tile.fg ~= 0 then return tile.fg end
  if tile.bg and tile.bg ~= 0 then return tile.bg end
  return 0
end

function IsTileWalkable(x, y)
  local maxX, maxY
  if SizeCache then
    maxX, maxY = SizeCache.x, SizeCache.y
  else
    if not InWorld() then return nil end
    maxX, maxY = GetWorldSize()
  end
  if not maxX then return nil end
  if x < 0 or y < 0 or x > maxX or y > maxY then return false end
  local tile = SafeTile(x, y)
  if not tile then return false end
  local blockid = GetTileBlockId(tile)
  if blockid ~= 0 and (ALLOWED_BLOCKS[blockid] or PASSED_BLOCKS[blockid]) then return true end
  if blockid ~= 0 and NOT_ALLOWED_BLOCKS[blockid] then return false end
  if (tile.fg or 0) == 0 then return true end
  local fgid = tile.fg
  if SizeCache then
    local c = CPBlock[fgid]
    if c ~= nil then return c end
  end
  if CPLeft <= 0 then return false end
  CPLeft = CPLeft - 1
  CPCalls = CPCalls + 1
  local ok, res = pcall(CheckPath, x, y)
  if CPCalls % 5 == 0 and ScriptRunning then Sleep(1) end
  res = (ok and res) and true or false
  if SizeCache then CPBlock[fgid] = res end
  return res
end

local function HeapPush(h, node)
  h.n = h.n + 1
  local i = h.n
  h[i] = node
  while i > 1 do
    local p = math.floor(i / 2)
    if h[p].f <= h[i].f then break end
    h[p], h[i] = h[i], h[p]
    i = p
  end
end

local function HeapPop(h)
  if h.n == 0 then return nil end
  local top = h[1]
  h[1] = h[h.n]
  h[h.n] = nil
  h.n = h.n - 1
  local i = 1
  while true do
    local l, r, m = i * 2, i * 2 + 1, i
    if l <= h.n and h[l].f < h[m].f then m = l end
    if r <= h.n and h[r].f < h[m].f then m = r end
    if m == i then break end
    h[m], h[i] = h[i], h[m]
    i = m
  end
  return top
end

function FindSafePath(startX, startY, targetX, targetY, maxIterations, budgetMs)
  if not InWorld() then return nil end
  maxIterations = maxIterations or 2000
  budgetMs = budgetMs or 1500
  local maxX, maxY = GetWorldSize()
  if not maxX then return nil end
  local W = maxX + 1
  local t0 = Script.GetTime()
  local oldCP, oldSize = CPLeft, SizeCache
  CPLeft, SizeCache = 120, {x = maxX, y = maxY}
  CPBlock = {}

  local memo = {}
  local function walk(x, y)
    local k = y * W + x
    local v = memo[k]
    if v == nil then
      v = IsTileWalkable(x, y) and true or false
      memo[k] = v
    end
    return v
  end
  local function heuristic(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)
  end

  local open, gScore, came, closed = {n = 0}, {}, {}, {}
  local sk = startY * W + startX
  gScore[sk] = 0
  HeapPush(open, {x = startX, y = startY, k = sk, g = 0, f = heuristic(startX, startY, targetX, targetY)})
  local dirs = {{0, -1}, {0, 1}, {-1, 0}, {1, 0}}
  local iterations, result = 0, nil
  while open.n > 0 and iterations < maxIterations do
    iterations = iterations + 1
    if iterations % 150 == 0 then
      if Script.GetTime() - t0 > budgetMs or not ScriptRunning then break end
      Sleep(1)
    end
    local cur = HeapPop(open)
    if not closed[cur.k] then
      closed[cur.k] = true
      if cur.x == targetX and cur.y == targetY then
        local path, node = {}, cur
        while node do
          table.insert(path, 1, {x = node.x, y = node.y})
          node = came[node.k]
        end
        result = path
        break
      end
      for _, d in ipairs(dirs) do
        local nx, ny = cur.x + d[1], cur.y + d[2]
        if nx >= 0 and ny >= 0 and nx <= maxX and ny <= maxY then
          local nk = ny * W + nx
          if not closed[nk] and walk(nx, ny) then
            local g = cur.g + 1
            if not gScore[nk] or g < gScore[nk] then
              gScore[nk] = g
              came[nk] = cur
              HeapPush(open, {x = nx, y = ny, k = nk, g = g, f = g + heuristic(nx, ny, targetX, targetY)})
            end
          end
        end
      end
    end
  end
  CPLeft, SizeCache = oldCP, oldSize
  return result
end

local function FindNearestReachable(targetX, targetY, maxRadius, curX, curY)
  if not InWorld() then return nil end
  maxRadius = maxRadius or 5
  local maxX, maxY = GetWorldSize()
  if not maxX then return nil end
  local t0 = Script.GetTime()
  local oldCP, oldSize = CPLeft, SizeCache
  CPLeft, SizeCache = 80, {x = maxX, y = maxY}
  CPBlock = {}
  local candidates = {}
  for dx = -maxRadius, maxRadius do
    for dy = -maxRadius, maxRadius do
      local dist = math.abs(dx) + math.abs(dy)
      if dist <= maxRadius then
        local cx, cy = targetX + dx, targetY + dy
        if cx >= 0 and cy >= 0 and cx <= maxX and cy <= maxY and IsTileWalkable(cx, cy) then
          table.insert(candidates, {x = cx, y = cy, d = dist})
        end
      end
    end
  end
  CPLeft, SizeCache = oldCP, oldSize
  table.sort(candidates, function(a, b) return a.d < b.d end)
  local tried = 0
  for _, c in ipairs(candidates) do
    if tried >= 6 or not ScriptRunning or Script.GetTime() - t0 > 3000 then break end
    tried = tried + 1
    local path = FindSafePath(curX, curY, c.x, c.y, 600, 600)
    if path and #path > 0 then return path, c.x, c.y end
    Sleep(1)
  end
  return nil
end

local function WalkPath(path, record)
  for i, pos in ipairs(path) do
    if i > 1 then
      if not ScriptRunning then return false end
      local walkable = IsTileWalkable(pos.x, pos.y)
      GoPath(3, 1, 0, pos.x, pos.y)
      GoPath(nil, nil, nil, pos.x, pos.y)
      Sleep(100)
      local cx, cy = MyPos()
      if cx ~= pos.x or cy ~= pos.y then return false end
      if record and not walkable then
        local id = GetTileBlockId(SafeTile(pos.x, pos.y))
        if id ~= 0 then PASSED_BLOCKS[id] = true end
      end
    end
  end
  return true
end

function SafeFindPath(x, y)
  if Ghost and not Cfg.PublicPNB then return end
  if not Cfg.PublicPNB then return PrivatePath(x, y) end
  if not InWorld() then return false end
  local iX, iY = MyPos()
  if not iX then return false end
  if iX == x and iY == y then PathFails = 0 return true end

  local key = x .. "," .. y
  if PathBlockUntil[key] and Script.GetTime() < PathBlockUntil[key] then return false end

  local function failed(block)
    PathFails = PathFails + 1
    if block then PathBlockUntil[key] = Script.GetTime() + 4000 end
    if PathFails >= 3 then
      PathFails = 0
      Say("`9Path search failed 3x, using direct path")
      PrivatePath(x, y)
      local fx, fy = MyPos()
      return fx == x and fy == y
    end
    return false
  end

  local path = FindSafePath(iX, iY, x, y, 1000, 1500)
  if path and #path > 0 then
    if WalkPath(path, true) then PathFails = 0 return true end
    return failed(false)
  end

  Say("`9No Path Found!")
  local cand = FindNearestReachable(x, y, 10, iX, iY)
  if cand and #cand > 0 then
    if not WalkPath(cand, false) then return failed(false) end
    local fx, fy = MyPos()
    if fx and math.abs(fx - x) + math.abs(fy - y) <= 10 then
      GoPath(3, 1, 0, x, y)
      GoPath(nil, nil, nil, x, y)
      Sleep(100)
      local ax, ay = MyPos()
      if ax == x and ay == y then PathFails = 0 return true end
    end
  end
  return failed(true)
end

local LastSuck, SuckBase = -100000, 0
function AutoSuck(force)
  if not force and not Cfg.SuckBgems then return end
  if not InWorld() then return end
  local t = Script.GetTime()
  local known = BlackGems and BlackGems > 0
  local cnt = known and obj(BlackGems) or -1
  if not force then
    if known and cnt < Cfg.SuckThreshold then return end
    if t - LastSuck < Cfg.SuckCooldown then return end
    if known and SuckBase > 0 and cnt >= SuckBase and t - LastSuck < Cfg.SuckCooldown * 3 then return end
  end
  LastSuck, SuckBase = t, math.max(cnt, 0)
  local netid
  local ok, me = pcall(GetLocal)
  if ok and type(me) == "table" then netid = me.netid or me.netID or me.net_id end
  SendPacket(2, "action|dialog_return\ndialog_name|popup\n" ..
    (netid and ("netID|" .. toint(netid) .. "|\n") or "") .. "buttonClicked|bgem_suckall\n")
  if known then
    Say("`2Suck BGems (" .. cnt .. ")")
  else
    Say("`2Suck BGems (BGem ID unknown, timer mode)")
  end
end

function DebugObjects()
  local ok, list = pcall(Client.GetObjects)
  if not ok or type(list) ~= "table" then Say("`4Can't read world objects") return end
  local sum, order = {}, {}
  for _, o in ipairs(list) do
    if not sum[o.id] then sum[o.id] = 0; table.insert(order, o.id) end
    sum[o.id] = sum[o.id] + (o.amount or 1)
  end
  table.sort(order, function(a, b) return sum[a] > sum[b] end)
  for i = 1, math.min(#order, 15) do
    local id = order[i]
    local okI, info = pcall(GetItemInfo, id)
    local nm = (okI and type(info) == "table" and info.name) or "?"
    Say("obj id " .. id .. " (" .. tostring(nm) .. ") x" .. sum[id])
  end
  Say("IDs now: Black=" .. BlackGems .. " Pink=" .. PinkGems .. " Infinity=" .. InfinityGems ..
      " | set BGemID/PGemID/IGemID in the GUI if wrong")
end

function AutoDontDrop()
  if not Cfg.NoGemsDrop or not Cfg.AutoDontDrop then return end
  if not InWorld() then return end
  local t = Script.GetTime()
  if t - LastDDCheck < 15000 then return end
  LastDDCheck = t
  local total = 0
  local want = {}
  for _, id in ipairs({BlackGems, PinkGems, InfinityGems, 112}) do
    if id and id > 0 then want[id] = true end
  end
  local okO, olist = pcall(Client.GetObjects)
  if okO and type(olist) == "table" then
    for _, o in ipairs(olist) do
      if want[o.id] then total = total + (o.amount or 1) end
    end
  end
  local grew = LastGemObjs > 0 and total > LastGemObjs
  LastGemObjs = total
  if grew or t - LastDDForce >= 120000 then
    LastDDForce = t
    CheatTurnOn()
    if grew then Say("`9Gems dropping -> re-apply Don't Drop Gems") end
  end
end

local LastConvert = 0
function AutoConvert()
  local t = Script.GetTime()
  if t - LastConvert < 2000 then return end
  LastConvert = t
  local Gems = GetGems()
  local maxg = Cfg.MaxGems
  local tel = "action|dialog_return\ndialog_name|telephone\nnum|53785|\nx|" .. Cfg.TelX ..
              "|\ny|" .. Cfg.TelY .. "|\nbuttonClicked|"
  local makeBGL = "action|dialog_return\ndialog_name|info_box\nbuttonClicked|make_bgl"

  if Cfg.AutoBuyWL then
    if inv(242) < 100 and inv(1796) < 100 and inv(7188) < 100 and Gems >= maxg then
      SendPacket(2, "action|buy\nitem|buy_worldlockpack")
    elseif inv(242) >= 100 and inv(1796) < 100 and inv(7188) < 100 then
      Raw({type = 10, value = 242})
    elseif inv(1796) >= 100 and inv(7188) < 100 then
      SendPacket(2, tel .. "bglconvert")
    elseif inv(7188) >= 100 then
      SendPacket(2, makeBGL)
    end
  end
  if Cfg.ConvertDLBGL then
    if Gems >= maxg and inv(1796) < 100 and inv(7188) < 100 then
      SendPacket(2, tel .. "dlconvert")
    elseif inv(1796) >= 100 and inv(7188) < 100 then
      SendPacket(2, tel .. "bglconvert")
    elseif inv(7188) >= 100 then
      SendPacket(2, makeBGL)
    end
  end
  if Cfg.ConvertBGL then
    if Gems > maxg and inv(7188) < 100 then
      SendPacket(2, tel .. "bglconvert2")
    elseif inv(7188) >= 100 then
      SendPacket(2, makeBGL)
    end
  end
end

function AutoConsume(id)
  Raw({type = 3, value = id, px = Cfg.pnbX, py = Cfg.pnbY, x = Cfg.pnbX * 32, y = Cfg.pnbY * 32})
  Sleep(500)
end

function TakeConsumes()
  if not Cfg.TakeConsumable then return end
  local a, c, s = Cfg.ConsumeArroz, Cfg.ConsumeClover, Cfg.ConsumeSongpyeon
  ConsumableID = {}
  if a then table.insert(ConsumableID, 4604) end
  if c then table.insert(ConsumableID, 528) end
  if s then table.insert(ConsumableID, 1056) end

  if not InWorld() then
    Sleep(2000)
    return
  end
  if #ConsumableID == 0 then
    Say("`4No ConsumableID configured.")
    return
  end

  for _, cid in ipairs(ConsumableID) do
    if inv(cid) < 1 then
      Taking = true
      GetRemote, CheatOn, CheatOff, MagW = false, false, false, false
      Script.Off("OnVariant", "pnb_variant")
      repeat
        local w = WorldInfo()
        if not w or w.name:upper() ~= Cfg.WorldConsume:upper() then
          SendPacket(3, "action|join_request\nname|" .. Cfg.WorldConsume .. "|\ninvitedWorld|0")
          Sleep(7000)
        else
          Sleep(800)
        end
        Say("`1Taking Consumable...")
        local ok, objects = pcall(Client.GetObjects)
        for _, o in ipairs(ok and objects or {}) do
          if o.id == cid then
            Sleep(500)
            SendPacket(2, "action|dialog_return\ndialog_name|cheats\ncheck_autofarm|0\ncheck_bfg|0\ncheck_gems|1\ncheck_lonely|0\ncheck_ignoreo|0\ncheck_ignoref|0\n")
            Sleep(5000)
            SendPacket(2, "action|respawn\n")
            Sleep(5000)
            SafeFindPath(math.floor(o.pos.x / 32), math.floor(o.pos.y / 32))
            Sleep(Cfg.DelayTake)
            if ghost then
              SendPacket(2, "action|input\n|text|/ghost")
              ghost = false
            end
            Sleep(Cfg.DelayTake)
            if inv(cid) > 0 then
              Say("`2Successfully Take Item! ID=" .. cid)
            end
            if not ghost then
              SendPacket(2, "action|input\n|text|/ghost")
              ghost = true
            end
            Sleep(Cfg.DelayTake)
            break
          end
        end
      until inv(cid) >= 1 or not ScriptRunning
      if not ScriptRunning then return end
      Say("`2Consumables ready! BFG mode active!")
      SafeJoin(WorldName)
      Sleep(7000)
      Taking = false
      Sleep(1200)
      Script.On("OnVariant", "pnb_variant", onvariant)
    end
  end
end

function HandleEmptyRemote()
  if not FirstEmpty then return end
  local now = Script.GetTime()
  if now - LastEmpty > 15000 then FirstEmpty = nil return end
  if NeedReassert and now - LastReassert >= 5000 then
    NeedReassert = false
    LastReassert = now
    CheatTurnOn()
    Say("`9Magplant empty -> Auto Remote")
  end
  if now - FirstEmpty > Cfg.EmptyWaitSec * 1000 then
    FirstEmpty = nil
    Say("`4Auto Remote has no magplant left, stopping")
    SendWebhook(Cfg.WebhookUrl, '{"content": "<@' .. Cfg.DiscordID .. '> ALL Magplants Are Empty!"}')
    ScriptRunning = false
  end
end

function AutoPNB()
  if not ScriptRunning then return end
  if #Mag == 0 then return false end
  if Now < 1 or Now > #Mag then Now = 1 end

  if Ghost and not Cfg.PublicPNB then
    Ghost = false
    Sleep(500)
    SendPacket(2, "action|input\n|text|/ghost")
    if Cfg.IgnoreOther then
      SafeJoin(WorldName)
      Sleep(2000)
    end
  end
  if Ghost and not Cfg.PublicPNB then return end

  if BlockSB and InWorld() then
    BlockSB = false
    Sleep(500)
    SendPacket(2, "action|input\n|text|/radio")
  end
  HandleEmptyRemote()
  if not ScriptRunning then return end
  if AllMagEmpty then
    SendWebhook(Cfg.WebhookUrl, '{"content": "<@' .. Cfg.DiscordID .. '> ALL Magplants Are Empty!"}')
    AllMagEmpty = false
  end

  TakeConsumes()

  if reconnect then
    reconnect = false
    if ReconnectWebhook then
      ReconnectWebhook = false
      SendWebhook(Cfg.WebhookUrl, '{"content": "<@' .. Cfg.DiscordID .. '> ' .. jesc(Nick) .. ' Is Reconnecting!"}')
    end
    Sleep(2000)
    if not InWorld() then
      SafeJoin(WorldName)
      Sleep(7000)
    else
      return
    end
  elseif arroz and Cfg.ConsumeArroz and GetRemote and not Cfg.AutoBuff then
    SafeFindPath(Cfg.pnbX, Cfg.pnbY)
    Sleep(2000)
    AutoConsume(4604)
    return true
  elseif clover and Cfg.ConsumeSongpyeon and GetRemote and not Cfg.AutoBuff then
    SafeFindPath(Cfg.pnbX, Cfg.pnbY)
    Sleep(2000)
    AutoConsume(1056)
    return true
  elseif clover and Cfg.ConsumeClover and GetRemote and not Cfg.AutoBuff then
    SafeFindPath(Cfg.pnbX, Cfg.pnbY)
    Sleep(2000)
    AutoConsume(528)
    return true
  elseif cheat and Cfg.AutoBuyCheats then
    SendPacket(2, "action|dialog_return\ndialog_name|buycheat\ndialog_name|cheats\nbuttonClicked|1\n")
    Sleep(5000)
    MagW = false
    GetRemote = false
    CheatOff = true
    Sleep(2000)
    return true
  end

  if CheatOff and not GetRemote then
    Sleep(500)
    CheatOff = false
    CheatTurnOff()
    if Cfg.PublicPNB and Cfg.RespawnOnStop then
      Sleep(800)
      SendPacket(2, "action|respawn\n")
      Sleep(3000)
    end
    Say("`1Stop PnB! Last Magplant #" .. Now)
    CheatStopped = true
  end

  if GetRemote then
    if not Taking then
      local lx, ly = MyPos()
      if lx then
        if lx ~= Cfg.pnbX or ly ~= Cfg.pnbY then
          if not WalkOffSent then
            WalkOffSent = true
            CheatTurnOff()
          end
          SafeFindPath(Cfg.pnbX, Cfg.pnbY)
          PendingCheatOn = true
          CheatOn = false
        else
          WalkOffSent = false
          if PendingCheatOn then
            PendingCheatOn = false
            CheatOn = true
            Say("`1Arrived at PnB position")
            if Cfg.VerticalPNB then
              FindTPVertical(Cfg.pnbX, Cfg.pnbY)
            elseif Cfg.MirrorPNB then
              FindTPLeft(Cfg.pnbX, Cfg.pnbY)
            end
            Sleep(2000)
          end
          if CheatOn then
            CheatOn = false
            CheatTurnOn()
            Say("`1Start PnB! X: `2" .. Cfg.pnbX .. "`1 Y: `2" .. Cfg.pnbY)
          end
          AutoSuck()
          AutoDontDrop()
          AutoConvert()
        end
      end
      CheckTime()
    end
    return true
  end

  local m = Mag[Now]
  if m and CheatStopped then
    Sleep(500)
    if WrenchFor ~= Now then WrenchFor, WrenchTry, PathTry = Now, 0, 0 end
    local function NextMag(msg)
      Say(msg)
      Now = (Now == #Mag) and 1 or (Now + 1)
      WrenchFor, WrenchTry, PathTry = nil, 0, 0
    end
    local tx, ty = m.x, m.y - 1
    if Cfg.PublicPNB and not IsTileWalkable(tx, ty) then
      NextMag("`1Magplant blocked, next")
      return true
    end
    if WrenchTry >= 8 then
      NextMag("`4Wrench got no response, next magplant")
      return true
    end
    if PathTry >= 6 then
      NextMag("`4Can't reach magplant, next")
      return true
    end
    local cx, cy = MyPos()
    if cx ~= tx or cy ~= ty then
      SafeFindPath(tx, ty)
      Sleep(500)
      cx, cy = MyPos()
    end
    if cx == tx and cy == ty then
      WrenchTry = WrenchTry + 1
      Wrench(m.x, m.y, WrenchTry)
      Sleep(1500)
    else
      PathTry = PathTry + 1
    end
    return true
  elseif m then
    Sleep(500)
  elseif not m then
    Now = (Now == #Mag) and 1 or (Now + 1)
    Say("`1Magplant missing, next")
    local nm = Mag[Now]
    if nm then
      SafeFindPath(nm.x, nm.y - 1)
      return true
    end
  end
  return false
end

local function DialogAt(s, x, y)
  local dx = s:match("embed_data|x|(%-?%d+)") or s:match("\nx|(%-?%d+)")
  local dy = s:match("embed_data|y|(%-?%d+)") or s:match("\ny|(%-?%d+)")
  if dx and dy then return tonumber(dx) == x and tonumber(dy) == y end
  return (s:find(x .. "\n", 1, true) and s:find(y .. "\n", 1, true)) and true or false
end

local function onvariant_impl(var)
  local ev, v1, v2 = var[0], var[1], var[2]
  local s1 = type(v1) == "string" and v1 or nil

  if not InWorld() then
    reconnect = true
    if Cfg.WebhookPNB then ReconnectWebhook = true end
  elseif ev == "OnSDBroadcast" then
    SendPacket(2, "action|input\n|text|/radio")
  elseif s1 and s1:find("backpack slots.") then
    Ghost = not s1:find("Ghost in the shell")
    arroz = not s1:find("Breaking Gems")
    clover = not s1:find("Lucky!")
    cheat = not s1:find("Cheater")
    return true
  elseif ev == "OnConsoleMessage" and s1 then
    if s1:find("Radio enabled,") then BlockSB = true end
    if s1:find("Where would you like to go") then
      MagW, GetRemote = false, false
      JoinRequested = true
    end
    if s1:find("World Locked") then
      MagW, GetRemote = false, false
      if not s1:find(WorldName, 1, true) then
        Ghost = true
        JoinRequested = true
      end
    end
    if s1:find("Your luck has worn off.") then clover = true end
    if s1:find("Your stomach's rumbling.") then arroz = true end
    if s1:find("boringness.") then cheat = true end
    if s1:find("You're luckier than before!") then clover = false end
    if s1:find("chance of a gem") then arroz = false end
    if s1:find("cheater!") then cheat = false end
  end

  if not MagW and not Ghost then MagW = true end

  if ev == "OnTalkBubble" then
    if type(v2) == "string" then
      if v2:find("You received a MAGPLANT 5000 Remote") then
        GetRemote = true
        PendingCheatOn = true
        Taking = false
        FirstEmpty = nil
      elseif v2:find("The MAGPLANT 5000 is empty") and not CheatOff then
        if Cfg.AutoRemote and Cfg.EmptyUseAutoRemote then
          local t = Script.GetTime()
          LastEmpty = t
          if not FirstEmpty then FirstEmpty = t end
          NeedReassert = true
        else
          GetRemote = false
          CheatOff = true
          MagW = false
          CheatStopped = false
          Taking = true
        end
      end
    end
  elseif ev == "OnDialogRequest" and not GetRemote then
    if #Mag == 0 then return false end
    local cur = Mag[Now]
    if not cur or not s1 then return false end
    local atCur = DialogAt(s1, cur.x, cur.y)
    if atCur then WrenchTry, PathTry = 0, 0 end
    if s1:find("ACTIVE") and atCur then
      if s1:find("Seed") then
        Now = (Now == #Mag) and 1 or (Now + 1)
      else
        SendPacket(2, "action|dialog_return\ndialog_name|magplant_edit\nx|" .. cur.x ..
                      "|\ny|" .. cur.y .. "|\nbuttonClicked|getRemote\n")
      end
    elseif (s1:find("DISABLED") or s1:find("The machine is disabled.")) and atCur then
      if Cfg.WebhookPNB and Now == #Mag then AllMagEmpty = true end
      Now = (Now == #Mag) and 1 or (Now + 1)
    end
  end
  return false
end

function onvariant(var)
  local ok, r = pcall(onvariant_impl, var)
  if not ok then
    Say("`4Hook error: " .. tostring(r))
    return false
  end
  return r == true
end

function Nmek(num)
  local formatted = tostring(math.floor(tonumber(num) or 0))
  local k
  while true do
    formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then break end
  end
  return formatted
end

function FTime(sec)
  local days = math.floor(sec / 86400)
  local hours = math.floor(sec % 86400 / 3600)
  local minutes = math.floor(sec % 3600 / 60)
  local seconds = math.floor(sec % 60)
  if days > 0 then
    return string.format("%s day %s hour %s minute %s second", days, hours, minutes, seconds)
  elseif hours > 0 then
    return string.format("%s hour %s minute %s second", hours, minutes, seconds)
  elseif minutes > 0 then
    return string.format("%s minute %s second", minutes, seconds)
  end
  return string.format("%s second", seconds)
end

function SendInfoPNB()
  math.randomseed(os.time())
  PGems = obj(PinkGems)
  BGems = obj(BlackGems)
  IGems = obj(InfinityGems)
  local Gems = GetGems()
  local Songpyeon, Clover, Arroz = inv(1056), inv(528), inv(4604)
  local BLK, BGL, DL = inv(11550), inv(7188), inv(1796)

  local earned = (BGL * 100 + DL) - StartTotalLocks
  if earned < 0 then earned = 0 end
  EarnedBGLTotal = math.floor(earned / 100)
  EarnedDLTotal = earned % 100

  local function F(name, value)
    return '{"name":"' .. name .. '","value":"' .. value .. '","inline":false}'
  end
  local fields = {
    F("<a:online_1:1471370661137088613> Account", "<:npc:1471371280786788405> " .. jesc(Nick)),
    F("<a:worlds:1474160169817477173> World", jesc(WorldName)),
    F("<:magplant:1471371093213319273> Magplant", Now .. " of " .. #Mag),
    F("<:antidote:1484086483173245061> Consumables",
      Songpyeon .. " <:songpyeon:1484086773540847719> " .. Clover .. " <:clover:1471370462419488872> " ..
      Arroz .. " <:arroz:1471370410334621771> "),
    F("<a:gems:1474161068623397022> Total Locks",
      BLK .. " <a:blk_1:1471370219644784640> " .. BGL .. " <a:bgls_1:1471368364743065741> " ..
      DL .. " <a:DLS:1471368227002257490> "),
    F("<:gems:1484087135815598100> Current Gems", Nmek(Gems)),
    F("<:Bgems:1471367283376001127> Gems Drop",
      Nmek(BGems) .. " <:bgems:1412036304715120791> |•| " .. Nmek(PGems) .. " <:pgems:1484100621614452766>"),
    F("<:gems:1341127516894789666> Dropped IGems", Nmek(IGems) .. " IGems"),
    F("<a:cuan:1471372894134079529> Earned",
      Nmek(EarnedBGLTotal) .. " <a:bgls_1:1471368364743065741> " ..
      Nmek(EarnedDLTotal) .. " <a:DLS:1471368227002257490> "),
    F("⏱️ Uptime", FTime(os.time() - StartTime)),
  }
  local payload = '{"embeds":[{"author":{"name":"PNB CGT Log V3.4"},"fields":[' ..
    table.concat(fields, ",") .. '],"color":' .. math.random(0, 16777215) .. '}]}'
  SendWebhook(Cfg.WebhookUrl, payload)
end

function dialog(teks)
  local ok, me = pcall(GetLocal)
  local name = ok and me and tostring(me.name or ""):match("%S+") or ""
  local d = "add_label_with_icon|big|`9PNB `eCGT `6V3.4|left|16224|\n" ..
            "add_spacer|small|\n" ..
            "add_textbox|GrowID : " .. name .. "|\n" ..
            "add_textbox|World : `2" .. WorldName .. "|\n" ..
            "add_textbox|Position BFG : `6" .. Cfg.pnbX .. " `0, `6" .. Cfg.pnbY .. "|\n" ..
            "add_textbox|`8" .. teks .. "|\n" ..
            "add_quick_exit|\nend_dialog|pnb_info||OK|"
  pcall(Client.ShowDialog, d)
end

function ApplyGUI()
  for _, k in ipairs({"BackgroundID", "pnbX", "pnbY", "TelX", "TelY", "MaxGems", "DelayTake", "SuckThreshold", "SuckCooldown", "BGemID", "PGemID", "IGemID", "EmptyWaitSec"}) do
    Cfg[k] = toint(Cfg[k])
  end
  Cfg.WorldConsume = tostring(Cfg.WorldConsume or "")
  Cfg.WebhookUrl = tostring(Cfg.WebhookUrl or "")
  Cfg.DiscordID = tostring(Cfg.DiscordID or ""):gsub("%D", "")
  if Cfg.DiscordID == "" then Cfg.DiscordID = "0" end
  RefreshChecks()
  RecalcMag()
  UpdatePaywallBlocks(false)
end

function StartPNB()
  local w = WorldInfo()
  if not w then
    TextOverlay("`4Join a world first")
    return
  end
  WorldName = w.name
  if #Mag == 0 then
    dialog("`7Please Set Magplant Background")
    return
  end
  if Cfg.WebhookPNB and type(MakeRequest) ~= "function" then
    Say("`4MakeRequest unavailable, webhook off")
    Cfg.WebhookPNB = false
    UI.Set("c_WebhookPNB", {value = false})
  end

  dialog("`8Please Wait A Moment...")
  Sleep(200)

  local ok, me = pcall(GetLocal)
  local clean = ok and me and tostring(me.name or ""):gsub("`(%S)", "") or ""
  Nick = clean:match("%S+") or "Unknown"
  local function ItemId(name)
    local okI, info = pcall(GetItemInfo, name)
    return (okI and type(info) == "table" and info.id) or 0
  end
  local function FirstId(manual, names)
    if manual and manual > 0 then return manual end
    for _, n in ipairs(names) do
      local id = ItemId(n)
      if id > 0 then return id end
    end
    return 0
  end
  PinkGems = FirstId(Cfg.PGemID, {"Pink Gemstone", "Pink Gems", "Pink Gem"})
  BlackGems = FirstId(Cfg.BGemID, {"Black Gems", "Black Gem", "Black Gemstone"})
  InfinityGems = FirstId(Cfg.IGemID, {"Infinity Gems", "Infinity Gem", "Infinity Gemstone"})
  Say("Gem IDs: Black=" .. BlackGems .. " Pink=" .. PinkGems .. " Infinity=" .. InfinityGems ..
      ((BlackGems == 0 or InfinityGems == 0) and " `4(0 = not found, use Debug Objects + set ID)" or ""))
  LastSuck, SuckBase = -100000, 0
  LastDDCheck, LastGemObjs, LastDDForce = -100000, 0, 0
  WrenchFor, WrenchTry, PathTry = nil, 0, 0
  FirstEmpty, LastEmpty, NeedReassert = nil, 0, false
  PathFails, PathBlockUntil, WalkOffSent = 0, {}, false
  Say("`9Info: GrowID, world & version dikirim ke pembuat script sebagai notifikasi pemakaian script.")
  SendUsageNotice()
  StartTime = os.time()
  LastTime = StartTime
  StartTotalLocks = inv(7188) * 100 + inv(1796)
  EarnedBGLTotal, EarnedDLTotal = 0, 0
  RefreshChecks()

  Now = 1
  BlockSB = true
  reconnect, GetRemote = false, false
  CheatOff, CheatOn, CheatStopped = false, false, true
  Ghost, MagW, ghost = false, false, true
  PendingCheatOn, Taking, JoinRequested = false, false, false
  PASSED_BLOCKS = {}
  Script.Off("OnVariant", "pnb_variant")
  Sleep(1000)

  if Cfg.AutoBuyCheats then
    SendPacket(2, "action|dialog_return\ndialog_name|buycheat\ndialog_name|cheats\nbuttonClicked|1\n")
    Sleep(1000)
  end
  if BlockSB then
    BlockSB = false
    Sleep(500)
    SendPacket(2, "action|input\n|text|/radio")
    Sleep(1000)
  end

  Script.On("OnVariant", "pnb_variant", onvariant)
  Sleep(1000)
  CheatTurnOff()
  Say("`1PnB On Progress...")
  Sleep(1000)
  if Cfg.PublicPNB then
    SendPacket(2, "action|respawn\n")
    Sleep(3000)
  end

  while ScriptRunning do
    Sleep(500)
    UpdateStatus()
    if JoinRequested then
      JoinRequested = false
      SafeJoin(WorldName)
      Sleep(5000)
    end
    AutoPNB()
  end

  Script.Off("OnVariant", "pnb_variant")
  pcall(CheatTurnOff)
  Sleep(300)
  pcall(CheatTurnOff)
  Say("`4Stopped")
end

local WIN = "pnb"
local Bound, Buttons = {}, {}
local uid = 0
local function nid(p)
  uid = uid + 1
  return p .. uid
end

UI.Window(WIN, {title = "PNB Main V3.4", width = 380, height = 560})

local function Head(text)
  UI.Separator(nid("sep"), {parent = WIN})
  UI.Text(nid("hd"), {parent = WIN, text = text})
end

local function Check(key, label)
  local id = "c_" .. key
  UI.Checkbox(id, {parent = WIN, text = label, value = Cfg[key] and true or false})
  Bound[id] = {key = key, kind = "bool"}
end

local function Field(key, label, kind)
  local id = "f_" .. key
  UI.Text(nid("lb"), {parent = WIN, text = label})
  UI.Input(id, {parent = WIN, value = tostring(Cfg[key])})
  Bound[id] = {key = key, kind = kind}
end

local function Btn(id, label, fn, same)
  if same then UI.SameLine(nid("sl"), {parent = WIN}) end
  UI.Button(id, {parent = WIN, text = label})
  Buttons[id] = fn
end

local function RefreshUI()
  for id, b in pairs(Bound) do
    if b.kind == "bool" then
      UI.Set(id, {value = Cfg[b.key] and true or false})
    else
      UI.Set(id, {value = tostring(Cfg[b.key])})
    end
  end
end

Btn("b_start", "Start PNB", function()
  if ScriptRunning or StartRequested then
    TextOverlay("`9Script already running")
  else
    StartRequested = true
  end
end)
Btn("b_stop", "Stop PNB", function()
  if ScriptRunning then
    ScriptRunning = false
    GetRemote, CheatOn, PendingCheatOn = false, false, false
    CheatTurnOff()
    TextOverlay("`4Stop requested")
  else
    TextOverlay("`9Script not running")
  end
end, true)
Btn("b_defaults", "Defaults", function()
  for k, v in pairs(Defaults) do Cfg[k] = v end
  RefreshChecks()
  RefreshUI()
  TextOverlay("`2Defaults restored")
end, true)

UI.Text("status", {parent = WIN, text = "Stopped"})

Head("Magplant & Background")
Field("BackgroundID", "BackgroundID", "int")

Head("Mode PNB")
Check("VerticalPNB", "VerticalPNB (Mneck)")
Check("PublicPNB", "PublicPNB")
Check("BypassPaywall", "Bypass Paywall")
Check("BypassWayBlock", "Bypass One-Way Block")
Check("MirrorPNB", "MirrorPNB")

Head("Positions (PNB / TEL)")
Field("pnbX", "pnbX", "int")
Field("pnbY", "pnbY", "int")
Field("TelX", "TelX", "int")
Field("TelY", "TelY", "int")
Btn("b_cap_pnb", "Capture PNB pos", function()
  local x, y = MyPos()
  if not x then TextOverlay("`4Can't read position") return end
  Cfg.pnbX, Cfg.pnbY = x, y
  UI.Set("f_pnbX", {value = tostring(x)})
  UI.Set("f_pnbY", {value = tostring(y)})
  TextOverlay("`2PNB pos saved: " .. x .. ", " .. y)
end)
Btn("b_cap_tel", "Capture TEL pos", function()
  local x, y = MyPos()
  if not x then TextOverlay("`4Can't read position") return end
  Cfg.TelX, Cfg.TelY = x, y
  UI.Set("f_TelX", {value = tostring(x)})
  UI.Set("f_TelY", {value = tostring(y)})
  TextOverlay("`2TEL pos saved: " .. x .. ", " .. y)
end, true)

Head("Conversion")
Check("AutoBuyWL", "Auto Buy WL")
Check("ConvertBGL", "Convert BGL")
Check("ConvertDLBGL", "Convert DL to BGL")
Field("MaxGems", "Max Earn Gems (Auto Convert)", "int")

Head("Auto Consumable")
Check("ConsumeArroz", "ConsumeArroz")
Check("ConsumeClover", "ConsumeClover")
Check("ConsumeSongpyeon", "ConsumeSongpyeon")

Head("Auto Take Consumable")
Check("TakeConsumable", "TakeConsumable")
Field("WorldConsume", "World Consume (Dropped)", "str")
Field("DelayTake", "Delay Take (ms)", "int")

Head("Auto Cheat")
Check("AutoBuff", "Auto Buff (Consume)")
Check("AutoRemote", "Auto Magplant Remote")
Check("EmptyUseAutoRemote", "Empty magplant: use Auto Remote (no walking)")
Field("EmptyWaitSec", "Stop if still empty after (sec)", "int")
Check("RespawnOnStop", "Respawn after cheats/magplant stop")

Head("Other")
Check("AutoBuyCheats", "AutoBuyCheats")
Check("SuckBgems", "SuckBgems")
Field("SuckThreshold", "Suck if BGems >=", "int")
Field("SuckCooldown", "Suck cooldown (ms)", "int")
Check("NoGemsDrop", "NoGemsDrop")
Check("AutoDontDrop", "Auto Don't Drop Gems (re-apply)")
Field("BGemID", "Black Gems ID (0 = auto)", "int")
Field("PGemID", "Pink Gems ID (0 = auto)", "int")
Field("IGemID", "Infinity Gems ID (0 = auto)", "int")
Btn("b_suck_now", "Suck Now", function()
  if not InWorld() then TextOverlay("`4Join a world first") return end
  AutoSuck(true)
end)
Btn("b_dbg_obj", "Debug Objects", DebugObjects, true)
Btn("b_test_wrench", "Test Wrench", function()
  if not InWorld() then TextOverlay("`4Join a world first") return end
  if #Mag == 0 then RecalcMag() end
  local m = Mag[Now] or Mag[1]
  if not m then TextOverlay("`4No magplant found (check BackgroundID)") return end
  Wrench(m.x, m.y, 1)
  Say("Test wrench sent to " .. m.x .. "," .. m.y)
end, true)
Check("IgnoreOther", "IgnoreOther")

Head("Webhook")
Check("WebhookPNB", "Enable WebhookPNB")
Field("WebhookUrl", "Webhook URL", "str")
Field("DiscordID", "Discord ID (mention)", "str")

local function OnSetting(key)
  if key == "BypassPaywall" or key == "BypassWayBlock" then
    UpdatePaywallBlocks(true)
  end
  RefreshChecks()
end

Script.On("OnUI", "pnb_ui", function(id, event, value)
  local b = Bound[id]
  if b then
    if event == "close" then return end
    local c = UI.Get(id)
    local val = c and c.value
    if val == nil then val = value end
    if b.kind == "bool" then
      Cfg[b.key] = truthy(val)
    elseif b.kind == "int" then
      local n = tonumber(val)
      if n then Cfg[b.key] = math.floor(n) end
    else
      Cfg[b.key] = tostring(val or "")
    end
    OnSetting(b.key)
  elseif event == "click" and Buttons[id] then
    Buttons[id]()
  end
end)

local lastStatus = ""
function UpdateStatus()
  local s = (ScriptRunning and "Running" or "Stopped") ..
            " | Mag " .. Now .. "/" .. #Mag ..
            " | PNB " .. Cfg.pnbX .. "," .. Cfg.pnbY ..
            " | TEL " .. Cfg.TelX .. "," .. Cfg.TelY
  if s ~= lastStatus then
    lastStatus = s
    UI.Set("status", {text = s})
  end
end

RefreshChecks()
UpdatePaywallBlocks(false)

while true do
  if StartRequested then
    StartRequested = false
    if not ScriptRunning then
      ScriptRunning = true
      ApplyGUI()
      StartPNB()
      ScriptRunning = false
    end
  end
  UpdateStatus()
  Sleep(250)
end
