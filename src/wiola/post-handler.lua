--
-- Project: this project
-- User: kostik
-- Date: 20.06.14
--

local wiola = require "wiola"
local wampServer = wiola:new()
local realm = "testRealm"

local redisOk, redisErr = wampServer:setupRedis("unix:/tmp/redis.sock")
if not redisOk then
    ngx.log(ngx.DEBUG, "Failed to connect to redis: ", redisErr)
    return ngx.exit(444)
end

ngx.req.read_body()
local req = ngx.req.get_body_data()

local res, httpCode = wampServer.processPostData(ngx.var.connection, realm, req)

ngx.status = httpCode
ngx.say(res)    -- returns response to client

-- to cause quit the whole request rather than the current phase handler
ngx.exit(ngx.HTTP_OK)
