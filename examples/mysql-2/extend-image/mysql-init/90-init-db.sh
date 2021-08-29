init_test_database() {
  local thisdir
  local init_data_file
  thisdir=$(dirname ${BASH_SOURCE[0]})
  init_data_file=$(readlink -f ${thisdir}/../mysql-data/init.sql)
  log_info "Initializing the test database from file ${init_data_file}..."
  mysql $mysql_flags ${MYSQL_DATABASE} < ${init_data_file}
}

if $MYSQL_DATADIR_FIRST_INIT ; then
  init_test_database
fi