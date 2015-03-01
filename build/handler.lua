--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--
local wsServer = require "resty.websocket.server"
local wiola = require "wiola"
local wampServer = wiola:new()

local webSocket, err = wsServer:new({
    timeout = 5000,
    max_payload_len = 65535
})

if not webSocket then
    return ngx.exit(444)
end

local redisOk, redisErr = wampServer:setupRedis("unix:/tmp/redis.sock")
if not redisOk then
    return ngx.exit(444)
end

local sessionId, dataType = wampServer:addConnection(ngx.var.connection, ngx.header["Sec-WebSocket-Protocol"])

local cleanExit = false

while true do
    local data, typ, err = webSocket:recv_frame()

    local cliData, cliErr = wampServer:getPendingData(sessionId)

    while cliData ~= ngx.null do

        if dataType == 'binary' then
            local bytes, err = webSocket:send_binary(cliData)
        else
            local bytes, err = webSocket:send_text(cliData)
        end

        if not bytes then
        end

        cliData, cliErr = wampServer:getPendingData(sessionId)
    end

    if webSocket.fatal then
        wampServer:removeConnection(sessionId)
        return ngx.exit(444)
    end

    if not data then

        local bytes, err = webSocket:send_ping()
        if not bytes then
            wampServer:removeConnection(sessionId)
            return ngx.exit(444)
        end

    elseif typ == "close" then
        wampServer:removeConnection(sessionId)
        local bytes, err = webSocket:send_close(1000, "Closing connection")
            if not bytes then
                return
            end
        cleanExit = true
        break

    elseif typ == "ping" then

        local bytes, err = webSocket:send_pong()
        if not bytes then
            wampServer:removeConnection(sessionId)
            return ngx.exit(444)
        end

    elseif typ == "pong" then

    elseif typ == "text" then -- Received something texty
        wampServer:receiveData(sessionId, data)

    elseif typ == "binary" then -- Received something binary
        wampServer:receiveData(sessionId, data)

    end
end

-- Just for clearance
if not cleanExit then
    webSocket:send_close()
    wampServer:removeConnection(sessionId)
end
