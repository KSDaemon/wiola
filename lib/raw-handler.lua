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
    return ngx.exit(444)
end

tcpSocket:settimeout(config.socketTimeout)

wampServer, err = wiola:new()
if not wampServer then
    return ngx.exit(444)
end

data, err = tcpSocket:receive(4)

if data == nil then
    return ngx.exit(444)    -- tcpSocket:close()
end

if string.byte(data) ~= 0x7F then
    return ngx.exit(444)
elseif string.byte(data, 3) ~= 0x0 or string.byte(data, 4) ~= 0x0 then
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
    cliData = string.char(0x7F, bit.bor(bit.lshift(1, 4), 0), 0, 0)
    tcpSocket:send(cliData)
    return ngx.exit(444)
end

local sessionId, dataType = wampServer:addConnection(ngx.var.connection, serializerStr)

cliData = string.char(0x7F, bit.bor(bit.lshift(wiola_max_payload_len, 4), serializer), 0, 0)
data, err = tcpSocket:send(cliData)

if not data then
    return ngx.exit(444)
end

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
    local hflags, msgType, msgLen

    hflags = wampServer:getHandlerFlags(sessionId)
    if hflags ~= nil then
        if hflags.sendLast == true then
            cliData = wampServer:getPendingData(sessionId, true)

            data, err = tcpSocket:send(cliData)

            if not data then
            end
        end

        if hflags.close == true then
            ngx.timer.at(0, removeConnection, sessionId)
            return ngx.exit(444)
        end
    end
    cliData = wampServer:getPendingData(sessionId)

    while cliData ~= ngx.null do

        msgLen = string.len(cliData)

        if msgLen < cliMaxLength then
            cliData = string.char(0) .. getLenBytes(msgLen) .. cliData
            data, err = tcpSocket:send(cliData)

            if not data then
            end
        end

        -- TODO Handle exceeded message length situation

        cliData = wampServer:getPendingData(sessionId)
    end

    data, err = tcpSocket:receive(4)

    if data == nil then
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
            ngx.timer.at(0, removeConnection, sessionId)
            return ngx.exit(444)
        end

        wampServer:receiveData(sessionId, data)

    elseif msgType == 1 then    -- PING

        data, err = tcpSocket:receive(msgLen)

        if data == nil then
            ngx.timer.at(0, removeConnection, sessionId)
            return ngx.exit(444)
        end

        cliData = string.char(2) .. msgLen .. data
        data, err = tcpSocket:send(cliData)

        if not data then
        end

--    elseif msgType == 2 then    -- PONG
        -- TODO Implement server initiated ping

    end
end
