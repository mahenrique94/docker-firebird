#!/bin/bash
/etc/init.d/xinetd start
$FIREBIRD_PATH/bin/gsec -user SYSDBA -password $FIREBIRD_DB_PASSWORD_DEFAULT -modify SYSDBA -pw $FIREBIRD_DB_PASSWORD
while :
do
	echo "[`date`] --> Firebird running..."
done
