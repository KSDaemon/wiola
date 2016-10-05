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
    ngx.log(ngx.ERR, "Failed to create new websocket: ", err)
    return ngx.exit(444)
end

ngx.log(ngx.DEBUG, "Created websocket")

local redisOk, redisErr = wampServer:setupRedis("unix:/tmp/redis.sock")
if not redisOk then
    ngx.log(ngx.DEBUG, "Failed to connect to redis: ", redisErr)
    return ngx.exit(444)
end

local sessionId, dataType = wampServer:addConnection(ngx.var.connection, ngx.header["Sec-WebSocket-Protocol"])
ngx.log(ngx.DEBUG, "Adding connection to list. Conn Id: ", ngx.var.connection)
ngx.log(ngx.DEBUG, "Session Id: ", sessionId, " selected protocol: ", ngx.header["Sec-WebSocket-Protocol"])

local cleanExit = false

while true do
    local data, typ, err = webSocket:recv_frame()

    local cliData, cliErr = wampServer:getPendingData(sessionId)

    while cliData ~= ngx.null do
        ngx.log(ngx.DEBUG, "Got data for client. DataType is ", dataType, ". Sending...")

        if dataType == 'binary' then
            local bytes, err = webSocket:send_binary(cliData)
        else
            local bytes, err = webSocket:send_text(cliData)
        end

        if not bytes then
            ngx.log(ngx.ERR, "Failed to send data: ", err)
        end

        cliData, cliErr = wampServer:getPendingData(sessionId)
    end

    if webSocket.fatal then
        ngx.log(ngx.ERR, "Failed to receive frame: ", err)
        wampServer:removeConnection(sessionId)
        return ngx.exit(444)
    end

    if not data then

        local bytes, err = webSocket:send_ping()
        if not bytes then
            ngx.log(ngx.ERR, "Failed to send ping: ", err)
            wampServer:removeConnection(sessionId)
            return ngx.exit(444)
        end

    elseif typ == "close" then

        ngx.log(ngx.DEBUG, "Normal closing websocket. SID: ", ngx.var.connection)
        wampServer:removeConnection(sessionId)
        local bytes, err = webSocket:send_close(1000, "Closing connection")
            if not bytes then
                ngx.log(ngx.ERR, "Failed to send the close frame: ", err)
                return
            end
        cleanExit = true
        break

    elseif typ == "ping" then

        local bytes, err = webSocket:send_pong()
        if not bytes then
            ngx.log(ngx.ERR, "Failed to send pong: ", err)
            wampServer:removeConnection(sessionId)
            return ngx.exit(444)
        end

    elseif typ == "pong" then

--        ngx.log(ngx.DEBUG, "client ponged")

    elseif typ == "text" then -- Received something texty

        ngx.log(ngx.DEBUG, "Received text data: ", data)
        wampServer:receiveData(sessionId, data)

    elseif typ == "binary" then -- Received something binary

        ngx.log(ngx.DEBUG, "Received binary data")
        wampServer:receiveData(sessionId, data)

    end
end

-- Just for clearance
if not cleanExit then
    webSocket:send_close()
    wampServer:removeConnection(sessionId)
end
