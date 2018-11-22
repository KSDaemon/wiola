--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--
local WAMP_PAYLOAD_LENGTHS = {
    [512] = 0,
    [1024] = 1,
    [2048] = 2,
    [4096] = 3,
    [8192] = 4,
    [16384] = 5,
    [32768] = 6,
    [65536] = 7,
    [131072] = 8,
    [262144] = 9,
    [524288] = 10,
    [1048576] = 11,
    [2097152] = 12,
    [4194304] = 13,
    [8388608] = 14,
    [16777216] = 15
}

local wiola = require "wiola"
local config = require("wiola.config").config()
local wiola_max_payload_len = WAMP_PAYLOAD_LENGTHS[config.maxPayloadLen] or 65536
local bit = require "bit"
local tcpSocket, wampServer, cliMaxLength, serializer, serializerStr, data, err, ok, cliData, pingCo

tcpSocket, err = ngx.req.socket(true)

if not tcpSocket then
    ngx.log(ngx.ERR, "Failed to initialize downstream socket: ", err)
    return ngx.exit(ngx.ERROR)
end

tcpSocket:settimeouts(config.socketTimeout, config.socketTimeout, config.socketTimeout)

wampServer, err = wiola:new()
if not wampServer then
    ngx.log(ngx.DEBUG, "Failed to create a wiola instance: ", err)
    return ngx.exit(ngx.ERROR)
end

data, err = tcpSocket:receive(4)

if data == nil then
    ngx.log(ngx.ERR, "Failed to receive data: ", err)
    return ngx.exit(ngx.ERROR)
end

if string.byte(data) ~= 0x7F then
    ngx.log(ngx.ERR, "Can not recognize WAMP handshake byte sequence")
    return ngx.exit(ngx.ERROR)
elseif string.byte(data, 3) ~= 0x0 or string.byte(data, 4) ~= 0x0 then
    ngx.log(ngx.ERR, "Reserved WAMP handshake bytes are not 0")
    cliData = string.char(0x7F, bit.bor(bit.lshift(3, 4), 0), 0, 0)
    tcpSocket:send(cliData)
    return ngx.exit(ngx.ERROR)
end

cliMaxLength = math.pow(2, 9 + bit.rshift(string.byte(data, 2), 4))
serializer = bit.band(string.byte(data, 2), 0xf)

if serializer == 1 then
    serializerStr = "wamp.2.json"
elseif serializer == 2 then
    serializerStr = "wamp.2.msgpack"
else
    ngx.log(ngx.ERR, "Can not recognize serializer to use (", serializer, ")")
    cliData = string.char(0x7F, bit.bor(bit.lshift(1, 4), 0), 0, 0)
    tcpSocket:send(cliData)
    return ngx.exit(ngx.ERROR)
end

local sessionId, dataType = wampServer:addConnection(ngx.var.connection, serializerStr)
ngx.log(ngx.DEBUG, "Adding connection to list. Conn Id: ", ngx.var.connection)
ngx.log(ngx.DEBUG, "Session Id: ", sessionId, " selected protocol: ", serializerStr)

cliData = string.char(0x7F, bit.bor(bit.lshift(wiola_max_payload_len, 4), serializer), 0, 0)
data, err = tcpSocket:send(cliData)

if not data then
    ngx.log(ngx.ERR, "Failed to send handshake data: ", err)
    return ngx.exit(ngx.ERROR)
end

local function removeConnection(_, sessId)
    ngx.log(ngx.DEBUG, "Cleaning up session: ", sessId)

    local wconfig = require("wiola.config").config()
    local store = require('wiola.stores.' .. config.store)

    ok, err = store:init(wconfig)
    if not ok then
        ngx.log(ngx.DEBUG, "Can not init datastore!", err)
    else
        store:removeSession(sessId)
        ngx.log(ngx.DEBUG, "Session data successfully removed!")
    end
end

local function removeConnectionWrapper()
    ngx.log(ngx.DEBUG, "client on_abort removeConnection callback fired!")
    removeConnection(true, sessionId)
end

ok, err = ngx.on_abort(removeConnectionWrapper)
if not ok then
    ngx.log(ngx.ERR, "failed to register the on_abort callback: ", err)
    ngx.exit(ngx.ERROR)
end

local function getLenBytes(len)
    local b3 = bit.band(len, 0xff)
    len = bit.rshift(len, 8)
    local b2 = bit.band(len, 0xff)
    len = bit.rshift(len, 8)
    local b1 = bit.band(len, 0xff)
    return string.char(b1, b2, b3)
end

if config.pingInterval > 0 then
    local pinger = function (period)
        local bytes, err, pingData
        coroutine.yield()

        while true do
            ngx.log(ngx.DEBUG, "Pinging client...")

            pingData = string.char(1) .. getLenBytes(1) .. 'p'
            bytes, err = tcpSocket:send(pingData)

            if not bytes then
                ngx.log(ngx.ERR, "Failed to send ping: ", err)
                ngx.timer.at(0, removeConnection, sessionId)
                ngx.exit(ngx.ERROR)
            end
            ngx.sleep(period)
        end
    end

    pingCo = ngx.thread.spawn(pinger, config.pingInterval / 1000)
end

while true do
    local hflags, msgType, msgLen

    --    ngx.log(ngx.DEBUG, "Checking data for client...")
    hflags = wampServer:getHandlerFlags(sessionId)
    cliData = wampServer:getPendingData(sessionId, hflags.sendLast)

    if cliData ~= ngx.null and cliData then

        msgLen = string.len(cliData)

        if msgLen < cliMaxLength then
            ngx.log(ngx.DEBUG, "Got data for client. DataType is ", dataType, ". Data: ", cliData, ". Sending...")
            cliData = string.char(0) .. getLenBytes(msgLen) .. cliData
            data, err = tcpSocket:send(cliData)

            if not data then
                ngx.log(ngx.ERR, "Failed to send data: ", err)
            end
        end

        -- TODO Handle exceeded message length situation
    end

    if hflags.close == true then
        ngx.log(ngx.DEBUG, "Got close connection flag for session")
        if pingCo then
            ngx.thread.kill(pingCo)
        end
        tcpSocket:shutdown("send")
        ngx.timer.at(0, removeConnection, sessionId)
        ngx.exit(ngx.OK)
    end

    data, err = tcpSocket:receive(4)

    if data ~= nil then
        msgType = bit.band(string.byte(data), 0xff)
        msgLen = bit.lshift(string.byte(data, 2), 16) +
                bit.lshift(string.byte(data, 3), 8) +
                string.byte(data, 4)

        if msgType == 0 then    -- regular WAMP message

            data, err = tcpSocket:receive(msgLen)

            if data == nil then
                ngx.log(ngx.ERR, "Failed to receive data: ", err)
                ngx.timer.at(0, removeConnection, sessionId)
                ngx.exit(ngx.ERROR)
            end

            ngx.log(ngx.DEBUG, "Received client data: ", data)
            wampServer:receiveData(sessionId, data)

        elseif msgType == 1 then    -- PING

            data, err = tcpSocket:receive(msgLen)

            if data == nil then
                ngx.log(ngx.ERR, "Failed to receive data: ", err)
                ngx.timer.at(0, removeConnection, sessionId)
                ngx.exit(ngx.ERROR)
            end

            cliData = string.char(2) .. msgLen .. data
            data, err = tcpSocket:send(cliData)

            if not data then
                ngx.log(ngx.ERR, "Failed to send data: ", err)
            end
        end
    elseif err == 'closed' then
        ngx.log(ngx.DEBUG, "Error reading socket: ", err)
        ngx.timer.at(0, removeConnection, sessionId)
        ngx.exit(ngx.ERROR)
    end
end
