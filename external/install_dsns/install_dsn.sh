#!/usr/bin/env bash

########################
# This script installs all required drivers

function hr {
  printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
}

function print_debug {
  echo "$(tput bold)$1$(tput sgr 0)"
}

function print_info {
  hr; print_debug "$(tput setaf 4)$1$(tput sgr 0)"; hr
}

function print_error {
  print_debug "$(tput setaf 1)$1$(tput sgr 0)"
}

function print_ok {
  print_debug "$(tput setaf 2)$1$(tput sgr 0)"
}

function install_odbc_datasource {
  DRIVER=$1
  CONNECTION_NAME=$2
  HOSTNAME=$3
  PORT=$4
  DATABASE=$5
  cat <<EOF | odbcinst -i -s -r -l
[${CONNECTION_NAME}]
Driver      = ${DRIVER}
Description = Connection ${CONNECTION_NAME}
Trace       = No
Server      = ${HOSTNAME},${PORT}
Database    = ${DATABASE}
EOF
}

function install_linux_odbc_datasource {
  install_odbc_datasource "ODBC Driver 17 for SQL Server" "$@"
}

function install_macos_odbc_datasource {
  install_odbc_datasource "/usr/local/lib/libmsodbcsql.17.dylib" "$@"
}

function test_connection {
  DSN=$1
  COMMAND=(python3 -c """
import pyodbc, os
from dotenv import load_dotenv
load_dotenv(dotenv_path='${HOME}/.config/cf_creds')
pyodbc.connect(f'DSN=${DSN};UID={os.environ[\"AZURE_DB_USERNAME\"]};PWD={os.environ[\"AZURE_DB_PWD\"]}')
""")
  echo "${COMMAND[@]}"
  if "${COMMAND[@]}"; then
    print_ok "Connection ${DSN} works"
  else
    print_error "Connection ${DSN} cannot be established!"
  fi
}

DSN_FILE=$1

unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
  print_info "Detected OS is Linux...."

  print_info "Installing MS ODBC driver 17"
  set -o pipefail && \
    apt-get update --fix-missing && \
    apt-get install curl && \
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    ACCEPT_EULA=Y apt-get install -y \
      msodbcsql17 \
      unixodbc-dev && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

  print_info "Installing ODBC data sources ..."
  while IFS=, read -r connection_name hostname port database
  do
    install_linux_odbc_datasource $connection_name $hostname $port $database
  done < $DSN_FILE

elif [[ "$unamestr" == 'Darwin' ]]; then
  print_info "Detected OS is MAC OS X"
  print_info "Installing MS SQL system dependencies..."
  brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
  brew update
  HOMEBREW_NO_ENV_FILTERING=1 ACCEPT_EULA=Y brew install msodbcsql17 mssql-tools unixodbc

  print_info "Installing ODBC data sources ..."
  while IFS=, read -r connection_name hostname port database
  do
    install_macos_odbc_datasource $connection_name $hostname $port $database
  done < $DSN_FILE

else
  print_error "Unknown detected OS"
fi

if [[ -f "${HOME}/.config/cf_creds"  ]]; then
  print_info "You seem to have installed your credential file at ${HOME}/.config/cf_creds"
  print_info "Testing installed ODBC data sources ..."
  while IFS=, read -r connection_name hostname port database
  do
    test_connection $connection_name
  done < $DSN_FILE
else
  print_error "No credential file found at ${HOME}/.config/cf_cred"
  print_error "Skipping testing ..."
fi
