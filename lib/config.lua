--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 01.11.16
--

--[[
-- Config examples
local storeConfigs = {
    -- Redis connection configuration
    redis = {
        host = "unix:///tmp/redis.sock",
        port = nil,
        db = nil
    },

    -- Postgres connection configuration
    postgres = {
    --    host = "unix:///var/run/postgresql/.s.PGSQL.5432",
        host = "127.0.0.1",
        port = 5432,
        db = "wiola",
        user="admin",
        password="123456"
    }
}
]]--

-- Wiola Runtime configuration
local wiolaConf = {
    socketTimeout = 100,
    maxPayloadLen = 65536,
    realms = {},
    store = "redis",
    storeConfig = {
        host = "unix:///tmp/redis.sock",
        port = nil,
        db = nil
    },
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
    },
    trustLevels = {
        authType = "none",          -- none | static | dynamic
        defaultTrustLevel = nil,
        staticCredentials = {
            byAuthid = {
                --{ authid = "user1", trustlevel = 1 },
                --{ authid = "admin1", trustlevel = 5 }
            },
            byAuthRole = {
                --{ authrole = "user-role", trustlevel = 2 },
                --{ authrole = "admin-role", trustlevel = 4 }
            },
            byClientIp = {
                --{ clientip = "127.0.0.1", trustlevel = 10 }
            }
        },
        authCallback = nil -- function that accepts (client ip address, realm,
                           -- authid, authrole) and returns trust level
    },
    metaAPI = {
        session = false,
        subscription = false,
        registration = false
    }
}

local _M = {}

--
-- Get or set Wiola Runtime configuration
--
-- config - Configuration table
-- without params it just returns current configuration
--
function _M.config(config)

    if not config then
        return wiolaConf
    end

    if config.socketTimeout then
        wiolaConf.socketTimeout = config.socketTimeout
    end

    if config.maxPayloadLen then
        wiolaConf.maxPayloadLen = config.maxPayloadLen
    end

    if config.realms then
        wiolaConf.realms = config.realms
    end

    if config.store then
        wiolaConf.store = config.store
    end

    if config.storeConfig then
        wiolaConf.storeConfig = config.storeConfig
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

    if config.trustLevels then

        if config.trustLevels.authType ~= nil then
            wiolaConf.trustLevels.authType = config.trustLevels.authType
        end

        if config.trustLevels.defaultTrustLevel ~= nil then
            wiolaConf.trustLevels.defaultTrustLevel = config.trustLevels.defaultTrustLevel
        end

        if config.trustLevels.staticCredentials ~= nil then
            wiolaConf.trustLevels.staticCredentials = config.trustLevels.staticCredentials
        end

        if config.trustLevels.authCallback ~= nil then
            wiolaConf.trustLevels.authCallback = config.trustLevels.authCallback
        end
    end

    if config.metaAPI then

        if config.metaAPI.session ~= nil then
            wiolaConf.metaAPI.session = config.metaAPI.session
        end

        if config.metaAPI.subscription ~= nil then
            wiolaConf.metaAPI.subscription = config.metaAPI.subscription
        end

        if config.metaAPI.registration ~= nil then
            wiolaConf.metaAPI.registration = config.metaAPI.registration
        end
    end
end

return _M
