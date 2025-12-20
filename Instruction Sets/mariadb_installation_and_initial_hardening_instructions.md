# MariaDB Installation & Initial Hardening (RHEL/CentOS-style)

These steps consolidate the original notes into a readable, repeatable install procedure.

> Notes
> - Commands assume `root` or `sudo`.
> - Replace placeholders like `REPLACE_ME_PASSWORD`.

---

## 1) Install MariaDB packages

### Option A: Use the MariaDB repo setup script

This is the quickest approach.

```bash
curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
```

If you downloaded the script manually, ensure it is executable:

```bash
chmod +x mariadb_repo_setup
```

### Option B: Manual download (when you cannot use the repo script)

1. Download the packages from `mariadb.com`.
   - If your location blocks access, you may need a VPN.
2. Extract the archive.

```bash
tar -xvf <downloaded-archive>.tar
```

3. Install required RPMs (order matters in many environments).

```bash
# Example flow (adjust package names/versions to what you downloaded)
rpm -ivh MariaDB-common*.rpm
rpm -ivh MariaDB-client*.rpm

# If you need Galera tooling (cluster-related)
rpm -ivh galera*.rpm socat*.rpm

rpm -ivh MariaDB-server*.rpm

# Optional: MariaDB backup package (versioned)
yum -y install MariaDB-backup-10.5.11*
```

---

## 2) Create log directory and set ownership

```bash
mkdir -p /var/log/mysql/
chown -R mysql:mysql /var/log/mysql/
```

Also ensure the data directory is owned by `mysql`:

```bash
chown -R mysql:mysql /var/lib/mysql/
```

---

## 3) Configure MariaDB (`my.cnf`)

### Error log + bind address

Edit your server config (commonly `/etc/my.cnf.d/server.cnf`). Under the server section (typically `[mysqld]`):

```ini
[mysqld]
log_error=/var/log/mysql/mysqld.log
bind-address=0.0.0.0
```

### Optional: Change the data directory (`datadir`) and socket

This is a relocation procedure; do it carefully.

1. Create destination directories and copy data.

```bash
mkdir -p /data/mysql
mkdir -p /var/log/mysql/
chown -R mysql:mysql /data/mysql

# Copy current data to the new location
rsync -av /var/lib/mysql/ /data/mysql/

# Keep a backup of the old directory
mv /var/lib/mysql /var/lib/mysql.bak
```

2. Update server config (under `[mysqld]`) to point to the new paths.

```ini
[mysqld]
datadir=/data/mysql/mysql
socket=/data/mysql/mysql/mysql.sock
```

3. Update client socket so local `mysql` connections work.

```ini
[client]
port=3306
socket=/data/mysql/mysql/mysql.sock
```

> CentOS 7 note (from original): config file permissions may need to be `644`.

```bash
chmod 644 /etc/my.cnf.d/*
```

> SELinux note (common blocker): if SELinux is enforcing, you may need to update file contexts for the new `datadir`.

---

## 4) Enable and start the service

```bash
systemctl enable mariadb.service
systemctl start mariadb.service
systemctl status mariadb.service
```

Check the log file if startup fails:

```bash
tail -n 200 /var/log/mysql/mysqld.log
```

---

## 5) Run `mysql_secure_installation`

```bash
mysql_secure_installation
```

Important note from the original sheet: run this **before** relocating the data directory, otherwise it may not work as expected.

---

## 6) Remove default/test users and databases

Drop anonymous users and the test database:

```bash
mysql -e "DROP USER ''@localhost;"
mysql -e "DROP USER ''@<hostname>;"  # replace <hostname> with your server hostname
mysql -e "DROP DATABASE test;"
```

---

## 7) Create/enable remote admin access (if required)

The original notes create a `root` superuser accessible from all remote hosts.
That works, but it is risky.
If possible, prefer creating a separate admin user and restrict by IP.

```bash
# BEGIN: create a superuser (original intent)
mysql -e "CREATE OR REPLACE USER root IDENTIFIED BY 'REPLACE_ME_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root' WITH GRANT OPTION;"
mysql -e "ALTER USER root PASSWORD EXPIRE NEVER;"

# If your setup requires forcing local `root@localhost` to use mysql_native_password
# (plugin availability depends on MariaDB version/config):
mysql -e "ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('REPLACE_ME_PASSWORD');"
# END
```

---

## 8) Open firewall port (remote access)

```bash
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --reload
```
