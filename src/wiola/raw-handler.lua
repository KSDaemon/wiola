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
local tcpSocket, wampServer, cliMaxLength, serializer, serializerStr, data, err, ok, cliData

tcpSocket, err = ngx.req.socket(true)

if not tcpSocket then
    ngx.log(ngx.ERR, "Failed to initialize downstream socket: ", err)
    return ngx.exit(444)
end

tcpSocket:settimeout(config.socketTimeout)

wampServer, err = wiola:new()
if not wampServer then
    ngx.log(ngx.DEBUG, "Failed to create a wiola instance: ", err)
    return ngx.exit(444)
end

data, err = tcpSocket:receive(4)

if data == nil then
    ngx.log(ngx.ERR, "Failed to receive data: ", err)
    return ngx.exit(444)    -- tcpSocket:close()
end

if string.byte(data) ~= 0x7F then
    ngx.log(ngx.ERR, "Can not recognize WAMP handshake byte sequence")
    return ngx.exit(444)
elseif string.byte(data, 3) ~= 0x0 or string.byte(data, 4) ~= 0x0 then
    ngx.log(ngx.ERR, "Reserved WAMP handshake bytes are not 0")
    cliData = string.char(0x7F, bit.bor(bit.lshift(3, 4), 0), 0, 0)
    tcpSocket:send(cliData)
    return ngx.exit(444)
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
    return ngx.exit(444)
end

local sessionId, dataType = wampServer:addConnection(ngx.var.connection, serializerStr)
ngx.log(ngx.DEBUG, "Adding connection to list. Conn Id: ", ngx.var.connection)
ngx.log(ngx.DEBUG, "Session Id: ", sessionId, " selected protocol: ", serializerStr)

cliData = string.char(0x7F, bit.bor(bit.lshift(wiola_max_payload_len, 4), serializer), 0, 0)
data, err = tcpSocket:send(cliData)

if not data then
    ngx.log(ngx.ERR, "Failed to send handshake data: ", err)
    return ngx.exit(444)
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
    ngx.exit(444)
end

local function getLenBytes(len)
    local b3 = bit.band(len, 0xff)
    len = bit.rshift(len, 8)
    local b2 = bit.band(len, 0xff)
    len = bit.rshift(len, 8)
    local b1 = bit.band(len, 0xff)
    return string.char(b1, b2, b3)
end

while true do
--    ngx.log(ngx.DEBUG, "Started handler loop!")
    local hflags, msgType, msgLen

    hflags = wampServer:getHandlerFlags(sessionId)
    if hflags ~= nil then
        if hflags.sendLast == true then
            cliData = wampServer:getPendingData(sessionId, true)

            data, err = tcpSocket:send(cliData)

            if not data then
                ngx.log(ngx.ERR, "Failed to send data: ", err)
            end
        end

        if hflags.close == true then
            ngx.log(ngx.DEBUG, "Got close connection flag for session")
            ngx.timer.at(0, removeConnection, sessionId)
            return ngx.exit(444)
        end
    end

--    ngx.log(ngx.DEBUG, "Checking data for client...")
    cliData = wampServer:getPendingData(sessionId)

    while cliData ~= ngx.null do

        msgLen = string.len(cliData)

        if msgLen < cliMaxLength then
            ngx.log(ngx.DEBUG, "Got data for client. DataType is ", dataType, ". Sending...")
            cliData = string.char(0) .. getLenBytes(msgLen) .. cliData
            data, err = tcpSocket:send(cliData)

            if not data then
                ngx.log(ngx.ERR, "Failed to send data: ", err)
            end
        end

        -- TODO Handle exceeded message length situation

        cliData = wampServer:getPendingData(sessionId)
    end

    data, err = tcpSocket:receive(4)

    if data == nil then
        ngx.log(ngx.ERR, "Failed to receive data: ", err)
        ngx.timer.at(0, removeConnection, sessionId)
        return ngx.exit(444)
    end

    msgType = bit.band(string.byte(data), 0xff)
    msgLen = bit.lshift(string.byte(data, 2), 16) +
            bit.lshift(string.byte(data, 3), 8) +
            string.byte(data, 4)

    if msgType == 0 then    -- regular WAMP message

        data, err = tcpSocket:receive(msgLen)

        if data == nil then
            ngx.log(ngx.ERR, "Failed to receive data: ", err)
            ngx.timer.at(0, removeConnection, sessionId)
            return ngx.exit(444)
        end

        wampServer:receiveData(sessionId, data)

    elseif msgType == 1 then    -- PING

        data, err = tcpSocket:receive(msgLen)

        if data == nil then
            ngx.log(ngx.ERR, "Failed to receive data: ", err)
            ngx.timer.at(0, removeConnection, sessionId)
            return ngx.exit(444)
        end

        cliData = string.char(2) .. msgLen .. data
        data, err = tcpSocket:send(cliData)

        if not data then
            ngx.log(ngx.ERR, "Failed to send data: ", err)
        end

--    elseif msgType == 2 then    -- PONG
        -- TODO Implement server initiated ping

    end

--    ngx.log(ngx.DEBUG, "Finished handler loop!")
end
