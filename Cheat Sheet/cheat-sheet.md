# MySQL / MariaDB Cheat Sheet

Quick, topic-grouped reference commands and examples.

## Quick links (instruction sets)

- [MariaDB installation & initial hardening](../Instruction%20Sets/mariadb_installation_and_initial_hardening_instructions.md)
- [GTID replication (read-only slave) using `mariabackup`](../Instruction%20Sets/gtid_replication_readonly_slave_instructions.md)
- [Create a database + application user](../Instruction%20Sets/create_database_and_user_instructions.md)

---

## Package install & service control (RHEL/CentOS)

```bash
sudo yum search mariadb
sudo yum info mariadb
sudo yum install mariadb-server

sudo systemctl enable mariadb.service
sudo systemctl start mariadb.service
sudo systemctl status mariadb.service
```

Run the interactive hardening wizard:

```bash
sudo mysql_secure_installation
```

---

## `mysql` client essentials

Run an inline SQL snippet:

```bash
mysql -u root -p -e "SELECT VERSION();"
```

Execute a SQL script file into an existing database:

```bash
mysql -u root -p my_database < file.sql
```

From inside the `mysql` prompt, load a script:

```sql
SOURCE /root/data/mysqlsampledatabase.sql;
```

---

## Database & user administration

Create a database:

```sql
CREATE DATABASE MyDB;
```

Create a user and prevent password expiry (MariaDB 10.4.3+):

```sql
CREATE OR REPLACE USER 'a.momen' IDENTIFIED BY 'REPLACE_ME_PASSWORD';
ALTER USER 'a.momen' PASSWORD EXPIRE NEVER;
```

Drop anonymous users (common hardening step):

```sql
DROP USER ''@'localhost';
-- Also remove the per-host anonymous user if it exists:
-- DROP USER ''@'<hostname>';  -- replace <hostname> with the server hostname
```

Grant privileges (example):

```sql
GRANT ALL PRIVILEGES ON database_name.table_name TO 'a.momen'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

List users that can connect remotely:

```sql
SELECT User, Host
FROM mysql.user
WHERE Host <> 'localhost';
```

---

## Password / authentication notes

Some older syntax is deprecated in modern MySQL/MariaDB.
Prefer `ALTER USER` over `SET PASSWORD`.

Force `root` to require a password and (if needed) switch to `mysql_native_password` (version/plugin dependent):

```sql
-- Use the simplest form supported by your MariaDB version:
ALTER USER 'root'@'localhost' IDENTIFIED BY 'REPLACE_ME_STRONG_PASSWORD';

-- If you must explicitly select a plugin (only if your server supports it):
-- ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('REPLACE_ME_STRONG_PASSWORD');
```

---

## Configuration discovery & common variables

Show server variables:

```sql
SHOW VARIABLES;
```

Find current `datadir`:

```sql
SELECT @@datadir;
```

Inspect which files `mysqld` reads (help output includes default config locations):

```bash
mysql --verbose --help
```

Get host-related variables:

```sql
SELECT @@hostname;
SHOW VARIABLES WHERE Variable_name LIKE '%host%';
```

Show current connections’ hostnames/IPs:

```sql
SELECT host FROM information_schema.processlist;
```

---

## Replication / GTID quick checks

Show master status:

```sql
SHOW MASTER STATUS;
```

Show slave status (expanded output):

```sql
SHOW SLAVE STATUS\G
```

Check `read_only`:

```sql
SHOW VARIABLES WHERE variable_name = 'read_only';
```

See also: [GTID replication instruction set](../Instruction%20Sets/gtid_replication_readonly_slave_instructions.md)

---

## Binary log purge (client utility + SQL)

### `mysqlbinlogpurge` (legacy `mysql-utilities`)

The `mysqlbinlogpurge` tool existed in `mysql-utilities` (common on RHEL7-era systems) and may not be available on newer distributions.
If you do have it, these are typical examples:

```bash
# Dry-run: show what would be purged
mysqlbinlogpurge \
  --master=root:msandbox@localhost:45007 \
  --slaves=root:msandbox@localhost:45008,root:msandbox@localhost:45009 \
  --dry-run

mysqlbinlogpurge \
  --master=root:REPLACE_ME@192.168.241.181:3306 \
  --slaves=root:REPLACE_ME@192.168.241.182:3306,root:REPLACE_ME@192.168.241.183:3306 \
  --dry-run

mysqlbinlogpurge --server=root:REPLACE_ME@192.168.241.182:3306 --dry-run
mysqlbinlogpurge --master=root:REPLACE_ME@192.168.241.181:3306 --slaves=root:REPLACE_ME@192.168.241.185:3306 --dry-run

# Dry-run from a specific binlog
mysqlbinlogpurge --server=root:REPLACE_ME@192.168.241.182:3306 --binlog=mysql-bin.000002 --dry-run
```

### `PURGE BINARY LOGS ...` (SQL)

Manual purge to a known-safe file:

```sql
-- Example: latest binlog fully replicated by all replicas is mysql-bin.000011
PURGE BINARY LOGS TO 'mysql-bin.000012';
```

Purge based on time:

```sql
-- Purge logs older than 2 days
PURGE BINARY LOGS BEFORE (DATE(NOW()) - INTERVAL 2 DAY);
```

If you want a safer end-to-end workflow, see the repo script docs: [Purge Binary Logs/Readme.md](../Purge%20Binary%20Logs/Readme.md)

---

## Table + CSV import example (data loading)

Create a table:

```sql
CREATE TABLE inpatientCharges (
  drg_definition VARCHAR(200),
  provider_id INT,
  provider_name VARCHAR(200),
  provider_street_address VARCHAR(200),
  provider_city VARCHAR(50),
  provider_state VARCHAR(10),
  provider_zip_code INT,
  hospital_referral_region_description VARCHAR(50),
  total_discharges INT,
  average_covered_charges VARCHAR(20),
  average_total_payments VARCHAR(20),
  average_medicare_payments VARCHAR(20)
);
```

Simple OLTP-style inserts (example):

```sql
USE test;
INSERT INTO inpatientCharges VALUES ('a',1,'a','a','a','a',1,'a',1,'a','a','a');
SELECT COUNT(*) FROM inpatientCharges;
```

Import a CSV using `mysqlimport` (example; adjust separators to your CSV):

```bash
mysqlimport -u root -p \
  --fields-terminated-by=, \
  --lines-terminated-by='\n' \
  --replace \
  --low-priority \
  --fields-optionally-enclosed-by='"' \
  --ignore-lines=1 \
  --verbose \
  test /data/mysql/inpatient_hospital_charges.csv
```

---

## Consistency checks (`mysqlcheck`)

Check all databases:

```bash
mysqlcheck -uroot --all-databases --check
```

Attempt repairs:

```bash
mysqlcheck -uroot --all-databases --repair
```

If you see `aria_sort_buffer_size is too small`, increasing `aria_sort_buffer_size` in your server config may help repairs succeed (then restart MariaDB).

```ini
# Example (place in your server config file under [mysqld] or the appropriate section)
aria_sort_buffer_size=64M
```
