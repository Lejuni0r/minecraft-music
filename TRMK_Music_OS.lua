-- ============================================================
-- TRMK Music OS
-- Universal CC:Tweaked music player / jukebox
-- - Pocket Computer + Speaker Upgrade
-- - Advanced Computer + one or many wired Speakers
-- - Streams DFPWM tracks from GitHub
-- ============================================================

local PLAYLIST_URL = "https://raw.githubusercontent.com/Lejuni0r/minecraft-music/main/playlist.json"
local PLAYLIST_CACHE = ".trmk_music_playlist.json"
local SETTINGS_FILE = ".trmk_music_settings.json"

local BYTES_PER_SECOND = 6000 -- DFPWM @ 48 kHz, 1 bit/sample
local CHUNK_SIZE = 8 * 1024
local UI_REFRESH = 0.20

local dfpwm = require("cc.audio.dfpwm")

local state = {
    running = true,

    playlist = {},
    filtered = {},
    query = "",
    searchMode = false,
    selected = 1,
    scroll = 0,

    speakers = {},
    speakerNames = {},

    current = nil,
    playRequested = false,
    paused = false,
    playing = false,
    loading = false,
    buffering = false,

    volume = 1.0,
    shuffle = false,
    repeatMode = 1, -- 0=OFF, 1=ALL, 2=TRACK

    autoplay = false,
    lastTrackFile = nil,

    token = 0,
    bytesRead = 0,
    totalBytes = nil,

    status = "BOOT",
    error = nil,
    playlistSource = "?",
}

local hitboxes = {}
local spinnerFrames = { "o", "O", "o", "." }
local spinnerIndex = 1

math.randomseed(os.epoch("utc") % 2147483647)

-- ============================================================
-- Helpers
-- ============================================================

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function wake()
    os.queueEvent("trmk_music_wake")
end

local function cleanText(s)
    s = tostring(s or "")

    local replacements = {
        {"À","A"},{"Á","A"},{"Â","A"},{"Ã","A"},{"Ä","A"},{"Å","A"},
        {"à","a"},{"á","a"},{"â","a"},{"ã","a"},{"ä","a"},{"å","a"},
        {"Ç","C"},{"ç","c"},
        {"È","E"},{"É","E"},{"Ê","E"},{"Ë","E"},
        {"è","e"},{"é","e"},{"ê","e"},{"ë","e"},
        {"Ì","I"},{"Í","I"},{"Î","I"},{"Ï","I"},
        {"ì","i"},{"í","i"},{"î","i"},{"ï","i"},
        {"Ñ","N"},{"ñ","n"},
        {"Ò","O"},{"Ó","O"},{"Ô","O"},{"Õ","O"},{"Ö","O"},
        {"ò","o"},{"ó","o"},{"ô","o"},{"õ","o"},{"ö","o"},
        {"Ù","U"},{"Ú","U"},{"Û","U"},{"Ü","U"},
        {"ù","u"},{"ú","u"},{"û","u"},{"ü","u"},
        {"Ý","Y"},{"Ÿ","Y"},{"ý","y"},{"ÿ","y"},
        {"Œ","OE"},{"œ","oe"},{"Æ","AE"},{"æ","ae"},
        {"’","'"},{"‘","'"},{"“",'"'},{"”",'"'},
        {"–","-"},{"—","-"},{"…","..."},
    }

    for _, pair in ipairs(replacements) do
        s = s:gsub(pair[1], pair[2])
    end

    -- ComputerCraft's terminal is not a general Unicode renderer.
    s = s:gsub("[\128-\255]", "")
    s = s:gsub("[%c]", " ")
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")

    if s == "" then s = "Untitled" end
    return s
end

local function fit(s, width)
    s = cleanText(s)
    if width <= 0 then return "" end

    if #s > width then
        if width <= 3 then return s:sub(1, width) end
        return s:sub(1, width - 3) .. "..."
    end

    return s .. string.rep(" ", width - #s)
end

local function center(s, width)
    s = cleanText(s)
    if #s > width then s = fit(s, width) end

    local left = math.floor((width - #s) / 2)
    return string.rep(" ", math.max(0, left)) .. s
end

local function formatTime(seconds)
    if not seconds or seconds < 0 then return "--:--" end

    seconds = math.floor(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60

    return string.format("%02d:%02d", m, s)
end

local function getHeader(headers, wanted)
    wanted = wanted:lower()

    for k, v in pairs(headers or {}) do
        if tostring(k):lower() == wanted then
            return v
        end
    end

    return nil
end

local function readFile(path)
    if not fs.exists(path) then return nil end

    local f = fs.open(path, "r")
    if not f then return nil end

    local data = f.readAll()
    f.close()

    return data
end

local function writeFile(path, data)
    local f = fs.open(path, "w")
    if not f then return false end

    f.write(data)
    f.close()

    return true
end

local function songTitle(song)
    if not song then return "No track" end
    return cleanText(song.title or song.file or "Untitled")
end

-- ============================================================
-- Speaker management
-- ============================================================

local function rescanSpeakers()
    local found = {}
    local names = {}

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "speaker") then
            local wrapped = peripheral.wrap(name)
            if wrapped then
                table.insert(found, wrapped)
                table.insert(names, name)
            end
        end
    end

    state.speakers = found
    state.speakerNames = names

    if #found == 0 then
        state.status = "NO SPEAKER"
        state.error = "Aucun Speaker detecte"
    elseif state.error == "Aucun Speaker detecte" then
        state.error = nil
    end

    return #found
end

local function stopAllSpeakers()
    for _, speaker in ipairs(state.speakers) do
        pcall(function()
            speaker.stop()
        end)
    end
end

local function playChunkOnAll(audio)
    if #state.speakers == 0 then
        rescanSpeakers()
        if #state.speakers == 0 then
            return false, "Aucun Speaker detecte"
        end
    end

    local done = {}
    local remaining = #state.speakers

    while remaining > 0 and state.running do
        for i, speaker in ipairs(state.speakers) do
            if not done[i] then
                local ok, accepted = pcall(function()
                    return speaker.playAudio(audio, state.volume)
                end)

                if not ok then
                    -- Peripheral may have disappeared.
                    return false, "Speaker deconnecte"
                end

                if accepted then
                    done[i] = true
                    remaining = remaining - 1
                end
            end
        end

        if remaining > 0 then
            state.buffering = true

            local ev = os.pullEvent()
            if ev == "peripheral" or ev == "peripheral_detach" then
                rescanSpeakers()
                return false, "Speakers modifies"
            end
        end
    end

    state.buffering = false
    return remaining == 0
end

-- ============================================================
-- Settings
-- ============================================================

local function saveSettings()
    local data = {
        volume = state.volume,
        shuffle = state.shuffle,
        repeatMode = state.repeatMode,
        autoplay = state.autoplay,
        lastTrackFile = state.lastTrackFile,
    }

    writeFile(SETTINGS_FILE, textutils.serializeJSON(data))
end

local function loadSettings()
    local raw = readFile(SETTINGS_FILE)
    if not raw then return end

    local ok, data = pcall(textutils.unserializeJSON, raw)
    if not ok or type(data) ~= "table" then return end

    state.volume = clamp(tonumber(data.volume) or 1.0, 0, 3)
    state.shuffle = data.shuffle == true
    state.repeatMode = clamp(math.floor(tonumber(data.repeatMode) or 1), 0, 2)
    state.autoplay = data.autoplay == true
    state.lastTrackFile = type(data.lastTrackFile) == "string" and data.lastTrackFile or nil
end

-- ============================================================
-- Playlist
-- ============================================================

local function normalizePlaylist(list)
    local out = {}

    if type(list) ~= "table" then return out end

    for _, song in ipairs(list) do
        if type(song) == "table" then
            local file = tostring(song.file or "")
            local url = tostring(song.url or "")

            if url == "" and file ~= "" then
                url =
                    "https://raw.githubusercontent.com/Lejuni0r/minecraft-music/main/songs/"
                    .. file
            end

            if url ~= "" then
                table.insert(out, {
                    title = tostring(song.title or file or "Untitled"),
                    file = file,
                    url = url,
                    bytes = tonumber(song.bytes),
                    duration = tonumber(song.duration),
                })
            end
        end
    end

    return out
end

local function parsePlaylist(raw)
    if not raw or raw == "" then
        return nil, "Playlist vide"
    end

    local ok, parsed = pcall(textutils.unserializeJSON, raw)

    if not ok or type(parsed) ~= "table" then
        return nil, "JSON invalide"
    end

    local list = normalizePlaylist(parsed)

    if #list == 0 then
        return nil, "Aucun morceau valide"
    end

    return list
end

local function rebuildFilter(reset)
    state.filtered = {}

    local q = state.query:lower()

    for i, song in ipairs(state.playlist) do
        local title = songTitle(song):lower()

        if q == "" or title:find(q, 1, true) then
            table.insert(state.filtered, i)
        end
    end

    if reset then
        state.selected = 1
        state.scroll = 0
    else
        state.selected =
            clamp(
                state.selected,
                1,
                math.max(1, #state.filtered)
            )
    end
end

local function findTrackByFile(file)
    if not file then return nil end

    for i, song in ipairs(state.playlist) do
        if song.file == file then
            return i
        end
    end

    return nil
end

local function fetchPlaylist()
    local oldFile = nil

    if state.current and state.playlist[state.current] then
        oldFile = state.playlist[state.current].file
    end

    state.loading = true
    state.status = "PLAYLIST"
    state.error = nil

    local response, err = http.get({
        url = PLAYLIST_URL,
        headers = { ["Cache-Control"] = "no-cache" },
        timeout = 15,
    })

    local raw = nil
    local source = "CACHE"

    if response then
        raw = response.readAll()
        response.close()
        source = "GITHUB"
    else
        raw = readFile(PLAYLIST_CACHE)
    end

    local list, parseErr = parsePlaylist(raw)

    if not list then
        state.loading = false
        state.error = err or parseErr or "Playlist indisponible"
        state.status = "ERROR"
        return false
    end

    state.playlist = list
    state.playlistSource = source

    if source == "GITHUB" and raw then
        writeFile(PLAYLIST_CACHE, raw)
    end

    if oldFile then
        state.current = findTrackByFile(oldFile)
    elseif state.lastTrackFile then
        state.current = findTrackByFile(state.lastTrackFile)
    end

    rebuildFilter(false)

    state.loading = false
    state.status = source

    return true
end

-- ============================================================
-- Playback
-- ============================================================

local function setTrack(index)
    if not index or not state.playlist[index] then return end

    state.token = state.token + 1
    state.current = index
    state.playRequested = true
    state.paused = false
    state.playing = false
    state.loading = true
    state.buffering = false
    state.bytesRead = 0
    state.totalBytes = state.playlist[index].bytes
    state.status = "CONNECT"
    state.error = nil

    state.lastTrackFile = state.playlist[index].file
    saveSettings()

    stopAllSpeakers()
    wake()
end

local function stopPlayback()
    state.token = state.token + 1
    state.playRequested = false
    state.paused = false
    state.playing = false
    state.loading = false
    state.buffering = false
    state.bytesRead = 0
    state.totalBytes = nil
    state.status = "STOP"

    stopAllSpeakers()
    wake()
end

local function randomTrack()
    if #state.playlist <= 1 then
        return state.current or 1
    end

    local n

    repeat
        n = math.random(1, #state.playlist)
    until n ~= state.current

    return n
end

local function nextTrack(manual)
    if #state.playlist == 0 then return end

    if state.shuffle then
        setTrack(randomTrack())
        return
    end

    local current = state.current or 0
    local nextIndex = current + 1

    if nextIndex > #state.playlist then
        if manual or state.repeatMode == 1 then
            nextIndex = 1
        else
            stopPlayback()
            return
        end
    end

    setTrack(nextIndex)
end

local function previousTrack()
    if #state.playlist == 0 then return end

    if state.shuffle then
        setTrack(randomTrack())
        return
    end

    local current = state.current or 1
    local prevIndex = current - 1

    if prevIndex < 1 then
        prevIndex = #state.playlist
    end

    setTrack(prevIndex)
end

local function togglePause()
    if not state.current then
        if #state.filtered > 0 then
            setTrack(state.filtered[state.selected] or state.filtered[1])
        end
        return
    end

    if not state.playRequested then
        setTrack(state.current)
        return
    end

    state.paused = not state.paused

    if state.paused then
        state.status = "PAUSED"
        state.buffering = false
        stopAllSpeakers()
    else
        state.status = "PLAY"
    end

    wake()
end

local function setVolume(v)
    state.volume =
        clamp(
            math.floor(v * 4 + 0.5) / 4,
            0,
            3
        )

    saveSettings()
end

local function streamTrack(token)
    local song = state.playlist[state.current]

    if not song then
        return "cancelled"
    end

    if rescanSpeakers() == 0 then
        state.loading = false
        state.playing = false
        state.playRequested = false
        state.status = "NO SPEAKER"
        return "error"
    end

    state.loading = true
    state.status = "CONNECT"
    state.error = nil

    local response, err = http.get({
        url = song.url,
        binary = true,
        timeout = 20,
        headers = { ["Cache-Control"] = "no-cache" },
    })

    if token ~= state.token or not state.running then
        if response then response.close() end
        return "cancelled"
    end

    if not response then
        state.loading = false
        state.playing = false
        state.playRequested = false
        state.status = "HTTP ERROR"
        state.error = tostring(err or "Connexion impossible")
        return "error"
    end

    local headers = response.getResponseHeaders()
    local length = tonumber(getHeader(headers, "content-length"))

    state.totalBytes = song.bytes or length or state.totalBytes
    state.bytesRead = 0

    local decoder = dfpwm.make_decoder()

    state.loading = false
    state.playing = true
    state.status = "PLAY"

    while state.running
        and token == state.token
        and state.playRequested do

        if state.paused then
            os.pullEvent("trmk_music_wake")
        else
            local chunk = response.read(CHUNK_SIZE)

            if not chunk or #chunk == 0 then
                response.close()
                state.playing = false
                state.buffering = false
                return "ended"
            end

            local audio = decoder(chunk)

            local ok, reason = playChunkOnAll(audio)

            if not ok then
                response.close()

                if token ~= state.token or not state.running then
                    return "cancelled"
                end

                state.error = reason
                state.playing = false
                state.loading = false
                state.status = "SPEAKER ERR"

                return "error"
            end

            state.bytesRead = state.bytesRead + #chunk
        end
    end

    response.close()

    return "cancelled"
end

local function handleNaturalEnd()
    if not state.current then
        stopPlayback()
        return
    end

    if state.repeatMode == 2 then
        -- LOOP TRACK
        setTrack(state.current)

    elseif state.shuffle then
        setTrack(randomTrack())

    else
        nextTrack(false)
    end
end

local function audioWorker()
    while state.running do
        if state.playRequested and state.current then
            local token = state.token
            local reason = streamTrack(token)

            if reason == "ended"
                and state.running
                and token == state.token
                and state.playRequested then

                handleNaturalEnd()
            end
        else
            os.pullEvent("trmk_music_wake")
        end
    end
end

-- ============================================================
-- UI primitives
-- ============================================================

local function addHitbox(x1, y1, x2, y2, action, value)
    table.insert(hitboxes, {
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        action = action,
        value = value,
    })
end

local function clearLine(y, bg)
    local w = term.getSize()

    term.setCursorPos(1, y)
    term.setBackgroundColor(bg or colors.black)
    term.write(string.rep(" ", w))
end

local function writeAt(x, y, text, fg, bg)
    local w, h = term.getSize()

    if y < 1 or y > h or x > w then return end

    text = tostring(text or "")

    if x < 1 then
        text = text:sub(2 - x)
        x = 1
    end

    if #text > w - x + 1 then
        text = text:sub(1, w - x + 1)
    end

    term.setCursorPos(x, y)
    term.setTextColor(fg or colors.white)
    term.setBackgroundColor(bg or colors.black)
    term.write(text)
end

local function fillButton(
    x1,
    x2,
    y,
    label,
    active,
    action,
    value,
    activeColor
)
    if x2 < x1 then return end

    local fg = active and colors.black or colors.white
    local bg = active and (activeColor or colors.cyan) or colors.gray

    local width = x2 - x1 + 1
    local text = center(label, width)

    if #text < width then
        text = text .. string.rep(" ", width - #text)
    end

    writeAt(
        x1,
        y,
        text:sub(1, width),
        fg,
        bg
    )

    addHitbox(
        x1,
        y,
        x2,
        y,
        action,
        value
    )
end

local function currentProgress()
    local elapsed =
        state.bytesRead / BYTES_PER_SECOND

    local total = nil

    if state.totalBytes and state.totalBytes > 0 then
        total =
            state.totalBytes / BYTES_PER_SECOND

    elseif state.current
        and state.playlist[state.current]
        and state.playlist[state.current].duration then

        total =
            state.playlist[state.current].duration
    end

    return elapsed, total
end

local function drawProgress(y)
    local w = term.getSize()

    local x1, x2 = 2, w - 1
    local width = math.max(1, x2 - x1 + 1)

    local ratio = 0

    if state.totalBytes and state.totalBytes > 0 then
        ratio =
            clamp(
                state.bytesRead / state.totalBytes,
                0,
                1
            )
    end

    local filled =
        math.floor(width * ratio + 0.5)

    term.setCursorPos(x1, y)

    term.setBackgroundColor(colors.cyan)
    term.write(string.rep(" ", filled))

    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", width - filled))

    term.setBackgroundColor(colors.black)
end

local function ensureSelectionVisible(rows)
    if #state.filtered == 0 then
        state.selected = 1
        state.scroll = 0
        return
    end

    state.selected =
        clamp(
            state.selected,
            1,
            #state.filtered
        )

    if state.selected <= state.scroll then
        state.scroll = state.selected - 1

    elseif state.selected > state.scroll + rows then
        state.scroll =
            state.selected - rows
    end

    state.scroll =
        clamp(
            state.scroll,
            0,
            math.max(0, #state.filtered - rows)
        )
end

local function repeatLabel()
    if state.repeatMode == 0 then
        return "REP OFF"
    elseif state.repeatMode == 2 then
        return "LOOP TRACK"
    end

    return "REP ALL"
end

-- ============================================================
-- Main UI
-- ============================================================

local function drawUI()
    local w, h = term.getSize()

    hitboxes = {}

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    -- Header
    clearLine(1, colors.blue)
    writeAt(
        2,
        1,
        "TRMK MUSIC OS",
        colors.white,
        colors.blue
    )

    local rightStatus

    if state.loading then
        rightStatus =
            "SYNC " .. spinnerFrames[spinnerIndex]

    elseif state.buffering then
        rightStatus = "BUFFER"

    elseif state.paused then
        rightStatus = "PAUSE"

    elseif state.playing then
        rightStatus = "PLAY"

    elseif state.error then
        rightStatus = "ERROR"

    else
        rightStatus = state.status
    end

    rightStatus = cleanText(rightStatus)

    writeAt(
        math.max(1, w - #rightStatus),
        1,
        rightStatus,
        colors.white,
        colors.blue
    )

    -- Speaker info
    clearLine(2, colors.black)

    local speakerText =
        string.format(
            "Speakers %d  Vol %.2f",
            #state.speakers,
            state.volume
        )

    writeAt(
        1,
        2,
        fit(speakerText, w),
        #state.speakers > 0
            and colors.lightGray
            or colors.red,
        colors.black
    )

    -- Current title
    local song =
        state.current
        and state.playlist[state.current]
        or nil

    local title =
        songTitle(song)

    writeAt(
        1,
        3,
        fit(title, w),
        state.error
            and colors.red
            or colors.white,
        colors.black
    )

    local elapsed, duration =
        currentProgress()

    local timeText =
        formatTime(elapsed)
        .. " / "
        .. formatTime(duration)

    writeAt(
        1,
        4,
        center(timeText, w),
        colors.lightGray,
        colors.black
    )

    drawProgress(5)

    -- Controls
    local third =
        math.floor(w / 3)

    fillButton(
        1,
        third,
        7,
        "<< PREV",
        false,
        "prev"
    )

    fillButton(
        third + 1,
        w - third,
        7,
        state.paused
            and "PLAY >"
            or "PAUSE",
        state.playRequested,
        "pause"
    )

    fillButton(
        w - third + 1,
        w,
        7,
        "NEXT >>",
        false,
        "next"
    )

    -- Stop / volume
    local quarter =
        math.max(3, math.floor(w / 4))

    fillButton(
        1,
        quarter,
        8,
        "STOP",
        false,
        "stop"
    )

    fillButton(
        quarter + 1,
        quarter * 2,
        8,
        "VOL -",
        false,
        "volDown"
    )

    fillButton(
        quarter * 2 + 1,
        quarter * 3,
        8,
        "VOL +",
        false,
        "volUp"
    )

    fillButton(
        quarter * 3 + 1,
        w,
        8,
        "RESCAN",
        false,
        "rescan"
    )

    -- Shuffle / repeat / autoplay
    local third2 =
        math.floor(w / 3)

    fillButton(
        1,
        third2,
        9,
        state.shuffle
            and "SHUF ON"
            or "SHUF OFF",
        state.shuffle,
        "shuffle"
    )

    fillButton(
        third2 + 1,
        w - third2,
        9,
        repeatLabel(),
        state.repeatMode ~= 0,
        "repeat"
    )

    fillButton(
        w - third2 + 1,
        w,
        9,
        state.autoplay
            and "AUTO ON"
            or "AUTO OFF",
        state.autoplay,
        "autoplay",
        nil,
        colors.lime
    )

    -- Search
    local searchLabel

    if state.searchMode then
        searchLabel =
            "SEARCH> "
            .. state.query
            .. "_"

    elseif state.query ~= "" then
        searchLabel =
            "SEARCH: "
            .. state.query

    else
        searchLabel = "SEARCH /"
    end

    clearLine(
        11,
        state.searchMode
            and colors.blue
            or colors.black
    )

    writeAt(
        1,
        11,
        fit(searchLabel, w),
        state.searchMode
            and colors.white
            or colors.cyan,
        state.searchMode
            and colors.blue
            or colors.black
    )

    addHitbox(
        1,
        11,
        w,
        11,
        "search"
    )

    -- Library
    local listStart = 12
    local listEnd =
        math.max(
            listStart,
            h - 2
        )

    local rows =
        listEnd - listStart + 1

    ensureSelectionVisible(rows)

    for row = 1, rows do
        local filteredPos =
            state.scroll + row

        local absIndex =
            state.filtered[filteredPos]

        local y =
            listStart + row - 1

        if absIndex then
            local item =
                state.playlist[absIndex]

            local isSelected =
                filteredPos == state.selected

            local isCurrent =
                absIndex == state.current

            local marker =
                isCurrent
                and ">"
                or " "

            local number =
                string.format(
                    "%03d",
                    absIndex
                )

            local label =
                marker
                .. number
                .. " "
                .. songTitle(item)

            local bg =
                isSelected
                and colors.gray
                or colors.black

            local fg

            if isCurrent then
                fg = colors.lime

            elseif isSelected then
                fg = colors.white

            else
                fg = colors.lightGray
            end

            clearLine(y, bg)

            writeAt(
                1,
                y,
                fit(label, w),
                fg,
                bg
            )

            addHitbox(
                1,
                y,
                w,
                y,
                "track",
                filteredPos
            )

        else
            clearLine(
                y,
                colors.black
            )
        end
    end

    -- Footer
    local countText =
        string.format(
            "%d/%d tracks | %s",
            #state.filtered,
            #state.playlist,
            state.playlistSource
        )

    clearLine(
        h - 1,
        colors.black
    )

    writeAt(
        1,
        h - 1,
        fit(countText, w),
        colors.lightGray,
        colors.black
    )

    if state.error then
        clearLine(h, colors.red)

        writeAt(
            1,
            h,
            fit(state.error, w),
            colors.white,
            colors.red
        )
    else
        clearLine(h, colors.black)

        local hint =
            "SPACE Play  / Search  R Sync"

        writeAt(
            1,
            h,
            fit(hint, w),
            colors.gray,
            colors.black
        )
    end

    term.setCursorBlink(
        state.searchMode
    )

    if state.searchMode then
        local cursorX =
            math.min(
                w,
                9 + #state.query
            )

        term.setCursorPos(
            cursorX,
            11
        )
    end
end

-- ============================================================
-- Actions
-- ============================================================

local function action(name, value)
    if name == "prev" then
        previousTrack()

    elseif name == "pause" then
        togglePause()

    elseif name == "next" then
        nextTrack(true)

    elseif name == "stop" then
        stopPlayback()

    elseif name == "volDown" then
        setVolume(
            state.volume - 0.25
        )

    elseif name == "volUp" then
        setVolume(
            state.volume + 0.25
        )

    elseif name == "rescan" then
        rescanSpeakers()

    elseif name == "shuffle" then
        state.shuffle =
            not state.shuffle

        saveSettings()

    elseif name == "repeat" then
        state.repeatMode =
            (state.repeatMode + 1) % 3

        saveSettings()

    elseif name == "autoplay" then
        state.autoplay =
            not state.autoplay

        saveSettings()

    elseif name == "search" then
        state.searchMode = true

    elseif name == "track" then
        local pos =
            tonumber(value)

        if pos
            and state.filtered[pos] then

            state.selected = pos

            setTrack(
                state.filtered[pos]
            )
        end
    end
end

local function handleClick(x, y)
    for i = #hitboxes, 1, -1 do
        local b = hitboxes[i]

        if x >= b.x1
            and x <= b.x2
            and y >= b.y1
            and y <= b.y2 then

            action(
                b.action,
                b.value
            )

            return
        end
    end
end

local function handleNormalKey(key)
    if key == keys.space then
        togglePause()

    elseif key == keys.left then
        previousTrack()

    elseif key == keys.right then
        nextTrack(true)

    elseif key == keys.up then
        state.selected =
            state.selected - 1

    elseif key == keys.down then
        state.selected =
            state.selected + 1

    elseif key == keys.enter then
        local absIndex =
            state.filtered[state.selected]

        if absIndex then
            setTrack(absIndex)
        end

    elseif key == keys.pageUp then
        state.selected =
            state.selected - 5

    elseif key == keys.pageDown then
        state.selected =
            state.selected + 5

    elseif key == keys.home then
        state.selected = 1

    elseif key == keys["end"] then
        state.selected =
            math.max(
                1,
                #state.filtered
            )

    elseif key == keys.backspace
        and state.query ~= "" then

        state.query = ""
        rebuildFilter(true)
    end
end

local function handleSearchKey(key)
    if key == keys.enter
        or key == keys.escape then

        state.searchMode = false

    elseif key == keys.backspace then

        if #state.query > 0 then
            state.query =
                state.query:sub(
                    1,
                    #state.query - 1
                )

            rebuildFilter(true)
        end

    elseif key == keys.delete then

        state.query = ""
        rebuildFilter(true)
    end
end

-- ============================================================
-- Workers
-- ============================================================

local function uiWorker()
    local timer =
        os.startTimer(UI_REFRESH)

    drawUI()

    while state.running do
        local ev, a, b, c =
            os.pullEvent()

        if ev == "timer"
            and a == timer then

            spinnerIndex =
                (spinnerIndex % #spinnerFrames) + 1

            drawUI()

            timer =
                os.startTimer(UI_REFRESH)

        elseif ev == "mouse_click" then

            handleClick(b, c)
            drawUI()

        elseif ev == "mouse_scroll" then

            local w, h =
                term.getSize()

            local rows =
                math.max(
                    1,
                    (h - 2) - 12 + 1
                )

            state.scroll =
                clamp(
                    state.scroll + a,
                    0,
                    math.max(
                        0,
                        #state.filtered - rows
                    )
                )

            state.selected =
                clamp(
                    state.selected + a,
                    1,
                    math.max(
                        1,
                        #state.filtered
                    )
                )

            drawUI()

        elseif ev == "char" then

            if state.searchMode then

                state.query =
                    state.query .. a

                rebuildFilter(true)

            else
                local ch =
                    a:lower()

                if ch == "/"
                    or ch == "s" then

                    state.searchMode = true

                elseif ch == "r" then
                    fetchPlaylist()

                elseif ch == "x" then
                    state.query = ""
                    rebuildFilter(true)

                elseif ch == "+"
                    or ch == "=" then

                    setVolume(
                        state.volume + 0.25
                    )

                elseif ch == "-" then

                    setVolume(
                        state.volume - 0.25
                    )

                elseif ch == "h" then

                    state.shuffle =
                        not state.shuffle

                    saveSettings()

                elseif ch == "t" then

                    state.repeatMode =
                        (state.repeatMode + 1) % 3

                    saveSettings()

                elseif ch == "a" then

                    state.autoplay =
                        not state.autoplay

                    saveSettings()

                elseif ch == "k" then
                    stopPlayback()

                elseif ch == "p" then
                    rescanSpeakers()

                elseif ch == "q" then

                    state.running = false
                    stopPlayback()
                    wake()
                end
            end

            drawUI()

        elseif ev == "key" then

            if state.searchMode then
                handleSearchKey(a)
            else
                handleNormalKey(a)
            end

            drawUI()

        elseif ev == "term_resize" then
            drawUI()

        elseif ev == "peripheral"
            or ev == "peripheral_detach" then

            rescanSpeakers()
            drawUI()
        end
    end
end

-- ============================================================
-- Startup
-- ============================================================

local function splash(message)
    local w, h =
        term.getSize()

    term.setBackgroundColor(
        colors.black
    )

    term.setTextColor(
        colors.white
    )

    term.clear()

    writeAt(
        1,
        math.max(
            1,
            math.floor(h / 2) - 1
        ),
        center(
            "TRMK MUSIC OS",
            w
        ),
        colors.cyan,
        colors.black
    )

    writeAt(
        1,
        math.max(
            1,
            math.floor(h / 2) + 1
        ),
        center(
            message or "Loading...",
            w
        ),
        colors.lightGray,
        colors.black
    )
end

local function tryAutoplay()
    if not state.autoplay then
        return
    end

    local index =
        findTrackByFile(
            state.lastTrackFile
        )

    if index then
        setTrack(index)
    elseif #state.playlist > 0 then
        setTrack(1)
    end
end

local function main()
    loadSettings()

    splash(
        "Scanning speakers..."
    )

    rescanSpeakers()

    splash(
        "Loading playlist..."
    )

    if not fetchPlaylist() then
        splash(
            "Playlist unavailable"
        )

        sleep(1)
    end

    rebuildFilter(true)

    tryAutoplay()

    parallel.waitForAll(
        audioWorker,
        uiWorker
    )

    stopAllSpeakers()

    term.setCursorBlink(false)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local ok, err =
    pcall(main)

stopAllSpeakers()

term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

if not ok then
    printError(err)
end
