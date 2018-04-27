--
-- Project: this project
-- User: kostik
-- Date: 20.06.14
--

local wiola = require "wiola"
local wampServer = wiola:new()
local realm = "testRealm"

ngx.req.read_body()
local req = ngx.req.get_body_data()

local res, httpCode = wampServer.processPostData(ngx.var.connection, realm, req)

ngx.status = httpCode
ngx.say(res)    -- returns response to client

-- to cause quit the whole request rather than the current phase handler
ngx.exit(ngx.HTTP_OK)
