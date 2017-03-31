--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 01.11.16
--


-- Redis connection configuration
local redisConf = {
    host = "unix:/tmp/redis.sock",
    port = nil,
    db = nil
}

-- Wiola Runtime configuration
local wiolaConf = {
    callerIdentification = "auto",   -- auto | never | always
    cookieAuth = {
        authType = "none",          -- none | static | dynamic
        cookieName = "wampauth",
        staticCredentials = nil, --{
            -- "user1", "user2:password2", "secretkey3"
        --},
        authCallback = nil
    },
    wampCRA = {
        authType = "none",          -- none | static | dynamic
        staticCredentials = nil, --{
            -- user1 = { authrole = "userRole1", secret="secret1" },
            -- user2 = { authrole = "userRole2", secret="secret2" }
        --},
        challengeCallback = nil,
        authCallback = nil
    }
}

local _M = {}

--
-- Get or set Wiola Runtime configuration
--
-- config - Configuration table with possible options:
--          {
--              redis = {
--                  host = string - redis host or unix socket (default: "unix:/tmp/redis.sock"),
--                  port = number - redis port in case of network use (default: nil),
--                  db = number - redis database to select (default: nil)
--              },
--              callerIdentification = string - Disclose caller identification?
--                                              Possible values: auto | never | always. (default: "auto")
--          }
-- without params it just returns current configuration
--
function _M.config(config)

    if not config then
        local conf = wiolaConf
        conf.redis = redisConf
        return conf
    end

    if config.redis then

        if config.redis.host ~= nil then
            redisConf.host = config.redis.host
        end

        if config.redis.port ~= nil then
            redisConf.port = config.redis.port
        end

        if config.redis.db ~= nil then
            redisConf.db = config.redis.db
        end
    end

    if config.callerIdentification ~= nil then
        wiolaConf.callerIdentification = config.callerIdentification
    end

    if config.cookieAuth then

        if config.cookieAuth.authType ~= nil then
            wiolaConf.cookieAuth.authType = config.cookieAuth.authType
        end

        if config.cookieAuth.cookieName ~= nil then
            wiolaConf.cookieAuth.cookieName = config.cookieAuth.cookieName
        end

        if config.cookieAuth.staticCredentials ~= nil then
            wiolaConf.cookieAuth.staticCredentials = config.cookieAuth.staticCredentials
        end

        if config.cookieAuth.authCallback ~= nil then
            wiolaConf.cookieAuth.authCallback = config.cookieAuth.authCallback
        end
    end

    if config.wampCRA then

        if config.wampCRA.authType ~= nil then
            wiolaConf.wampCRA.authType = config.wampCRA.authType
        end

        if config.wampCRA.staticCredentials ~= nil then
            wiolaConf.wampCRA.staticCredentials = config.wampCRA.staticCredentials
        end

        if config.wampCRA.challengeCallback ~= nil then
            wiolaConf.wampCRA.challengeCallback = config.wampCRA.challengeCallback
        end

        if config.wampCRA.authCallback ~= nil then
            wiolaConf.wampCRA.authCallback = config.wampCRA.authCallback
        end
    end
end

return _M
