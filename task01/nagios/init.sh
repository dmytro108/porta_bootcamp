#!/bin/sh

set -eu

#echo "\$USER\$=${}" >> ${NAGIOS_VARS_FILE}
NAGIOS_VARS_FILE="/home/nagios/vars"
NAGIOS_RESOURCES="/opt/nagios/etc/resource.cfg"

if [ ! -f ${NAGIOS_VARS_FILE} ]; then
  echo "" > /home/nagios/vars
  echo "\$USER10\$=${DB_MASTER_HOST}" >> ${NAGIOS_VARS_FILE}
  echo "\$USER20\$=${DB_SLAVE_HOST}" >> ${NAGIOS_VARS_FILE}
  echo "\$USER30\$=${APP_HOST}" >> ${NAGIOS_VARS_FILE}
  echo "\$USER11\$=${DB_USER}" >> ${NAGIOS_VARS_FILE}
  echo "\$USER12\$=${DB_PASSWORD}" >> ${NAGIOS_VARS_FILE}
  cat ${NAGIOS_VARS_FILE} >> ${NAGIOS_RESOURCES}
fi

/usr/local/bin/start_nagios