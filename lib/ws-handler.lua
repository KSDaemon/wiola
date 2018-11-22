--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--
local wsServer = require "resty.websocket.server"
local wiola = require "wiola"
local config = require("wiola.config").config()
local webSocket, wampServer, ok, err, bytes, pingCo

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

    local wconfig = require("wiola.config").config()
    local store = require('wiola.stores.' .. config.store)

    ok, err = store:init(wconfig)
    if not ok then
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
        coroutine.yield()

        while true do
            bytes, err = webSocket:send_ping()
            if not bytes then
                ngx.timer.at(0, removeConnection, sessionId)
                ngx.exit(ngx.ERROR)
            end
            ngx.sleep(period)
        end
    end

    pingCo = ngx.thread.spawn(pinger, config.pingInterval / 1000)
end

while true do
    local cliData, data, typ, hflags
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

        bytes, err = webSocket:send_pong()
        if not bytes then
            ngx.timer.at(0, removeConnection, sessionId)
            ngx.exit(ngx.ERROR)
        end

--    elseif typ == "pong" then

    elseif typ == "text" then -- Received something texty
        wampServer:receiveData(sessionId, data)

    elseif typ == "binary" then -- Received something binary
        wampServer:receiveData(sessionId, data)

    end
end
