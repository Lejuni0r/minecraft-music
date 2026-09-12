--[[
TRMK TV - YouTube/YouCube video player for CC:Tweaked
Single-file client for Advanced Monitor + Speaker.

Protocol compatibility: YouCube proof-of-concept API / 32Vid raw frames.
Inspired by CC-YouCube/client and MCJack123/sanjuuni.
This implementation is original glue/UI code and keeps the project attribution.

Requirements:
  - CC:Tweaked with HTTP/WebSocket enabled
  - Advanced Monitor (recommended)
  - Speaker for audio
  - A working YouCube-compatible WebSocket backend for YouTube/search input

Usage:
  TRMK_TV.lua https://www.youtube.com/watch?v=...
  TRMK_TV.lua "search words"
  TRMK_TV.lua --server wss://example.net <url-or-search>
  TRMK_TV.lua --volume 1.0 <url-or-search>

Controls while playing:
  SPACE  pause/resume
  Q      stop
  -      volume down
  =/+    volume up
  Monitor touch: controles si ecran assez grand; pause/reprise plein ecran sinon
]]

local VERSION = "1.1.0"
local CONTROL_EVENT = "trmk_tv_control"

local function fail(msg)
    term.setTextColor(colors.red)
    print("TRMK TV: " .. tostring(msg))
    term.setTextColor(colors.white)
    error(msg, 0)
end

if not http or not http.websocket then
    fail("HTTP/WebSocket API indisponible. Active HTTP dans la config CC:Tweaked.")
end

-- -------------------------------------------------------------------------
-- Args / settings
-- -------------------------------------------------------------------------
local argv = { ... }
local opts = {
    volume = tonumber(settings and settings.get("trmk.tv.volume")) or 1.0,
    server = settings and settings.get("trmk.tv.server") or nil,
    scale = tonumber(settings and settings.get("trmk.tv.scale")) or 0.5,
}
local queryParts = {}
local i = 1
while i <= #argv do
    local a = argv[i]
    if a == "--server" and argv[i + 1] then
        opts.server = argv[i + 1]
        i = i + 2
    elseif a:match("^%-%-server=") then
        opts.server = a:match("^%-%-server=(.+)$")
        i = i + 1
    elseif a == "--volume" and argv[i + 1] then
        opts.volume = tonumber(argv[i + 1]) or opts.volume
        i = i + 2
    elseif a:match("^%-%-volume=") then
        opts.volume = tonumber(a:match("^%-%-volume=(.+)$")) or opts.volume
        i = i + 1
    elseif a == "--scale" and argv[i + 1] then
        opts.scale = tonumber(argv[i + 1]) or opts.scale
        i = i + 2
    elseif a:match("^%-%-scale=") then
        opts.scale = tonumber(a:match("^%-%-scale=(.+)$")) or opts.scale
        i = i + 1
    else
        queryParts[#queryParts + 1] = a
        i = i + 1
    end
end
opts.volume = math.max(0, math.min(3, opts.volume))
opts.scale = math.max(0.5, math.min(5, opts.scale))
local input = #queryParts > 0 and table.concat(queryParts, " ") or nil

-- -------------------------------------------------------------------------
-- Peripherals
-- -------------------------------------------------------------------------
local monitor = peripheral.find("monitor")
if not monitor then fail("Aucun monitor detecte.") end
if monitor.isColor and not monitor.isColor() then
    fail("Un Advanced Monitor couleur est recommande/requis pour la video.")
end
pcall(monitor.setTextScale, opts.scale)

local speaker = peripheral.find("speaker")
local haveAudio = speaker ~= nil

local mw, mh
local videoH
local showControlBar
local compactScreen

local function refreshLayout()
    mw, mh = monitor.getSize()
    if mw < 4 or mh < 3 then
        fail(("Monitor trop petit (%dx%d)."):format(mw, mh))
    end

    -- Sur les petits ecrans (notamment un Advanced Monitor 1x1 = 15x10
    -- a l'echelle 0.5), toute la surface est reservee a la video.
    -- A partir d'une taille confortable, on reserve la derniere ligne
    -- pour des controles tactiles.
    compactScreen = (mw < 24 or mh < 12)
    showControlBar = not compactScreen
    videoH = showControlBar and (mh - 1) or mh
end

refreshLayout()

-- Save monitor palette so we can restore it.
local savedPalette = {}
for p = 0, 15 do
    local ok, r, g, b = pcall(monitor.getPaletteColor, 2 ^ p)
    if ok then savedPalette[p] = { r, g, b } end
end

local function restoreMonitor()
    for p, rgb in pairs(savedPalette) do
        pcall(monitor.setPaletteColor, 2 ^ p, rgb[1], rgb[2], rgb[3])
    end
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

local function mwrite(x, y, text, fg, bg)
    text = tostring(text or "")
    if y < 1 or y > mh or x > mw then return end
    if x < 1 then
        text = text:sub(2 - x)
        x = 1
    end
    if #text > mw - x + 1 then text = text:sub(1, mw - x + 1) end
    monitor.setCursorPos(x, y)
    monitor.setTextColor(fg or colors.white)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.write(text)
end

local function mcenter(y, text, fg, bg)
    text = tostring(text or "")
    mwrite(math.max(1, math.floor((mw - #text) / 2) + 1), y, text, fg, bg)
end

local function clearMonitor(bg)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
end

local function splash(title, subtitle, status)
    clearMonitor(colors.black)

    -- Placement adaptatif : pas de coordonnees fixes qui debordent sur
    -- un petit monitor, tout en gardant un rendu aere sur un grand ecran.
    if mh <= 5 then
        mcenter(1, "TRMK TV", colors.red)
        if title then mcenter(math.min(2, mh), title, colors.white) end
        if status then mcenter(mh, status, colors.yellow) end
        return
    end

    local yLogo = math.max(1, math.floor(mh * 0.16))
    local yTitle = math.max(yLogo + 1, math.floor(mh * 0.38))
    local ySub = math.max(yTitle + 1, math.floor(mh * 0.58))
    local yStatus = math.min(mh, math.max(ySub + 1, math.floor(mh * 0.80)))

    mcenter(yLogo, "TRMK TV", colors.red)
    mcenter(yTitle, title or "", colors.white)
    if subtitle and ySub <= mh then mcenter(ySub, subtitle, colors.lightGray) end
    if status and yStatus <= mh then mcenter(yStatus, status, colors.yellow) end
end

-- -------------------------------------------------------------------------
-- JSON + Base64
-- -------------------------------------------------------------------------
local jsonDecode = textutils.unserialiseJSON or textutils.unserializeJSON
local jsonEncode = textutils.serialiseJSON or textutils.serializeJSON
if not jsonDecode or not jsonEncode then fail("JSON API indisponible dans cette version de CC:Tweaked.") end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64map = {}
for n = 1, #B64 do b64map[B64:byte(n)] = n - 1 end

local function base64decode(s)
    local out = {}
    local oi = 1
    local len = #s
    local pos = 1
    while pos <= len do
        local a = b64map[s:byte(pos)]
        local b = b64map[s:byte(pos + 1)]
        local cbyte = s:byte(pos + 2)
        local dbyte = s:byte(pos + 3)
        if not a or not b then break end
        local c = cbyte == 61 and nil or b64map[cbyte]
        local d = dbyte == 61 and nil or b64map[dbyte]
        out[oi] = string.char(bit32.bor(bit32.lshift(a, 2), bit32.rshift(b, 4)))
        oi = oi + 1
        if c then
            out[oi] = string.char(bit32.band(bit32.bor(bit32.lshift(b, 4), bit32.rshift(c, 2)), 0xFF))
            oi = oi + 1
            if d then
                out[oi] = string.char(bit32.band(bit32.bor(bit32.lshift(c, 6), d), 0xFF))
                oi = oi + 1
            end
        end
        pos = pos + 4
    end
    return table.concat(out)
end

-- -------------------------------------------------------------------------
-- YouCube-compatible websocket API
-- -------------------------------------------------------------------------
local DEFAULT_SERVERS = {
    "wss://us-ky.youcube.knijn.one",
    "wss://youcube.knijn.one",
    "wss://youcube.onrender.com",
    "wss://yc.tweaked-programs.cc",
}

local API = {}
API.__index = API

function API.new()
    return setmetatable({ ws = nil, url = nil }, API)
end

local function connectWithTimeout(url, timeout)
    timeout = timeout or 4
    if http.websocketAsync then
        local ok, err = http.websocketAsync(url)
        if not ok then return nil, err end
        local timer = os.startTimer(timeout)
        while true do
            local ev, a, b = os.pullEvent()
            if ev == "websocket_success" and a == url then
                return b
            elseif ev == "websocket_failure" and a == url then
                return nil, b
            elseif ev == "timer" and a == timer then
                return nil, "timeout"
            end
        end
    end
    return http.websocket(url)
end

function API:connect(preferred)
    local list = {}
    if preferred and preferred ~= "" then list[#list + 1] = preferred end
    for _, s in ipairs(DEFAULT_SERVERS) do
        local duplicate = false
        for _, e in ipairs(list) do if e == s then duplicate = true break end end
        if not duplicate then list[#list + 1] = s end
    end

    local errors = {}
    for n, url in ipairs(list) do
        splash("Connexion au backend", ("Serveur %d/%d"):format(n, #list), url:sub(1, mw - 4))
        local ok, wsOrErr, err2 = pcall(connectWithTimeout, url, 4)
        local ws, err
        if ok then ws, err = wsOrErr, err2 else err = wsOrErr end
        if ws then
            self.ws = ws
            self.url = url
            return true
        end
        errors[#errors + 1] = url .. " -> " .. tostring(err or "echec")
    end
    return false, table.concat(errors, "\n")
end

function API:send(tbl)
    local payload = jsonEncode(tbl)
    local ok, err = pcall(self.ws.send, payload)
    if not ok then error("Connexion backend perdue: " .. tostring(err), 0) end
end

function API:receive(filter)
    while true do
        local ok, msg = pcall(self.ws.receive)
        if not ok then error("Connexion backend perdue: " .. tostring(msg), 0) end
        if msg == nil then
            error("Message WebSocket vide/trop gros. Augmente la limite WebSocket dans computercraft-server.toml.", 0)
        end
        local data, err = jsonDecode(msg)
        if not data then error("JSON backend invalide: " .. tostring(err), 0) end
        if not filter or data.action == filter then return data end
    end
end

function API:handshake()
    self:send({ action = "handshake" })
    return self:receive("handshake")
end

function API:requestMedia(q, width, height)
    local req = { action = "request_media", url = q }
    if width and height then
        req.width = width * 2
        req.height = height * 3
    end
    self:send(req)
end

function API:getAudioChunk(index, id)
    self:send({ action = "get_chunk", chunkindex = index, id = id })
    local r = self:receive("chunk")
    return base64decode(r.chunk or "")
end

function API:getVideoLines(tracker, id, width, height)
    self:send({
        action = "get_vid",
        tracker = tracker,
        id = id,
        width = width * 2,
        height = height * 3,
    })
    local r = self:receive("vid")
    return r.lines or {}
end

-- -------------------------------------------------------------------------
-- Filler/buffer objects (one websocket consumer, two playback consumers)
-- -------------------------------------------------------------------------
local function newBuffer(limit)
    return { q = {}, limit = limit or 16, eof = false }
end

local function bufferPush(buf, item)
    buf.q[#buf.q + 1] = item
end

local function bufferNext(buf, state)
    while #buf.q == 0 and not buf.eof and not state.stop do
        os.pullEvent()
    end
    if state.stop then return nil end
    if #buf.q == 0 then return nil end
    local v = buf.q[1]
    table.remove(buf.q, 1)
    return v
end

-- -------------------------------------------------------------------------
-- 32Vid raw frame decoder (YouCube's streamed video format)
-- -------------------------------------------------------------------------
local function u16le(s, p)
    local a, b = s:byte(p, p + 1)
    if not a or not b then return nil end
    return a + b * 256
end

local function decodeFrameLine(frame)
    local mode = frame:match("^!CP([CD])")
    if not mode then return nil, "frame invalide" end
    local len, start
    if mode == "C" then
        len = tonumber(frame:sub(5, 8), 16)
        start = 9
    else
        len = tonumber(frame:sub(5, 16), 16)
        start = 17
    end
    if not len then return nil, "taille frame invalide" end
    local data = base64decode(frame:sub(start, start + len - 1))
    if #data < 17 then return nil, "frame tronquee" end

    local width = u16le(data, 5)
    local height = u16le(data, 7)
    if not width or not height then return nil, "dimensions invalides" end

    local pos, runByte, runLeft = 17, nil, 0
    local function nextRLE()
        if runLeft <= 0 then
            runByte = data:byte(pos)
            runLeft = data:byte(pos + 1) or 0
            pos = pos + 2
            if not runByte or runLeft <= 0 then return nil end
        end
        runLeft = runLeft - 1
        return runByte
    end

    local chars = {}
    for y = 1, height do
        local row = {}
        for x = 1, width do
            local v = nextRLE()
            if not v then return nil, "RLE texte invalide" end
            row[x] = string.char(v)
        end
        chars[y] = table.concat(row)
    end

    local fgs, bgs = {}, {}
    local hex = "0123456789abcdef"
    for y = 1, height do
        local fg, bg = {}, {}
        for x = 1, width do
            local v = nextRLE()
            if not v then return nil, "RLE couleur invalide" end
            fg[x] = hex:sub(bit32.band(v, 0x0F) + 1, bit32.band(v, 0x0F) + 1)
            local hi = bit32.rshift(v, 4)
            bg[x] = hex:sub(hi + 1, hi + 1)
        end
        fgs[y], bgs[y] = table.concat(fg), table.concat(bg)
    end

    -- In valid frames the final RLE run ends exactly here, leaving pos at palette.
    if runLeft > 0 then
        -- Defensive skip: a malformed/extended run would overlap palette.
        runLeft = 0
    end

    local palette = {}
    for p = 0, 15 do
        local r, g, b = data:byte(pos, pos + 2)
        if not r or not g or not b then return nil, "palette tronquee" end
        palette[p] = { r / 255, g / 255, b / 255 }
        pos = pos + 3
    end

    return {
        width = width,
        height = height,
        chars = chars,
        fgs = fgs,
        bgs = bgs,
        palette = palette,
    }
end

local function drawFrame(decoded)
    local h = math.min(decoded.height, videoH)
    local w = math.min(decoded.width, mw)
    for p = 0, 15 do
        local rgb = decoded.palette[p]
        if rgb then monitor.setPaletteColor(2 ^ p, rgb[1], rgb[2], rgb[3]) end
    end
    for y = 1, h do
        monitor.setCursorPos(1, y)
        monitor.blit(
            decoded.chars[y]:sub(1, w),
            decoded.fgs[y]:sub(1, w),
            decoded.bgs[y]:sub(1, w)
        )
    end
end

-- -------------------------------------------------------------------------
-- Playback UI / controls
-- -------------------------------------------------------------------------
local state = {
    paused = false,
    stop = false,
    volume = opts.volume,
    title = "",
    fps = 0,
    frame = 0,
}

local hit = {}
local function drawControls()
    hit = {}
    if not showControlBar then return end

    local y = mh
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(1, y)
    monitor.write(string.rep(" ", mw))

    if mw < 28 then
        local x = 1
        local pauseLabel = state.paused and " > " or "II "
        mwrite(x, y, pauseLabel, colors.black, state.paused and colors.lime or colors.yellow)
        hit.pause = { x, x + #pauseLabel - 1 }
        x = x + #pauseLabel + 1

        local stopLabel = " X "
        mwrite(x, y, stopLabel, colors.white, colors.red)
        hit.stop = { x, x + #stopLabel - 1 }
        x = x + #stopLabel + 1

        local minus = " - "
        mwrite(x, y, minus, colors.white, colors.blue)
        hit.minus = { x, x + #minus - 1 }
        x = x + #minus + 1

        local plus = " + "
        mwrite(x, y, plus, colors.white, colors.blue)
        hit.plus = { x, math.min(mw, x + #plus - 1) }
        return
    end

    local pauseLabel = state.paused and " PLAY " or " PAUSE "
    local x = 1
    mwrite(x, y, pauseLabel, colors.black, state.paused and colors.lime or colors.yellow)
    hit.pause = { x, x + #pauseLabel - 1 }
    x = x + #pauseLabel + 1

    local stopLabel = " STOP "
    mwrite(x, y, stopLabel, colors.white, colors.red)
    hit.stop = { x, x + #stopLabel - 1 }
    x = x + #stopLabel + 1

    local minus = " - "
    mwrite(x, y, minus, colors.white, colors.blue)
    hit.minus = { x, x + #minus - 1 }
    x = x + #minus

    local vol = math.floor(state.volume / 3 * 100 + 0.5)
    local volText = (" VOL %3d%% "):format(vol)
    mwrite(x, y, volText, colors.white, colors.gray)
    x = x + #volText

    local plus = " + "
    mwrite(x, y, plus, colors.white, colors.blue)
    hit.plus = { x, x + #plus - 1 }
end

local function setPaused(v)
    state.paused = v
    if v and speaker then pcall(speaker.stop) end
    drawControls()
    os.queueEvent(CONTROL_EVENT)
end

local function togglePause() setPaused(not state.paused) end
local function setVolume(v)
    state.volume = math.max(0, math.min(3, v))
    if settings then settings.set("trmk.tv.volume", state.volume); pcall(settings.save) end
    drawControls()
    os.queueEvent(CONTROL_EVENT)
end

local function stopPlayback()
    state.stop = true
    if speaker then pcall(speaker.stop) end
    os.queueEvent(CONTROL_EVENT)
end

local function controlsLoop()
    drawControls()
    while not state.stop do
        local ev, a, b, c = os.pullEvent()
        if ev == "key" then
            if a == keys.space then togglePause()
            elseif a == keys.q or a == keys.escape then stopPlayback()
            elseif a == keys.minus then setVolume(state.volume - 0.15)
            elseif a == keys.equals or a == keys.plus then setVolume(state.volume + 0.15)
            end
        elseif ev == "monitor_touch" then
            local x, y = b, c
            if showControlBar and y == mh then
                local function inside(r) return r and x >= r[1] and x <= r[2] end
                if inside(hit.pause) then togglePause()
                elseif inside(hit.stop) then stopPlayback()
                elseif inside(hit.minus) then setVolume(state.volume - 0.15)
                elseif inside(hit.plus) then setVolume(state.volume + 0.15)
                end
            elseif not showControlBar then
                -- En mode petit ecran, aucune ligne n'est sacrifiee pour l'UI.
                -- Un toucher n'importe ou met simplement pause/reprend.
                togglePause()
            end
        elseif ev == "terminate" then
            stopPlayback()
            return
        end
    end
end

local function waitIfPaused()
    while state.paused and not state.stop do
        os.pullEvent()
    end
    return not state.stop
end

local function waitFrameDelay(seconds)
    local remaining = seconds
    while remaining > 0 and not state.stop do
        if state.paused then
            if not waitIfPaused() then return false end
        end
        local start = os.epoch("utc")
        local timer = os.startTimer(remaining)
        while true do
            local ev, id = os.pullEvent()
            if state.stop then return false end
            if state.paused then
                local elapsed = (os.epoch("utc") - start) / 1000
                remaining = math.max(0, remaining - elapsed)
                break
            elseif ev == "timer" and id == timer then
                return true
            end
        end
    end
    return not state.stop
end

-- -------------------------------------------------------------------------
-- Main
-- -------------------------------------------------------------------------
local function getInput()
    if input and input ~= "" then return input end
    splash("Pret", "Colle l'URL sur le PC", "Monitor detecte")
    term.setTextColor(colors.cyan)
    print(("TRMK TV v%s"):format(VERSION))
    term.setTextColor(colors.white)
    print(("Monitor: %dx%d | video: %dx%d | UI: %s"):format(
        mw, mh, mw, videoH, showControlBar and "barre tactile" or "plein ecran"
    ))
    print("Colle une URL YouTube ou un terme de recherche :")
    term.write("> ")
    return read()
end

local api = API.new()
local decoder
if haveAudio then
    local ok, dfpwm = pcall(require, "cc.audio.dfpwm")
    if ok and dfpwm and dfpwm.make_decoder then decoder = dfpwm.make_decoder() end
    if not decoder then haveAudio = false end
end

local function main()
    input = getInput()
    if not input or input == "" then return end

    local ok, err = api:connect(opts.server)
    if not ok then
        splash("Aucun backend disponible", "YouCube public semble indisponible", "Configure --server <wss://...>")
        term.setTextColor(colors.red)
        print("Impossible de joindre un serveur YouCube compatible:")
        print(err)
        term.setTextColor(colors.white)
        print("Tu peux utiliser: TRMK_TV.lua --server wss://TON_SERVEUR <URL>")
        return
    end

    splash("Backend connecte", api.url, "Handshake...")
    local hsOk, hs = pcall(function() return api:handshake() end)
    if not hsOk then
        term.setTextColor(colors.orange)
        print("Handshake non disponible, tentative quand meme: " .. tostring(hs))
        term.setTextColor(colors.white)
    end

    splash("Preparation", input:sub(1, mw - 4), "Demande de la video...")
    api:requestMedia(input, mw, videoH)

    local media
    while not media do
        local data = api:receive()
        if data.action == "status" then
            splash("Preparation", (data.message or "Traitement..."):sub(1, mw - 4), api.url)
        elseif data.action == "error" then
            error(data.message or "Erreur backend", 0)
        elseif data.action == "media" then
            media = data
        end
    end

    state.title = tostring(media.title or "Video")
    clearMonitor(colors.black)
    local titleY = math.max(1, math.floor(videoH / 2))
    local bufferY = math.min(videoH, titleY + 2)
    mcenter(titleY, state.title:sub(1, math.max(1, mw - 2)), colors.white)
    if bufferY ~= titleY then mcenter(bufferY, "Buffering...", colors.yellow) end
    drawControls()

    local audioBuf = newBuffer(32)
    local videoBuf = newBuffer(60)
    local audioIndex = 0
    local videoTracker = 0

    local function fillBuffers()
        while not state.stop do
            os.queueEvent("trmk_tv_fill")
            os.pullEvent()

            if haveAudio and not audioBuf.eof and #audioBuf.q < audioBuf.limit then
                local chunk = api:getAudioChunk(audioIndex, media.id)
                audioIndex = audioIndex + 1
                if chunk == "" then audioBuf.eof = true else bufferPush(audioBuf, chunk) end
            end

            if not videoBuf.eof and #videoBuf.q < videoBuf.limit then
                local lines = api:getVideoLines(videoTracker, media.id, mw, videoH)
                if #lines == 0 then
                    videoBuf.eof = true
                else
                    for _, line in ipairs(lines) do
                        videoTracker = videoTracker + #line + 1
                        bufferPush(videoBuf, line)
                        if line == "" then videoBuf.eof = true break end
                    end
                end
            end

        end
    end

    local function playVideo()
        local header = bufferNext(videoBuf, state)
        if not header then return end
        if header ~= "32Vid 1.1" then error("Format video non supporte: " .. tostring(header), 0) end

        local fpsLine = bufferNext(videoBuf, state)
        local fps = tonumber(fpsLine) or 15
        if fps <= 0 then fps = 15 end
        state.fps = fps

        -- The raw stream historically includes two initial frame slots; consume naturally.
        local frameDuration = 1 / fps
        while not state.stop do
            if not waitIfPaused() then return end
            local line = bufferNext(videoBuf, state)
            if not line or line == "" then return end
            local decoded, derr = decodeFrameLine(line)
            if decoded then
                drawFrame(decoded)
                state.frame = state.frame + 1
                drawControls()
            else
                error("Decode video: " .. tostring(derr), 0)
            end
            if not waitFrameDelay(frameDuration) then return end
        end
    end

    local function playAudio()
        if not haveAudio then return end
        while not state.stop do
            if not waitIfPaused() then return end
            local chunk = bufferNext(audioBuf, state)
            if not chunk then return end
            local pcm = decoder(chunk)
            local accepted = speaker.playAudio(pcm, state.volume)
            while not accepted and not state.stop do
                os.pullEvent("speaker_audio_empty")
                if state.paused then break end
                accepted = speaker.playAudio(pcm, state.volume)
            end
        end
    end

    local function mediaLoop()
        if haveAudio then
            parallel.waitForAll(playVideo, playAudio)
        else
            playVideo()
        end
    end

    local runOk, runErr = pcall(function()
        parallel.waitForAny(fillBuffers, mediaLoop, controlsLoop)
    end)

    state.stop = true
    if speaker then pcall(speaker.stop) end
    restoreMonitor()
    if not runOk then error(runErr, 0) end

    splash("Lecture terminee", state.title:sub(1, mw - 4), "Q pour quitter / relance pour une autre video")
    sleep(1.5)
end

local ok, err = xpcall(main, function(e)
    return tostring(e) .. "\n" .. debug.traceback("", 2)
end)

if speaker then pcall(speaker.stop) end
restoreMonitor()
if api.ws then pcall(api.ws.close) end

if not ok then
    term.setTextColor(colors.red)
    print("TRMK TV a plante:")
    print(err)
    term.setTextColor(colors.white)
    print("Si l'erreur parle de WebSocket/message size, augmente la limite dans computercraft-server.toml.")
end
