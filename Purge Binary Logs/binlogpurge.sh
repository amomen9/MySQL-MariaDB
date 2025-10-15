#!/bin/bash
# Binary log purge & archive workflow for multi-node MySQL replication topology.
# Author: Ali Momen  |  Email: amomen@gmail.com
# Steps:
#   1. Discover current relay/master positions.
#   2. Tar+compress obsolete binlogs (older than active relay/master file) to dated archive.
#   3. PURGE BINARY LOGS up to safe file on each node.
#   4. Log success/fail events via syslog (local1 facility).

set -x

# Syslog redirection (stdout & stderr)
exec > >(logger -i -p local1.info) 2>&1

# Optional mode flag (retained for compatibility; not used directly)
PURGE_MODE="$1"

######################### Topology & Credentials (anonymized) #########################
# Replace CHANGE_ME_* passwords with secure secrets (env vars recommended).
PRIMARY_IP='10.50.0.11'
STANDBY1_IP='10.50.0.12'
MASTER2_IP='10.50.0.13'
MASTER3_IP='10.50.0.14'

PRIMARY_PORT=3306
STANDBY1_PORT=3306
MASTER2_PORT=3306
MASTER3_PORT=3306

PRIMARY_USER=root
STANDBY1_USER=root
MASTER2_USER=root
MASTER3_USER=root

PRIMARY_PASS='CHANGE_ME_PRIMARY'
STANDBY1_PASS='CHANGE_ME_STANDBY1'
MASTER2_PASS='CHANGE_ME_MASTER2'
MASTER3_PASS='CHANGE_ME_MASTER3'
#######################################################################################

# Binary log source directory & naming pattern (primary node)
BINLOG_DIR=/var/log/mysql
BINLOG_BASE_NAME='master-bin'

# Success counter
COUNT=3

# --- Helper: run mysql with minimal noise ---
mysql_exec () {
  local user=$1 pass=$2 host=$3 port=$4 query=$5
  mysql -u"${user}" -p"${pass}" -h"${host}" -P"${port}" -e "${query}"
}

# --- PRIMARY / STANDBY SECTION ---
CURRENT_LOG=$(mysql_exec "$STANDBY1_USER" "$STANDBY1_PASS" "$STANDBY1_IP" "$STANDBY1_PORT" "SHOW SLAVE STATUS\G" | grep Relay_Master_Log_File | awk '{print $2}')
CURRENT_LOG_S=$(mysql_exec "$STANDBY1_USER" "$STANDBY1_PASS" "$STANDBY1_IP" "$STANDBY1_PORT" "SHOW MASTER STATUS\G" | grep File | awk '{print $2}')

if [ $? -ne 0 ]; then
  logger -i -p local1.error "Unable to connect to standby. Primary & standby not purged. Time $(date)"
  let COUNT-=1
else
  TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
  ARCHIVE_DIR="/backup/binlog_archive/${TIMESTAMP}"
  mkdir -p "${ARCHIVE_DIR}"

  # If there are obsolete logs (older than CURRENT_LOG) archive them
  if [ ! -z "$(find "$BINLOG_DIR" -name "${BINLOG_BASE_NAME}*" ! -newer "$BINLOG_DIR/$CURRENT_LOG" ! -name "$CURRENT_LOG" -print -quit)" ]; then
    find "$BINLOG_DIR" -name "${BINLOG_BASE_NAME}*" ! -newer "$BINLOG_DIR/$CURRENT_LOG" ! -name "$CURRENT_LOG" -print0 \
      | tar -cavf "${ARCHIVE_DIR}/${TIMESTAMP}.tar.gz" --null -T -
    if [ $? -eq 0 ]; then
      mysql_exec "$PRIMARY_USER" "$PRIMARY_PASS" "127.0.0.1" "$PRIMARY_PORT" "PURGE BINARY LOGS TO '$CURRENT_LOG';"
      mysql_exec "$STANDBY1_USER" "$STANDBY1_PASS" "$STANDBY1_IP" "$STANDBY1_PORT" "PURGE BINARY LOGS TO '$CURRENT_LOG_S';"
      logger -i -p local1.info "Logs purged on Primary to $CURRENT_LOG and Standby to $CURRENT_LOG_S successfully on $(date)"
    else
      logger -i -p local1.error "Archive failure; logs NOT purged. Time $(date)"
    fi
  fi
fi

# --- MASTER2 ---
CURRENT_LOG_2=$(mysql_exec "$MASTER2_USER" "$MASTER2_PASS" "$MASTER2_IP" "$MASTER2_PORT" "SHOW MASTER STATUS\G" | grep File | awk '{print $2}')
if [ $? -ne 0 ]; then
  logger -i -p local1.error "Unable to connect to $MASTER2_IP. Logs not purged. Time $(date)"
  let COUNT-=1
else
  mysql_exec "$MASTER2_USER" "$MASTER2_PASS" "$MASTER2_IP" "$MASTER2_PORT" "PURGE BINARY LOGS TO '$CURRENT_LOG_2';"
  logger -i -p local1.info "Logs purged on secondary master $MASTER2_IP successfully. Time $(date)"
fi

# --- MASTER3 ---
CURRENT_LOG_3=$(mysql_exec "$MASTER3_USER" "$MASTER3_PASS" "$MASTER3_IP" "$MASTER3_PORT" "SHOW MASTER STATUS\G" | grep File | awk '{print $2}')
if [ $? -ne 0 ]; then
  logger -i -p local1.error "Unable to connect to $MASTER3_IP. Logs not purged. Time $(date)"
  let COUNT-=1
else
  mysql_exec "$MASTER3_USER" "$MASTER3_PASS" "$MASTER3_IP" "$MASTER3_PORT" "PURGE BINARY LOGS TO '$CURRENT_LOG_3';"
  logger -i -p local1.info "Logs purged on secondary master $MASTER3_IP successfully. Time $(date)"
fi

logger -i -p local1.info "Script execution completed on $(date). $COUNT operations completed successfully."
exit 0