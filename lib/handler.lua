--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--
local wsServer = require "resty.websocket.server"
local wiola = require "wiola"
local webSocket, wampServer, ok, err, bytes

webSocket, err = wsServer:new({
    timeout = tonumber(ngx.var.wiola_socket_timeout, 10) or 100,
    max_payload_len = tonumber(ngx.var.wiola_max_payload_len, 10) or 65535
})

if not webSocket then
    return ngx.exit(444)
end

wampServer, err = wiola:new()
if not wampServer then
    return ngx.exit(444)
end

local sessionId, dataType = wampServer:addConnection(ngx.var.connection, ngx.header["Sec-WebSocket-Protocol"])

local function removeConnection(_, sessId)

    local config = require("wiola.config").config()
    local store = require('wiola.stores.' .. config.store)

    ok, err = store:init(config)
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
    ngx.exit(444)
end

while true do
    local cliData, data, typ, hflags

    hflags = wampServer:getHandlerFlags(sessionId)
    if hflags ~= nil then
        if hflags.sendLast == true then
            cliData = wampServer:getPendingData(sessionId, true)

            if dataType == 'binary' then
                bytes, err = webSocket:send_binary(cliData)
            else
                bytes, err = webSocket:send_text(cliData)
            end

            if not bytes then
            end
        end

        if hflags.close == true then
            ngx.timer.at(0, removeConnection, sessionId)
            return ngx.exit(444)
        end
    end
    cliData = wampServer:getPendingData(sessionId)

    while cliData ~= ngx.null do
        if dataType == 'binary' then
            bytes, err = webSocket:send_binary(cliData)
        else
            bytes, err = webSocket:send_text(cliData)
        end

        if not bytes then
        end

        cliData = wampServer:getPendingData(sessionId)
    end

    if webSocket.fatal then
        ngx.timer.at(0, removeConnection, sessionId)
        return ngx.exit(444)
    end

    data, typ = webSocket:recv_frame()

    if not data then

        bytes, err = webSocket:send_ping()
        if not bytes then
            ngx.timer.at(0, removeConnection, sessionId)
            return ngx.exit(444)
        end

    elseif typ == "close" then
        bytes, err = webSocket:send_close(1000, "Closing connection")
            if not bytes then
                return
            end
        ngx.timer.at(0, removeConnection, sessionId)
        webSocket:send_close()
        break

    elseif typ == "ping" then

        bytes, err = webSocket:send_pong()
        if not bytes then
            ngx.timer.at(0, removeConnection, sessionId)
            return ngx.exit(444)
        end

--    elseif typ == "pong" then

    elseif typ == "text" then -- Received something texty
        wampServer:receiveData(sessionId, data)

    elseif typ == "binary" then -- Received something binary
        wampServer:receiveData(sessionId, data)

    end
end
