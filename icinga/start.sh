#!/bin/bash

set -e
set -x

function get_icingaweb2_api_password() {
  ICINGAWEB2_API_PASSWORD=$(awk '
        BEGIN {
                username = "none"
        }

        /object ApiUser *"(.+)"/ {
                username = $3
        }

        /password *= *"(.+)"/ {
                if(username == "\"icingaweb2\"") {
                        gsub("\"", "", $3)
                        print $3
                        exit
                }
        }
  ' /usr/local/icinga2/etc/icinga2/conf.d/api-users.conf)
}

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
  password = "xxxICINGAWEBAPIPASSWORDxxx"
  permissions = [ "status/query", "actions/*", "objects/modify/*", "objects/query/*" ]
}
EOF
  sed -i "s|xxxICINGAWEBAPIPASSWORDxxx|${ICINGAWEB2_API_PASSWORD}|g" /usr/local/icinga2/etc/icinga2/conf.d/api-users.conf
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

echo "waiting for login to be possible"
until mysql -hmysql -u${MYSQL_WEB_USER} -p${MYSQL_WEB_PASSWORD} -e "" 2>/dev/null; do
  sleep 1
done

ROW_COUNT=$(mysql -Ns -hmysql -u${MYSQL_WEB_USER} -p${MYSQL_WEB_PASSWORD} "$MYSQL_WEB_DATABASE" -e 'select count(*) from icingaweb_group')
if [[ "$ROW_COUNT" -eq "0" ]] ; then
  echo "generating icingaadmin login database"
  ICINGAADMIN_PASSWORD_HASH=$(php -r "echo password_hash(\"${ICINGAADMIN_PASSWORD}\", PASSWORD_DEFAULT);")
  mysql -hmysql -u${MYSQL_WEB_USER} -p${MYSQL_WEB_PASSWORD} "$MYSQL_WEB_DATABASE" -e "insert into icingaweb_group(name, ctime) values ('Administrators', NOW()); insert into icingaweb_user(name, active, password_hash, ctime) values ('icingaadmin', 1, '$ICINGAADMIN_PASSWORD_HASH', NOW()); insert into icingaweb_group_membership(group_id, username, ctime) values ((select id from icingaweb_group where name = 'Administrators'), 'icingaadmin', NOW());"
fi

MONITORING_PATH="/usr/local/icinga2/etc/icingaweb2/enabledModules/monitoring"
if [[ ! -d "$MONITORING_PATH" ]] ; then
  echo "enabling module monitoring"
  mkdir /usr/local/icinga2/etc/icingaweb2/enabledModules
  ln -s /build/icingaweb2/modules/monitoring "$MONITORING_PATH"
  chown -R www-data:icingaweb2 /usr/local/icinga2/etc/icingaweb2/enabledModules

  cp /template/icingaweb2-monitoring/* "$MONITORING_PATH/"
  get_icingaweb2_api_password
  sed -i "s|xxxICINGAWEBAPIPASSWORDxxx|${ICINGAWEB2_API_PASSWORD}|g" "$MONITORING_PATH/commandtransports.ini"

  # move this file to this weird location for whatever reason
  mkdir -p /usr/local/icinga2/etc/icingaweb2/modules/monitoring
  mv "$MONITORING_PATH/backends.ini" /usr/local/icinga2/etc/icingaweb2/modules/monitoring/
  chown -R www-data:icingaweb2 /usr/local/icinga2/etc/icingaweb2/modules
fi

echo "starting apache"
/etc/init.d/apache2 start
echo "starting icinga daemon"
/usr/local/icinga2/sbin/icinga2 daemon

set +x
while pgrep icinga >/dev/null ; do
  sleep 5
done
