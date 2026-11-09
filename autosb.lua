-- SCRIPT BOTHAX PNB BY @4_Rab --
-- AUTO SB 4 MODE --
-- YOU BETTER USE BOOSTER ACC --

CONFIGURATION = {
mode_sb = "counterdown" -- choose use (timerup/timerdown/counterup/counterdown)
}

Text = "`1FREE/RENT BFG POG GO `8B4 `2USE IGL + XENO `9UNLIMITED STOCKS AND ROOMS `5#ALWAYSPTHT" -- Write your text here
name = "@Daein" -- Write your name here
TotalSB = 9999 -- How many time u want to SB
timers = 60.0 -- Timer is count in minutes  (kelipatan/multiple 1.5)
Warp_to = "B4" -- WORLD NAME TO WARP IF SB IS DONE

-- WEBHOOK SETTINGS -- 
whUse = false -- true or false (Usage; Sending Information throughout Discord)
discordID = "" -- Discord ID (Usage; Pinging you when after sending a information)
whUrl = "https://discord.com/api/webhooks/1183352566361374850/_1OYhnwERvibC4RXLBf2GpU8sGrDo5rPhtw9u-VIFoFBkmaxF8voeuE801aCTX6ebL_g" -- Discord Webhook Url (Usage; Using the Webhook Url It allows you to send a information)

-- [DON'T TOUCH THE SETTINGS BELOW!] --

currentTime = os.time() -- Don't Touch --
player = GetLocal().name -- Don't Touch --
currentWorld = GetWorld().name -- Don't Touch --
currentGem = GetPlayerInfo().gems -- Don't Touch --

-- [DON'T CHANGE THE SCRIPT IDIOT!] --

AddHook("onvariant", "Kaede", function(var)
    if var[0] == "OnSDBroadcast" then 
        return true
    end
end)

local function warnText(text)
    text = text
    packet = {}
    packet[0] = "OnAddNotification"
    packet[1] = "interface/atomic_button.rttex"
    packet[2] = text
    packet[3] = "audio/hub_open.wav"
    packet[4] = 0
    SendVariantList(packet)
    return true
end

local function FormatNumber(num)
    num = math.floor(num + 0.5)

    local formatted = tostring(num)
    local k = 3
    while k < #formatted do
        formatted = formatted:sub(1, #formatted - k) .. "," .. formatted:sub(#formatted - k + 1)
        k = k + 4
    end

    return formatted
end

local function removeColorAndSymbols(str)
    cleanedStr = string.gsub(str, "`(%S)", '')
    cleanedStr = string.gsub(cleanedStr, "`{2}|(~{2})", '')
    return cleanedStr
end

if GetWorld() == nil then
    username = removeColorAndSymbols(player)
else
    username = removeColorAndSymbols(GetLocal().name)
end

time = os.time()
local function playerHook(info)
    if whUse then
        oras = os.time() - time
        local script = [[
            $webHookUrl = "]].. whUrl ..[["
            $title = "<:rotating_light:1168024326386237470> **Super Broadcast Information**"
            $date = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), 'Singapore Standard Time').ToString('g')
            $cpu = (Get-WmiObject win32_processor | Measure-Object -property LoadPercentage -Average | Select Average).Average
            $RAM = Get-WMIObject Win32_PhysicalMemory | Measure -Property capacity -Sum | %{$_.sum/1Mb} 
            $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $(Get-NetConnectionProfile | Select-Object -ExpandProperty InterfaceIndex) | Select-Object -ExpandProperty IPAddress
            $thumbnailObject = @{
                url = ""
            }
            $footerObject = @{
                text = "Date: ]]..(os.date("!%A %b %d, %Y | Time: %I:%M %p ", os.time() + 8 * 60 * 60))..[[ | @4_Rab"
            }
            
            $fieldArray = @(

            @{
                name = "<:bangbang:1187766612011520161> Information"
                value = "World : **]].. currentWorld ..[[**
                Status : **]].. info ..[[**"
                inline = "false"
            }

            @{
                name = "<:bust_in_silhouette:1178875116348768326> Player Name"
                value = "]].. username ..[["
                inline = "false"
            }
  
            @{
                name = "<:gem:1178876023253778462> Total Gems"
                value = "Current Gems: ]].. FormatNumber(GetPlayerInfo().gems) ..[["
                inline = "false"
            }
  
            @{
                name = "<:stopwatch:1178878505283485817> Super Broadcast UpTime"
                value = "]].. math.floor(oras/86400) ..[[ Days ]].. math.floor(oras%86400/3600) ..[[ Hours ]].. math.floor(oras%86400%3600/60) ..[[ Minutes ]].. math.floor(oras%3600%60) ..[[ Seconds"
                inline = "false"
            }

          $Body = @{
          'content' = '<@]].. discordID ..[[>'
          }
      
          )
          $embedObject = @{
          title = $title
          description = $desc
          footer = $footerObject
          thumbnail = $thumbnailObject
          color = "]] ..math.random(1000000, 9999999).. [["
      
          fields = $fieldArray
      }
      $embedArray = @($embedObject)
      $payload = @{
      avatar_url = "https://images7.alphacoders.com/944/944843.png"
      username = "SB SC by Rab"
      content = "<:white_check_mark:1168023732955119616> <@]].. discordID ..[[>"
      embeds = $embedArray
      }
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Invoke-RestMethod -Uri $webHookUrl -Body ($payload | ConvertTo-Json -Depth 4) -Method Post -ContentType 'application/json'
      ]]
      local pipe = io.popen("powershell -command -", "w")
      pipe:write(script)
      pipe:close()
    end
end

playerHook("Script is now Running!")

warnText("`4DO NOT RESELL SCRIPT! `6DC: [`5@fourdan93`6]")

local function counterup()
if CONFIGURATION.mode_sb == "counterup" then
    count = 0
    for i = 1, TotalSB do
        SendPacket(2, "action|input\ntext|/sb " .. Text)
        count = count + 1
        Sleep(1000)
        playerHook("Broadcasting")
        SendPacket(2, "action|input\ntext|`1Super Broadcast Has Been Sent (megaphone) `9SB Counter: " .. count .. "/" .. TotalSB .. " `5[DC: @fourdan93]")
        Sleep(91000)
     if count == TotalSB then
        SendPacket(2, "action|input\ntext|`^SB Done!")
        Sleep(1000)
        SendPacket(3, "action|join_request\nname|"..Warp_to.."\ninvitedWorld|0")
        Sleep(99999999)
end
end
end
end

local function counterdown()
if CONFIGURATION.mode_sb == "counterdown" then
    count = TotalSB
    for i = 1, TotalSB do
        SendPacket(2, "action|input\ntext|/sb " .. Text)
        count = count - 1
        Sleep(1000)
        playerHook("Broadcasting")
        SendPacket(2, "action|input\ntext|`1Super Broadcast Has Been Sent (megaphone) `9SB Counter: " .. count .. " SB Left `5[DC: @fourdan93]")
        Sleep(91000)
    if count == 0 then
        SendPacket(2, "action|input\ntext|`^SB Done!")
        Sleep(1000)
        SendPacket(3, "action|join_request\nname|"..Warp_to.."\ninvitedWorld|0")
        Sleep(99999999)
end
end
end
end

local function timercountdown()
if CONFIGURATION.mode_sb == "timerdown" then
    count = timers + 1.5
    for i = 1, timers do
        SendPacket(2, "action|input\ntext|/sb " .. Text)
        count = count - 1.5
        Sleep(1000)
        playerHook("Broadcasting")
        SendPacket(2, "action|input\ntext|`1Super Broadcast Has Been Sent (megaphone) `9SB Counter: " .. count .. " Minutes Left `5[DC: @fourdan93]")
        Sleep(91000)
    if count == 0 then
        SendPacket(2, "action|input\ntext|`^SB Done!")
        Sleep(1000)
        SendPacket(3, "action|join_request\nname|"..Warp_to.."\ninvitedWorld|0")
        Sleep(999999999)
end
end
end
end

local function timercountup()
if CONFIGURATION.mode_sb == "timerup" then
    count = -1.5
    for j = 1, timers do
        SendPacket(2, "action|input\ntext|/sb " .. Text)
        count = count + 1.5
        Sleep(1000)
        playerHook("Broadcasting")
        SendPacket(2, "action|input\ntext|`1Super Broadcast Has Been Sent (megaphone) `9Time: " .. count .. " Minutes / " .. timers .. " Minutes `5[DC: @fourdan93]")
        Sleep(91000)
    if count == timers then
        SendPacket(2, "action|input\ntext|`^SB Done!")
        Sleep(1000)
        SendPacket(3, "action|join_request\nname|"..Warp_to.."\ninvitedWorld|0")
        Sleep(999999999)
end
end
end
end

local function start()
SendPacket(2, "action|input\ntext|`6[Premium Script by `b@Daein`6] [DC : `5@fourdan93`6]")
Sleep(2000)
SendPacket(2, "action|input\ntext|`9Super Broadcast by `b" .. name .. " `9START!")
Sleep(2000)
end

start()
while true do
if CONFIGURATION.mode_sb == "counterup" then
counterup()
elseif CONFIGURATION.mode_sb == "counterdown" then
counterdown()
elseif CONFIGURATION.mode_sb == "timerup" then
timercountup()
elseif CONFIGURATION.mode_sb == "timerdown" then
timercountdown()
end
end
