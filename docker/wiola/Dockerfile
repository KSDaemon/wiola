FROM openresty/openresty:alpine-fat

LABEL maintainer='Konstantin Burkalev <KSDaemon@ya.ru>'

RUN apk add --no-cache --virtual .build-deps \
            make \
            curl \
            gd-dev \
            geoip-dev \
            libxslt-dev \
            perl-dev \
            readline-dev \
            zlib-dev \
            git \
            cmake \
            openssl-dev \
            build-base \
            curl \
            gd \
            geoip \
            libgcc \
            libxslt \
            linux-headers \
            make \
            perl \
            unzip \
            zlib

RUN opm install ledgetech/lua-resty-http KSDaemon/wiola
RUN luarocks install rapidjson
RUN luarocks install lua-messagepack
RUN luarocks install redis-lua

ADD config.nginx /usr/local/openresty/nginx/conf/nginx.conf
ADD startup.sh /usr/local/wiola/startup

ENTRYPOINT ["/usr/local/wiola/startup"]
