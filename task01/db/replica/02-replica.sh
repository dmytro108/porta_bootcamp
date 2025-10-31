#!/bin/bash

SQL=$(cat <<EOF
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='${DB_MASTER_HOST}',
  SOURCE_USER='${REPLICA_USER}',
  SOURCE_PASSWORD='${REPLICA_PASSWORD}',
  SOURCE_AUTO_POSITION=1;
START REPLICA;
SHOW REPLICA STATUS\G
EOF
)

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "$SQL"

if [[ $? -eq 0 ]]; then
  echo "User '$REPLICA_USER' created."
else
  echo "Error. User '$REPLICA_USER' not created."
  exit 2
fi
