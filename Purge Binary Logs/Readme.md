This bash script helps safely backup first and then remove MySQL family DBMSs binary logs in a MySQL replication. Meaning, it first makes sure that the binary logs are applied successfully on all other replicas, then removes them from MySQL's default binary logs directory and archives them at user's will. The archiving is also safe because the logs will not be purged unless they are successfully archived if the database admin wishes to do so. This script replaces the old mysqlbinlogpurge binary which was available under mysql-utilities package under RHEL7 and earlier, but it was discontinued as of RHEL8.