wiola
=====

WAMP (WebSocket Application Messaging Protocol) implementation on Lua, using the power of LUA Nginx module,
Lua WebSocket addon, and Redis as cache store.

Table of Contents
=================

* [Description](#description)
* [Usage example](#usage-example)
* [Installation](#installation)
* [Dependencies](#dependencies)
* [Methods](#methods)
	* [addConnection](#addconnection)
	* [removeConnection](#removeconnection)
	* [receiveData](#receivedata)
	* [getPendingData](#getpendingdata)
* [Copyright and License](#copyright-and-license)
* [See Also](#see-also)

Description
===========

Wiola implements [WAMP](http://wamp.ws) v2 router specification on top of OpenResty web app server,
 which is actually nginx plus a bunch of 3rd party modules, such as lua-nginx-module, lua-resty-websocket,
 lua-resty-redis and so on.

wiola supports next WAMP roles and features:

* broker: advanced profile with features:
	* subscriber blackwhite listing
	* publisher exclusion
	* publisher identification
* dealer: basic profile.

Wiola supports JSON and msgpack serializers.

[Back to TOC](#table-of-contents)

Usage example
=============

For example usage, please see handler.lua file.

[Back to TOC](#table-of-contents)

Installation
============

To use wiola you need:
* Nginx
* lua-nginx-module
* lua-resty-websocket module
* lua-resty-redis module
* luajit
* [lua-MessagePack](http://fperrad.github.io/lua-MessagePack/) library
* Redis server

Instead of compiling lua-* modules into nginx, you can simply use [OpenResty](http://openresty.org) server.

Next thing is configuring nginx host. See example below.

```nginx
# set search paths for pure Lua external libraries (';;' is the default path):
# add paths for wiola and msgpack libs
lua_package_path '/usr/local/lualib/wiola/?.lua;/usr/local/lualib/lua-MessagePack/?.lua;;';

# Configure a vhost
server {
   # example location
   location /ws/ {
      lua_socket_log_errors off;
      lua_check_client_abort on;

      # Set a handler for connection
      content_by_lua_file $document_root/lua/wiola/handler.lua;
      # This is needed to set additional websocket protocol headers
      header_filter_by_lua_file $document_root/lua/wiola/headers.lua;
   }

}
```

Actually, you do not need to do anything. Just take any WAMP client and make a connection.

[Back to TOC](#table-of-contents)

Methods
========

addConnection(sid, wampProto)
------------------------------------------

TBD

[Back to TOC](#table-of-contents)

removeConnection(regId)
---------------

TBD

[Back to TOC](#table-of-contents)

receiveData(regId, data)
---------------

TBD

[Back to TOC](#table-of-contents)

getPendingData(regId)
---------------------------

TBD

[Back to TOC](#table-of-contents)

Copyright and License
=====================

Wiola library is licensed under the BSD 2-Clause license.

Copyright (c) 2014, Konstantin Burkalev
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)

See Also
========

* [WAMP specification](http://wamp.ws)
* [Wampy.js](https://github.com/KSDaemon/wampy.js). WAMP Javascript client-side implementation.
* [OpenResty](http://openresty.org)
* [lua-nginx-module](https://github.com/chaoslawful/lua-nginx-module)
* [lua-resty-websocket](https://github.com/agentzh/lua-resty-websocket)
* [lua-resty-redis](https://github.com/agentzh/lua-resty-redis)
* [Redis key-value store](http://redis.io)
* [lua-MessagePack](http://fperrad.github.io/lua-MessagePack/)

[Back to TOC](#table-of-contents)
