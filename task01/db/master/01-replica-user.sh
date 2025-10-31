#!/bin/bash

SQL=$(cat <<EOF
CREATE USER '${REPLICA_USER}'@'%' IDENTIFIED BY '${REPLICA_PASSWORD}';
GRANT REPLICATION SLAVE ON *.* TO '${REPLICA_USER}'@'%';
FLUSH PRIVILEGES;
ALTER USER '${REPLICA_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPLICA_PASSWORD}';
FLUSH PRIVILEGES;
EOF
)

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "$SQL"

if [[ $? -eq 0 ]]; then
  echo "User '$REPLICA_USER' created."
else
  echo "Error. User '$REPLICA_USER' not created."
  exit 2
fi