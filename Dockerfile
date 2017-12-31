FROM xataz/alpine:3.7

LABEL description="A server software for creating file hosting services" \
      tags="latest 12.0.4 12.0 12" \
      maintainer="xataz <https://github.com/xataz" \
      build_ver="2017123101"

ARG NEXTCLOUD_VER=12.0.4

ENV UID=991 \
    GID=991 \
    UPLOAD_MAX_SIZE=10G \
    APC_SHM_SIZE=128M \
    OPCACHE_MEM_SIZE=128 \
    MEMORY_LIMIT=512M \
    CRON_PERIOD=15m \
    CRON_MEMORY_LIMIT=1g \
    TZ=Etc/UTC \
    DB_TYPE=sqlite3 \
    DOMAIN=localhost

RUN BUILD_DEPS="gnupg \
                tar \
                build-base \
                autoconf \
                automake \
                pcre-dev \
                libtool \
                samba-dev \
                git \
                php7-dev" \
    && apk add --no-cache \
                libressl \
                ca-certificates \
                libsmbclient \
                tzdata \
                nginx \
                php7 \
                php7-fpm \
                php7-apcu \
                php7-ctype \
                php7-curl \
                php7-dom \
                php7-fileinfo \
                php7-gd \
                php7-iconv \
                php7-json \
                php7-mbstring \
                php7-mysqli \
                php7-opcache \
                php7-openssl \
                php7-pdo \
                php7-pdo_mysql \
                php7-pdo_pgsql \
                php7-pdo_sqlite \
                php7-pgsql \
                php7-posix \
                php7-redis \
                php7-session \
                php7-simplexml \
                php7-sqlite3 \
                php7-xml \
                php7-xmlreader \
                php7-xmlwriter \
                php7-zip \
                php7-zlib \
                su-exec \
                s6 \
                ${BUILD_DEPS} \
    ## Install libsmbclient-php
    && git clone git://github.com/eduardok/libsmbclient-php.git /tmp/libsmbclient-php \
    && cd /tmp/libsmbclient-php \
    && phpize \
    && ./configure \
    && make \
    && make install \
    && echo "extension=smbclient.so" > /etc/php7/conf.d/21_smbclient.ini \
    ## Install Nextcloud
    && git clone -b v${NEXTCLOUD_VER} https://github.com/nextcloud/server /app/nextcloud \
    && cd /app/nextcloud \
    && git submodule update --init \
    ## Cleanup
    && apk del --no-cache ${BUILD_DEPS} \
    && rm -rf /var/cache/apk/* /tmp/* /root/.gnupg /app/nextcloud/.git

COPY rootfs /
RUN chmod +x /usr/local/bin/* /etc/s6.d/*/* /etc/s6.d/.s6-svscan/*

VOLUME /data /config /apps2 /nextcloud/themes
EXPOSE 8888

CMD ["/usr/local/bin/startup"]
