package = "Wiola"
version = "0.13.1-1"

source = {
    url = "git://github.com/KSDaemon/wiola.git",
    tag = "v0.13.1"
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
    "lua-messagepack >= 0.4",
    "redis-lua >= 2.0"
}

build = {
    type = 'builtin',
    modules = {
        ['wiola'] = 'lib/wiola.lua',
        ['wiola.config'] = 'lib/wiola/config.lua',
        ['wiola.flushdb'] = 'lib/wiola/flushdb.lua',
        ['wiola.ws-handler'] = 'lib/wiola/ws-handler.lua',
        ['wiola.raw-handler'] = 'lib/wiola/raw-handler.lua',
        ['wiola.headers'] = 'lib/wiola/headers.lua',
        ['wiola.post-handler'] = 'lib/wiola/post-handler.lua',
        ['wiola.serializers.json_serializer'] = 'lib/wiola/serializers/json_serializer.lua',
        ['wiola.serializers.msgpack_serializer'] = 'lib/wiola/serializers/msgpack_serializer.lua',
        ['wiola.stores.redis'] = 'lib/wiola/stores/redis.lua',
    }
}
