### MySQL master and slave servers settings
echo DB_MASTER_HOST=db_master
echo DB_MASTER_ROOT_PASSW=$(openssl rand -base64 32 | tr -cd "a-zA-Z0-9" | cut -c5-17)

echo DB_SLAVE_HOST=db_slave
echo DB_SLAVE_ROOT_PASSW=$(openssl rand -base64 32 | tr -cd "a-zA-Z0-9" | cut -c5-17)

echo DB_ADM_HOST=db_adm

### DB replication user credential
echo DB_REPLICA_USER=replic
echo DB_REPLICA_PASSW=$(openssl rand -base64 32 | tr -cd "a-zA-Z0-9" | cut -c5-17)

### App DB connection settings
echo DB_NAME=task01
echo DB_USER=app_user
echo DB_PASSW=$(openssl rand -base64 32 | tr -cd "a-zA-Z0-9" | cut -c5-17)

### WebApp
echo APP_HOST=apache
echo APP_PORT=80
echo APP_PORT_SSL=443

### Monitoring Nagios
echo NAGIOS_ADMIN=admin
echo NAGIOS_PASSW=$(openssl rand -base64 32 | tr -cd "a-zA-Z0-9" | cut -c5-17)
echo TIMEZONE=Europe/London
echo NAGIOS_PORT=9090