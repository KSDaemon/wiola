package = "Wiola"
version = "0.6.1-1"

source = {
    url = "git://github.com/KSDaemon/wiola.git",
    tag = "v0.6.1"
}

description = {
    summary = "LUA WAMP router",
    detailed = [[
    WAMP implementation on Lua, using the power of LUA Nginx module,
    Lua-Resty-WebSocket addon, and Redis as cache store.
    This package works both in Nginx enviroment with installed ngx_lua
    and lua-resty-websocket modules and OpenResty platform.
    ]],
    homepage = "https://github.com/KSDaemon/wiola",
    license = "BSD 2-Clause license",
    maintainer = "Konstantin Burkalev <KSDaemon@ya.ru>"
}

dependencies = {
    "lua >= 5.1",
    "luarestyredis",
    "rapidjson >= 0.5",
    "lua-resty-hmac >= v1.0",
    "lua-messagepack >= 0.3",
    "redis-lua >= 2.0"
}

build = {
    type = 'builtin',
    modules = {
        ['wiola'] = 'lib/wiola.lua',
        ['wiola.cleanup'] = 'lib/cleanup.lua',
        ['wiola.flushdb'] = 'lib/flushdb.lua',
        ['wiola.config'] = 'lib/config.lua',
        ['wiola.handler'] = 'lib/handler.lua',
        ['wiola.headers'] = 'lib/headers.lua',
        ['wiola.post-handler'] = 'lib/post-handler.lua',
    }
}
