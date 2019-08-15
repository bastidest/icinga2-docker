FROM debian:buster

ARG GIT_REF_ICINGA2=master
ARG GIT_REF_ICINGAWEB2=master
ARG GIT_REF_ICINGAWEB2_GRAPHITE=master

WORKDIR /build

RUN apt-get update\
  && apt-get -y install\
  apt-transport-https\
  wget\
  gnupg\
  git\
  cmake\
  g++\
  build-essential\
  libssl-dev\
  libboost-all-dev\
  bison\
  flex\
  default-libmysqlclient-dev\
  default-mysql-client\
  libpq-dev\
  apache2\
  php7.3 php7.3-cli php7.3-curl php-php-gettext php7.3-intl php7.3-mbstring php7.3-xml php7.3-ldap php7.3-gd php-imagick php7.3-mysql php7.3-pgsql\
  monitoring-plugins

RUN git clone --depth 1 --branch ${GIT_REF_ICINGA2} https://github.com/Icinga/icinga2.git icinga2
RUN mkdir icinga2/release\
  && cd icinga2/release\
  && cmake .. -DCMAKE_BUILD_TYPE=Release -DICINGA2_UNITY_BUILD=OFF -DCMAKE_INSTALL_PREFIX=/usr/local/icinga2 -DICINGA2_PLUGINDIR=/usr/lib/nagios/plugins\
  && make -j4

RUN git clone --depth 1 --branch ${GIT_REF_ICINGAWEB2} https://github.com/Icinga/icingaweb2.git icingaweb2

RUN git clone --depth 1 --branch ${GIT_REF_ICINGAWEB2_GRAPHITE} https://github.com/Icinga/icingaweb2-module-graphite.git ./icingaweb2/modules/graphite

RUN groupadd icinga\
  && groupadd icingacmd\
  && useradd -c "icinga" -s /sbin/nologin -G icingacmd -g icinga icinga

RUN cd icinga2/release && make install\
  && chown -R icinga:icingacmd\
    /usr/local/icinga2/var/cache\
    /usr/local/icinga2/var/log\
    /usr/local/icinga2/var/run\
    /usr/local/icinga2/var/lib\
  && mkdir /template\
  && mv /usr/local/icinga2/etc/icinga2 /template/

RUN groupadd -r icingaweb2\
  && usermod -a -G icingaweb2 www-data\
  && /build/icingaweb2/bin/icingacli setup config directory --config=/usr/local/icingaweb2/etc\
  && /build/icingaweb2/bin/icingacli setup config webserver apache --path=/ --root=/build/icingaweb2/public/ --config=/usr/local/icingaweb2/etc --file=/etc/apache2/sites-enabled/icingaweb2.conf\
  && a2enmod rewrite

COPY ./icingaweb2/ /template/icingaweb2/
# /build/icingaweb2/bin/icingacli setup token create --config=/usr/local/icingaweb2/etc

WORKDIR /app

COPY ./icinga/start.sh /app/start.sh

CMD [ "/app/start.sh" ]
