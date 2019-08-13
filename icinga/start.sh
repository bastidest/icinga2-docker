#!/bin/bash

set -e
set -x

/etc/init.d/apache2 start

ICINGAWEB2_API_PASSWORD=$(openssl rand -base64 16)

if [ ! -f /usr/local/icinga2/var/lib/icinga2/ca/ca.crt ] ; then
  echo "setting up icinga API"
  /usr/local/icinga2/sbin/icinga2 api setup
fi

if test ! grep -Fxq 'object ApiUser "icingaweb2"' /usr/local/icinga2/etc/icinga2/conf.d/api-users.conf ; then
  echo "creating api user for icingaweb"
  cat /usr/local/icinga2/etc/icinga2/conf.d/api-users.conf
  cat >> /usr/local/icinga2/etc/icinga2/conf.d/api-users.conf <<EOF

object ApiUser "icingaweb2" {
  password = "changethispassword"
  permissions = [ "status/query", "actions/*", "objects/modify/*", "objects/query/*" ]
}
EOF
  sed -i "s|changethispassword|${ICINGAWEB2_API_PASSWORD}|g" /usr/local/icinga2/etc/icinga2/conf.d/api-users.conf
else
  echo "copy password from icinga to icingaweb"
fi

if [ ! -f /usr/local/icinga2/etc/icingaweb2/resources.ini ] ; then
  echo "copy configuration templates for icingaweb2"
  cp /template/icingaweb2-etc/* /usr/local/icinga2/etc/icingaweb2/
  sed -i "s|xxxICINGAWEBDBNAMExxx|${MYSQL_WEB_DATABASE}|g" /usr/local/icinga2/etc/icingaweb2/resources.ini
  sed -i "s|xxxICINGAWEBUSERxxx|${MYSQL_WEB_USER}|g" /usr/local/icinga2/etc/icingaweb2/resources.ini
  sed -i "s|xxxICINGAWEBPASSWORDxxx|${MYSQL_WEB_PASSWORD}|g" /usr/local/icinga2/etc/icingaweb2/resources.ini
  sed -i "s|xxxICINGADBNAMExxx|${MYSQL_DATABASE}|g" /usr/local/icinga2/etc/icingaweb2/resources.ini
  sed -i "s|xxxICINGAUSERxxx|${MYSQL_USER}|g" /usr/local/icinga2/etc/icingaweb2/resources.ini
  sed -i "s|xxxICINGAPASSWORDxxx|${MYSQL_PASSWORD}|g" /usr/local/icinga2/etc/icingaweb2/resources.ini
fi

chown -R www-data:icingaweb2 /usr/local/icinga2/etc/icingaweb2

ICINGAADMIN_PASSWORD_HASH=$(php -r "echo password_hash(\"${ICINGAADMIN_PASSWORD}\", PASSWORD_DEFAULT);")

echo "waiting for login to be possible"
until mysql -hmysql -u${MYSQL_WEB_USER} -p${MYSQL_WEB_PASSWORD} -e "" 2>/dev/null; do
  sleep 1
done
mysql -hmysql -u${MYSQL_WEB_USER} -p${MYSQL_WEB_PASSWORD} "$MYSQL_WEB_DATABASE" -e "insert into icingaweb_group(name, ctime) values ('Administrators', NOW()); insert into icingaweb_user(name, active, password_hash, ctime) values ('icingaadmin', 1, '$ICINGAADMIN_PASSWORD_HASH', NOW()); insert into icingaweb_group_membership(group_id, username, ctime) values ((select id from icingaweb_group where name = 'Administrators'), 'icingaadmin', NOW());"

echo "starting icinga daemon"
/usr/local/icinga2/sbin/icinga2 daemon
