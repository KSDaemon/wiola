--
-- Project: this project
-- User: kostik
-- Date: 20.06.14
--

local wampServer = require "wiola"
local realm = "hga"

local redisOk, redisErr = wampServer.setupRedis("unix:/tmp/redis.sock")
if not redisOk then
	return ngx.exit(444)
end

--local req = ngx.var.request_body
ngx.req.read_body()
local req = ngx.req.get_body_data()

local res, httpCode = wampServer.processPostData(ngx.var.connection, realm, req)

ngx.status = httpCode
ngx.say(res)

-- to cause quit the whole request rather than the current phase handler
ngx.exit(ngx.HTTP_OK)
