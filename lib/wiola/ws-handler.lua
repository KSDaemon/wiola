--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--


local wsServer = require "resty.websocket.server"
local wiola = require "wiola"
local config = require("wiola.config").config()
local restyLock = require "resty.lock"
local semaphore = require "ngx.semaphore"
local lockM = restyLock:new("wiola")
local sema = semaphore.new()
local wampServer, webSocket, ok, err, pingCo
local socketData = {}
local storeDataCount = 0

webSocket, err = wsServer:new({
    timeout = config.socketTimeout,
    max_payload_len = config.maxPayloadLen
})

if not webSocket then
    return ngx.exit(ngx.ERROR)
end

wampServer, err = wiola:new()
if not wampServer then
    return ngx.exit(ngx.ERROR)
end

local sessionId, dataType = wampServer:addConnection(ngx.var.connection, ngx.header["Sec-WebSocket-Protocol"])

local function removeConnection(_, sessId)
    local okk, errr

    local wconfig = require("wiola.config").config()
    local store = require('wiola.stores.' .. wconfig.store)

    okk, errr = store:init(wconfig)
    if not okk then
    else
        store:removeSession(sessId)
    end
end

local function removeConnectionWrapper()
    removeConnection(true, sessionId)
end

ok, err = ngx.on_abort(removeConnectionWrapper)
if not ok then
    ngx.exit(ngx.ERROR)
end

if config.pingInterval > 0 then
    local pinger = function (period)
        local bytes, lerr
        coroutine.yield()

        while true do
            bytes, lerr = webSocket:send_ping()
            if not bytes then
                ngx.timer.at(0, removeConnection, sessionId)
                ngx.exit(ngx.ERROR)
            end
            ngx.sleep(period)
        end
    end

    pingCo = ngx.thread.spawn(pinger, config.pingInterval / 1000)
end

local redNotifier = function ()
    local redisOk, redis, lres, lerr
    local redisLib = require "resty.redis"
    local lrestyLock = require "resty.lock"
    local lockR = lrestyLock:new("wiola")

    redis = redisLib:new()
    redis:set_timeouts(1000, 1000, 1000)

    if config.storeConfig.port == nil then
        redisOk, lerr = redis:connect(config.storeConfig.host)
    else
        redisOk, lerr = redis:connect(config.storeConfig.host, config.storeConfig.port)
    end

    if redisOk and config.storeConfig.db ~= nil then
        redis:select(config.storeConfig.db)
    end

    if not redisOk then
        ngx.timer.at(0, removeConnection, sessionId)
        ngx.exit(ngx.ERROR)
    end

    local sesskey = "__keyspace@" ..
            (config.storeConfig.db or 0) ..
            "__:wiSes" ..
            string.format("%.0f", sessionId) ..
            "Data"
    lres, lerr = redis:subscribe(sesskey)
    if not lres then
        ngx.timer.at(0, removeConnection, sessionId)
        ngx.exit(ngx.ERROR)
    end

    while true do
        lres, lerr = redis:read_reply()
        if not lres then
            if lerr ~= "timeout" then
                ngx.timer.at(0, removeConnection, sessionId)
                ngx.exit(ngx.ERROR)
            end
        else
            if lres[1] == "message" and lres[3] == "rpush" then
                local elapsed = lockR:lock("dataCount" .. sessionId)
                if elapsed ~= nil then
                    storeDataCount = storeDataCount + 1
                    sema:post(1)
                end
                lockR:unlock()
            end
        end
    end
end

ngx.thread.spawn(redNotifier)

local SocketHandler = function ()
    local lrestyLock = require "resty.lock"
    local lockS = lrestyLock:new("wiola")

    while true do
        local data, typ, bytes, lerr

        if webSocket.fatal then
            ngx.timer.at(0, removeConnection, sessionId)
            ngx.exit(ngx.ERROR)
        end

        data, typ = webSocket:recv_frame()

        if typ == "close" then
            if pingCo then
                ngx.thread.kill(pingCo)
            end
            webSocket:send_close(1000, "Closing connection")
            ngx.timer.at(0, removeConnection, sessionId)
            ngx.exit(ngx.OK)
            break

        elseif typ == "ping" then

            bytes, lerr = webSocket:send_pong()
            if not bytes then
                ngx.timer.at(0, removeConnection, sessionId)
                ngx.exit(ngx.ERROR)
            end

    --    elseif typ == "pong" then

        elseif typ == "text" then -- Received something texty
            local elapsed = lockS:lock("socketData" .. sessionId)
            if elapsed ~= nil then
                table.insert(socketData, data)
                sema:post(1)
            end
            lockS:unlock()

        elseif typ == "binary" then -- Received something binary
            local elapsed = lockS:lock("socketData" .. sessionId)
            if elapsed ~= nil then
                table.insert(socketData, data)
                sema:post(1)
            end
            lockS:unlock()

        end
    end
end

ngx.thread.spawn(SocketHandler)

while true do
    local lok, lerr = sema:wait(60)
    if not lok then
    else
        local hflags, cliData, bytes

        while storeDataCount > 0 do
            hflags = wampServer:getHandlerFlags(sessionId)
            cliData = wampServer:getPendingData(sessionId, hflags.sendLast)

            if cliData ~= ngx.null and cliData then
                if dataType == 'binary' then
                    bytes, err = webSocket:send_binary(cliData)
                else
                    bytes, err = webSocket:send_text(cliData)
                end

                if not bytes then
                end
            end

            if hflags.close == true then
                if pingCo then
                    ngx.thread.kill(pingCo)
                end
                webSocket:send_close(1000, "Closing connection")
                ngx.timer.at(0, removeConnection, sessionId)
                ngx.exit(ngx.OK)
            end

            local elapsed = lockM:lock("dataCount" .. sessionId)
            if elapsed ~= nil then
                storeDataCount = storeDataCount - 1
            end
            lockM:unlock()

        end

        local elapsed = lockM:lock("socketData" .. sessionId)
        if elapsed ~= nil then
            while #socketData > 0 do
                wampServer:receiveData(sessionId, table.remove(socketData, 1))
            end
        end
        lockM:unlock()

    end
end
