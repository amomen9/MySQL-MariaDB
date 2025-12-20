# Create a database and application user (MariaDB)

This instruction set is a cleaned-up version of the original “create DB/USER” notes.

---

## 1) Create the database

If you specifically need `utf8` (3-byte), use:

```sql
CREATE DATABASE database_name CHARACTER SET utf8 COLLATE utf8_general_ci;
```

If you can use `utf8mb4` (recommended for full Unicode), use:

```sql
CREATE DATABASE database_name CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
```

---

## 2) Create the user

Create the user and bind it to the application host IP.

```sql
CREATE USER 'user_name'@'IP' IDENTIFIED BY 'REPLACE_ME_PASSWORD';
```

Important: the `IP` must be the application server’s IP (or a safe subnet pattern), not the database server’s IP.

---

## 3) Grant privileges

```sql
GRANT ALL PRIVILEGES ON database_name.* TO 'user_name'@'IP';
FLUSH PRIVILEGES;
```

If you intentionally need the user to grant privileges to others (admin-like), add `WITH GRANT OPTION`:

```sql
GRANT ALL PRIVILEGES ON database_name.* TO 'user_name'@'IP' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```
