# Set up GTID replication with a read-only slave (MariaDB)

This instruction set follows the original notes: configure GTID, take a physical backup from the master using `mariabackup`, restore it on the slave, then start replication using `master_use_gtid=slave_pos`.

---

## Prerequisites

- Network connectivity from slave to master on TCP/3306.
- `mariabackup` installed on the master (and typically on the slave for prepare/decompress).
- A replication user with enough privileges for backup + replication.
- You already decided/created:
  - `MASTER_HOST` (e.g., `192.168.241.181`)
  - `SLAVE_HOST` (e.g., `192.168.241.185`)
  - `DATADIR` (e.g., `/data/mysql/mysql`)

---

## 1) Create backup directories

On the master:

```bash
mkdir -p /data/mysql/backups/full-backup1/
chown -R mysql:mysql /data/mysql
```

On the slave:

```bash
mkdir -p /data/mysql/backups_slave/rep/full-backup1/
```

---

## 2) Configure GTID on the master

In the master server config (often `/etc/my.cnf.d/server.cnf`), under the server section (commonly `[mysqld]`):

```ini
[mysqld]
log-bin=/data/mysql/mysql/MyDB/log-bin
server_id=1
log-basename=master1
binlog-format=mixed

gtid_strict_mode=1
# Optional convention from the original sheet:
# gtid_domain_id=<last character in hostname>
```

Restart MariaDB on the master after changes.

---

## 3) Configure GTID + read-only on the slave

```ini
[mysqld]
server_id=2

gtid_strict_mode=1
read_only=1
# Optional convention from the original sheet:
# gtid_domain_id=<last character in hostname>
```

Restart MariaDB on the slave after changes.

---

## 4) Create replication and admin users on the master

Create a replication user (backup needs `RELOAD` and `PROCESS` per the original notes):

```sql
CREATE USER 'repl'@'%' IDENTIFIED BY 'REPLACE_ME_PASSWORD';
GRANT RELOAD, PROCESS, SUPER, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;
```

If you want to change a user’s host after creation (original note):

```sql
RENAME USER 'super'@'localhost' TO 'super'@'%';
```

Expanded listing (handy while troubleshooting):

```sql
SELECT user, host FROM mysql.user\G
```

---

## 5) Install `qpress` (if your backup is compressed)

On both master and slave:

```bash
yum install https://repo.percona.com/yum/percona-release-latest.noarch.rpm -y
yum install qpress -y
```

---

## 6) Take a full backup on the master

```bash
mariabackup --defaults-file=/etc/my.cnf \
  --backup \
  --compress \
  --parallel=4 \
  --target-dir=/data/mysql/backups/full-backup1 \
  --user=repl \
  --password='REPLACE_ME_PASSWORD'
```

---

## 7) Copy the backup to the slave

From the master:

```bash
scp -rp /data/mysql/backups/full-backup1 \
  root@192.168.241.185:/data/mysql/backups_slave/rep/full-backup1

# Alternatively:
# rsync -a /data/mysql/backups/full-backup1/ root@192.168.241.185:/data/mysql/backups_slave/rep/full-backup1/
```

---

## 8) Restore on the slave

1) Decompress and prepare the backup:

```bash
mariabackup --decompress --parallel=4 --remove-original \
  --target-dir=/data/mysql/backups_slave/rep/full-backup1

mariabackup --prepare \
  --target-dir=/data/mysql/backups_slave/rep/full-backup1
```

2) Stop MariaDB:

```bash
systemctl stop mariadb
```

3) Remove old data files from the data directory.

> Be careful: this deletes the slave’s current datadir contents.

```bash
rm -rf /data/mysql/mysql/*
```

4) Ensure any leftover `.qp` files are removed (original step):

```bash
cd /data/mysql/backups_slave/rep/full-backup1
find . -type f -name "*.qp" -exec rm -v {} \;
```

5) Move restored files into place.

> The original notes moved into `/data/mysql/`. Ensure this matches your configured `datadir`.
> If your `datadir` is `/data/mysql/mysql`, copy the *contents* there.

```bash
mv /data/mysql/backups_slave/rep/full-backup1/* /data/mysql/mysql/
rm -rf /data/mysql/backups_slave/rep/*
chown -R mysql:mysql /data/mysql
```

6) Start MariaDB:

```bash
systemctl start mariadb
```

---

## 9) Capture the GTID position

You must set the slave to the GTID position of the backup.
Use one of these approaches:

### A) Query from the master

```bash
mysql -uroot -p -e "SELECT @@GLOBAL.gtid_binlog_pos;"
mysql -uroot -p -e "SELECT @@GLOBAL.gtid_current_pos;"
```

### B) Read from the backup metadata on the slave

```bash
cat /data/mysql/mysql/xtrabackup_info | grep -i GTID
```

Example from the original notes:

```text
binlog_pos = filename 'master1-bin.000003', position '344', GTID of the last change '0-1-1'
```

---

## 10) Configure replication on the slave

In the MariaDB client on the slave:

```sql
STOP SLAVE;
RESET SLAVE;
RESET SLAVE ALL;
RESET MASTER;

-- Set this from the GTID you captured (do not hardcode blindly)
SET GLOBAL gtid_slave_pos='REPLACE_ME_GTID';

CHANGE MASTER TO
  master_host='192.168.241.181',
  master_port=3306,
  master_user='repl',
  master_password='REPLACE_ME_PASSWORD',
  master_connect_retry=10,
  master_use_gtid=slave_pos;

-- Make the slave read-only (original intent)
SET GLOBAL read_only=ON;

START SLAVE;
```

Check status:

```sql
SHOW SLAVE STATUS\G
SHOW VARIABLES WHERE variable_name = 'read_only';
```
