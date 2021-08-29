log_info "Creating bookinfo user"
log_info "$mysql_flags"
mysql $mysql_flags <<EOSQL
    CREATE USER '${MYSQL_BOOKUSER}'@'%' IDENTIFIED BY '${MYSQL_BOOKPASSWORD}';
EOSQL

log_info "Granting privileges to user ${MYSQL_BOOKUSER} for ${MYSQL_DATABASE} ..."
mysql $mysql_flags <<EOSQL
    GRANT ALL ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_BOOKUSER}'@'%' ;
    ALTER USER '${MYSQL_BOOKUSER}'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_BOOKPASSWORD}';
    FLUSH PRIVILEGES;
EOSQL