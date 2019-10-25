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
local semaphore = require "ngx.semaphore"
local sema = semaphore.new()
local tcpSocket, wampServer, cliMaxLength, serializer, serializerStr, data, err, ok, cliData, pingCo
local socketData = {}
local storeDataCount = 0

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

cliData = string.char(0x7F, bit.bor(bit.lshift(wiola_max_payload_len, 4), serializer), 0, 0)
data, err = tcpSocket:send(cliData)

if not data then
    ngx.log(ngx.ERR, "Failed to send handshake data: ", err)
    return ngx.exit(ngx.ERROR)
end

local sessionId, dataType = wampServer:addConnection(ngx.var.connection, serializerStr)
ngx.log(ngx.DEBUG, "New rawsocket client from ", ngx.var.remote_addr, ". Conn Id: ", ngx.var.connection)
ngx.log(ngx.DEBUG, "Session Id: ", sessionId, " selected protocol: ", serializerStr)

local function removeConnection(_, sessId)
    local okk, errr
    ngx.log(ngx.DEBUG, "Cleaning up session: ", sessId)

    local wconfig = require("wiola.config").config()
    local store = require('wiola.stores.' .. config.store)

    okk, errr = store:init(wconfig)
    if not okk then
        ngx.log(ngx.DEBUG, "Can not init datastore!", errr)
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
        local pingData
        coroutine.yield()

        while true do
            ngx.log(ngx.DEBUG, "Pinging client...")

            pingData = string.char(1) .. getLenBytes(1) .. 'p'
            data, err = tcpSocket:send(pingData)

            if not data then
                ngx.log(ngx.ERR, "Failed to send ping: ", err)
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

    redis = redisLib:new()
    redis:set_timeout(0)

    if config.storeConfig.port == nil then
        redisOk, lerr = redis:connect(config.storeConfig.host)
    else
        redisOk, lerr = redis:connect(config.storeConfig.host, config.storeConfig.port)
    end

    if redisOk and config.storeConfig.db ~= nil then
        redis:select(config.storeConfig.db)
    end

    if not redisOk then
        ngx.log(ngx.ERR, "Failed to initialize redis connection: ", lerr)
        ngx.timer.at(0, removeConnection, sessionId)
        ngx.exit(ngx.ERROR)
    end

    local sesskey = "__keyspace@" ..
            (config.storeConfig.db or 0) ..
            "__:wiSes" ..
            string.format("%.0f", sessionId) ..
            "Data"
    ngx.log(ngx.DEBUG, "Subscribing to redis notification for key: ", sesskey)
    lres, lerr = redis:subscribe(sesskey)
    if not lres then
        ngx.log(ngx.ERR, "Failed to subscribe to redis topic: ", lerr)
        ngx.timer.at(0, removeConnection, sessionId)
        ngx.exit(ngx.ERROR)
    end

    coroutine.yield()

    while true do
        lres, lerr = redis:read_reply()
        if not lres then
            ngx.log(ngx.ERR, "Failed to read redis reply: ", lerr)
            ngx.timer.at(0, removeConnection, sessionId)
            ngx.exit(ngx.ERROR)
        end

        ngx.log(ngx.DEBUG, "Received redis notification!")
        if lres[1] == "message" and lres[3] == "rpush" then
            ngx.log(ngx.DEBUG, "Received rpush redis notification!")
            storeDataCount = storeDataCount + 1
            sema:post(1)
        end
    end
end

ngx.thread.spawn(redNotifier)

local SocketHandler = function ()
    while true do
        local sockData, err, msgType, msgLen

        sockData, err = tcpSocket:receive(4)

        if sockData ~= nil then
            msgType = bit.band(string.byte(sockData), 0xff)
            msgLen = bit.lshift(string.byte(sockData, 2), 16) +
                    bit.lshift(string.byte(sockData, 3), 8) +
                    string.byte(sockData, 4)

            if msgType == 0 then    -- regular WAMP message

                sockData, err = tcpSocket:receive(msgLen)

                if sockData == nil then
                    ngx.log(ngx.ERR, "Failed to receive data: ", err)
                    ngx.timer.at(0, removeConnection, sessionId)
                    ngx.exit(ngx.ERROR)
                end

                ngx.log(ngx.DEBUG, "Received client data")
                table.insert(socketData, sockData)
                sema:post(1)

            elseif msgType == 1 then    -- PING

                sockData, err = tcpSocket:receive(msgLen)

                if sockData == nil then
                    ngx.log(ngx.ERR, "Failed to receive data: ", err)
                    ngx.timer.at(0, removeConnection, sessionId)
                    ngx.exit(ngx.ERROR)
                end

                cliData = string.char(2) .. msgLen .. sockData
                sockData, err = tcpSocket:send(cliData)

                if not sockData then
                    ngx.log(ngx.ERR, "Failed to send data: ", err)
                end
            end
        elseif err == 'closed' then
            ngx.log(ngx.DEBUG, "Error reading socket: ", err)
            ngx.timer.at(0, removeConnection, sessionId)
            ngx.exit(ngx.ERROR)
        end
    end
end

ngx.thread.spawn(SocketHandler)


while true do
    local ok, err = sema:wait(60)  -- wait for a second at most
    if not ok then
        ngx.log(ngx.DEBUG, "main thread: failed to wait on sema: ", err)
    else
        local hflags, msgLen

        ngx.log(ngx.DEBUG, "main thread: waited successfully.")

        while storeDataCount > 0 do
            hflags = wampServer:getHandlerFlags(sessionId)
            cliData = wampServer:getPendingData(sessionId, hflags.sendLast)

            if cliData ~= ngx.null and cliData then
                msgLen = string.len(cliData)

                if msgLen < cliMaxLength then
                    ngx.log(ngx.DEBUG, "Got data for client. DataType is ", dataType, ". Sending...")
                    --ngx.log(ngx.DEBUG, "Escaped client data: ", numericbin(cliData), ". Sending...")
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

            storeDataCount = storeDataCount - 1
        end

        while #socketData > 0 do
            wampServer:receiveData(sessionId, table.remove(socketData, 1))
        end
    end
end
