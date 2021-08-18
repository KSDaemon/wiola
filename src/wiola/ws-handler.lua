--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--

--local numericbin = require("debug.vardump").numericbin
local wsServer = require "resty.websocket.server"
local wiola = require "wiola"
local config = require("wiola.config").config()
local semaphore = require "ngx.semaphore"
local sema = semaphore.new()
local wampServer, webSocket, ok, err, pingCo
local socketData = {}
local storeDataCount = 0

webSocket, err = wsServer:new({
    timeout = config.socketTimeout,
    max_payload_len = config.maxPayloadLen
})

if not webSocket then
    ngx.log(ngx.ERR, "Failed to create new websocket: ", err)
    return ngx.exit(ngx.ERROR)
end

ngx.log(ngx.DEBUG, "Created websocket")

wampServer, err = wiola:new()
if not wampServer then
    ngx.log(ngx.DEBUG, "Failed to create a wiola instance: ", err)
    return ngx.exit(ngx.ERROR)
end

local sessionId, dataType = wampServer:addConnection(ngx.var.connection, ngx.header["Sec-WebSocket-Protocol"])
ngx.log(ngx.DEBUG, "New websocket client from ", ngx.var.remote_addr, ". Conn Id: ", ngx.var.connection)
ngx.log(ngx.DEBUG, "Session Id: ", sessionId, " selected protocol: ", ngx.header["Sec-WebSocket-Protocol"])

local function removeConnection(_, sessId)
    local okk, errr
    ngx.log(ngx.DEBUG, "Cleaning up session: ", sessId)

    local wconfig = require("wiola.config").config()
    local store = require('wiola.stores.' .. wconfig.store)

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

if config.pingInterval > 0 then
    local pinger = function (period)
        local bytes, lerr
        coroutine.yield()

        while true do
            ngx.log(ngx.DEBUG, "Pinging client...")
            bytes, lerr = webSocket:send_ping()
            if not bytes then
                ngx.log(ngx.ERR, "Failed to send ping: ", lerr)
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
        local data, typ, bytes, lerr

        if webSocket.fatal then
            ngx.timer.at(0, removeConnection, sessionId)
            ngx.exit(ngx.ERROR)
        end

        data, typ = webSocket:recv_frame()
        --ngx.log(ngx.DEBUG, "Received WS Frame. Type is ", typ)

        if typ == "close" then

            ngx.log(ngx.DEBUG, "Normal closing websocket. SID: ", ngx.var.connection)
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
                ngx.log(ngx.ERR, "Failed to send pong: ", lerr)
                ngx.timer.at(0, removeConnection, sessionId)
                ngx.exit(ngx.ERROR)
            end

    --    elseif typ == "pong" then

    --        ngx.log(ngx.DEBUG, "client ponged")

        elseif typ == "text" then -- Received something texty

            ngx.log(ngx.DEBUG, "Received text data: ", data)
            table.insert(socketData, data)
            sema:post(1)

        elseif typ == "binary" then -- Received something binary

            ngx.log(ngx.DEBUG, "Received binary data")
            table.insert(socketData, data)
            sema:post(1)
        end
    end
end

ngx.thread.spawn(SocketHandler)

while true do
    local ok, err = sema:wait(60)  -- wait for a second at most
    if not ok then
        ngx.log(ngx.DEBUG, "main thread: failed to wait on sema: ", err)
    else
        local hflags, cliData, bytes

        ngx.log(ngx.DEBUG, "main thread: waited successfully.")

        while storeDataCount > 0 do
            hflags = wampServer:getHandlerFlags(sessionId)
            cliData = wampServer:getPendingData(sessionId, hflags.sendLast)

            if cliData ~= ngx.null and cliData then
                if dataType == 'binary' then
                    ngx.log(ngx.DEBUG, "Got data for client. DataType is ", dataType, ". Sending...")
                    --ngx.log(ngx.DEBUG, "Escaped binary data: ", numericbin(cliData), ". Sending...")
                    bytes, err = webSocket:send_binary(cliData)
                else
                    ngx.log(ngx.DEBUG, "Got data for client. DataType is ", dataType, ". Sending...")
                    ngx.log(ngx.DEBUG, "Client data: ", cliData)
                    bytes, err = webSocket:send_text(cliData)
                end

                if not bytes then
                    ngx.log(ngx.ERR, "Failed to send data: ", err)
                end
            end

            if hflags.close == true then
                ngx.log(ngx.DEBUG, "Got close connection flag for session")
                if pingCo then
                    ngx.thread.kill(pingCo)
                end
                webSocket:send_close(1000, "Closing connection")
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
