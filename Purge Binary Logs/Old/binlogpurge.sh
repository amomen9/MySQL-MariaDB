#!/bin/bash
# Written to purge primary's binary log files safely in a MySQL cluster
# Author: Ali Momen
# mailto:amomen@gmail.com

set -x
exec > >(logger -i -p local1.info) 2>&1

#purge mode: (SLAVE_IO or SLAVE_SQL)
PURGE_MODE="$1"

#IPs:
PRIMARY_IP='192.168.241.181' 	#arbitrary    
STANDBY1_IP='192.168.241.185'
MASTER2_IP='192.168.241.182'
MASTER3_IP='192.168.241.183'

#Ports:
PRIMARY_PORT=3306
STANDBY1_PORT=3306
MASTER2_PORT=3306
MASTER3_PORT=3306

#Users:
PRIMARY_USER=root
STANDBY1_USER=root
MASTER2_USER=root
MASTER3_USER=root


#Passes:
PRIMARY_PASS=1
STANDBY1_PASS=1
MASTER2_PASS=1
MASTER3_PASS=1

#Primary's binlog dir:

BINLOG_DIR=/var/log/mysql
BINLOG_BASE_NAME='master-bin'

#
COUNT=3
##Begin#####################################################

##PRIMARY/STANDBY:
CURRENT_LOG=$(mysql -u$STANDBY1_USER -p$STANDBY1_PASS -h$STANDBY1_IP -P$STANDBY1_PORT -e "show slave status\G" | grep Relay_Master_Log_File | awk '{print $2}')
CURRENT_LOG_S=$(mysql -u$STANDBY1_USER -p$STANDBY1_PASS -h$STANDBY1_IP -P$STANDBY1_PORT -e "show master status\G" | grep File | awk '{print $2}')
if [ $? -ne 0 ];
then
    logger -i -p local1.error unable to connect to the standby with the connection parameters specified. Master and Standby not purged. Time $(date)
	let COUNT-=1
else

	TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
	TIMESTAMP=${TIMESTAMP// /\\ }
	
	mkdir -p /backup/binlog_archive/$TIMESTAMP/
	
	if [ ! -z $(find $BINLOG_DIR -name "$BINLOG_BASE_NAME*" ! -newer "$BINLOG_DIR/$CURRENT_LOG" ! -name "$CURRENT_LOG" -print0) ];
	then
		find $BINLOG_DIR -name "$BINLOG_BASE_NAME*" ! -newer "$BINLOG_DIR/$CURRENT_LOG" ! -name "$CURRENT_LOG" -print0 | tar -cavf /backup/binlog_archive/$TIMESTAMP/$TIMESTAMP.tar.gz --null -T -
		
		if [ $? -eq 0 ];
		then
			mysql -u$PRIMARY_USER -p$PRIMARY_PASS -P$PRIMARY_PORT -e "purge binary logs to '$CURRENT_LOG';"
			mysql -u$STANDBY1_USER -p$STANDBY1_PASS -h$STANDBY1_IP -P$STANDBY1_PORT -e "purge binary logs to '$CURRENT_LOG_S';"
			logger -i -p local1.info logs purged on Primary to $CURRENT_LOG and its Slave successfuly on $(date)!
		else
			logger -i -p local1.error something went wrong trying to backup binary logs. The logs will not be purged. Time $(date)
		fi
	fi
fi

##MASTER2:
CURRENT_LOG_2=$(mysql -u$MASTER2_USER -p$MASTER2_PASS -h$MASTER2_IP -P$MASTER2_PORT -e "show master status\G" | grep File | awk '{print $2}')
if [ $? -ne 0 ];
then
    logger -i -p local1.error unable to connect to $MASTER2_IP. Its logs not purged. Time $(date)
	let COUNT-=1
else
	mysql -u$MASTER2_USER -p$MASTER2_PASS -h$MASTER2_IP -P$MASTER2_PORT -e "purge binary logs to '$CURRENT_LOG_2';"
	logger -i -p local1.info logs purged on Secondory Master $MASTER2_IP successfuly! Time $(date)
fi

##MASTER3:
CURRENT_LOG_3=$(mysql -u$MASTER3_USER -p$MASTER3_PASS -h$MASTER3_IP -P$MASTER3_PORT -e "show master status\G" | grep File | awk '{print $2}')
if [ $? -ne 0 ];
then
    logger -i -p local1.error unable to connect to $MASTER3_IP. Its logs not purged. Time $(date)
	let COUNT-=1
else
	mysql -u$MASTER3_USER -p$MASTER3_PASS -h$MASTER3_IP -P$MASTER3_PORT -e "purge binary logs to '$CURRENT_LOG_3';"
	logger -i -p local1.info logs purged on Secondory Master $MASTER3_IP successfuly! Time $(date)
fi


logger -i -p local1.info Script execution completed on $(date). $COUNT operations completed successfully.


exit 0


