#!/bin/bash

set -e
set -x

function importSchema() {
  echo "importing schema..."
  mysql icinga < /app/icinga2-schema.sql
  mysql -e "CREATE DATABASE ${MYSQL_WEB_DATABASE}; CREATE USER '${MYSQL_WEB_USER}'@'%' IDENTIFIED BY '${MYSQL_WEB_PASSWORD}'; GRANT ALL ON ${MYSQL_WEB_DATABASE}.* TO '${MYSQL_WEB_USER}'@'%';"
  mysql "${MYSQL_WEB_DATABASE}" < /app/icingaweb2-schema.sql
  echo "import successful"
}

/entrypoint.sh mysqld --default-authentication-plugin=mysql_native_password &
MYSQL_PID=$!

echo "waiting for database"
until mysqladmin ping >/dev/null 2>&1; do
  sleep 3
done
echo "database online"

cat > ~/.my.cnf <<EOF
[client]
user=root
password="${MYSQL_ROOT_PASSWORD}"
EOF

echo "waiting for login to be possible"
until mysql -e "" 2>/dev/null; do
  sleep 3
done

sleep 5

echo "checking for existing schema"
sql_response=$(mysql icinga -sse "show tables where Tables_in_icinga = 'icinga_endpoints';")
if [ "$?" -eq "0" ] && [ ! -z $sql_response ] ; then
  echo "table exists, skipping setup"
else
  importSchema
fi

echo "signal that database is ready"
/app/nc -kl 6969 > /dev/null &

wait $MYSQL_PID
