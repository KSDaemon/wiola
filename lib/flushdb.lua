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

    local conf = require("wiola.config").config()
    local redis = require "redis"
    local client = redis.connect(conf.redis.host, conf.redis.port)

    if conf.redis.db then
        client:select(conf.redis.db)
    end

    client:flushdb()
end

return _M
