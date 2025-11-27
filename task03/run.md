sudo docker exec -ti  db_master  bash -c 'mysql -u root -p${MYSQL_ROOT_PASSWORD} < /home/db-schema.sql'

