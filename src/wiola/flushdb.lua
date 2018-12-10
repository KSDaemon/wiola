---
--- Project: wiola
--- User: Konstantin Burkalev
--- Date: 06.04.17
---

local _M = {}

---
--- Cleans up all wiola sessions data in redis store
---
function _M.flushAll()
    ngx.log(ngx.DEBUG, "Cleaning up all wiola sessions...")

    local conf = require("wiola.config").config()
    local redis = require "redis"
    local client = redis.connect(conf.storeConfig.host, conf.storeConfig.port)

    if conf.storeConfig.db then
        client:select(conf.storeConfig.db)
    end

    client:flushdb()

    ngx.log(ngx.DEBUG, "Sessions data successfully cleared!")
end

return _M
