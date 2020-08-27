#!/bin/bash
set -e

GS_HOME=/var/lib/gridstore
ARCHIVE_CONF=$GS_HOME/archive/conf/gs_archive.properties
EXPIMP_CONF=$GS_HOME/expimp/conf/gs_expimp.properties
WEB_API_CONF=$GS_HOME/webapi/conf/repository.json
GS_ADMIN_PASSWORD=$GS_HOME/admin/conf/password
GS_ADMIN_CONF=$GS_HOME/admin/conf/repository.json
CONNECT_SERVER_TIMEOUT=30

function check_server_status {
  NODE_ADDRESS=$1
  NODE_PORT=$2
  
  cluster_status=$(su - gsadm -c "gs_stat -s $NODE_ADDRESS -p $NODE_PORT -u admin/admin" | jq -r '.cluster.clusterStatus' 2>/dev/null || true)
  echo -n "Waiting for server.."
  j=1
  while [[ "$cluster_status" != "MASTER" && "$cluster_status" != "FOLLOWER" ]];
  do
    echo -n "."
    cluster_status=$(su - gsadm -c "gs_stat -s $NODE_ADDRESS -p $NODE_PORT -u admin/admin" | jq -r '.cluster.clusterStatus' 2>/dev/null || true)
    j=$((j+1))
    if [[ "$j" = "$CONNECT_SERVER_TIMEOUT" ]]; then
      echo "Cannot connect to server. Automatic configuration ignored."
      connect_success="false"
      return 0
    fi
    sleep 2
  done
  echo "connected to server."
}

function config_webapi {
  cluster_mode=$1
  echo "$cluster_mode mode detected"
  echo "Configure WebAPI."
  master_address=$2
  master_port=$3
  WEB_API_CONF_TMP=${WEB_API_CONF}.tmp
  if [ "$cluster_mode" = "FIXED_LIST" ]; then
    read transactionMember sqlMember < <(extract_transaction_sql_member $master_address $master_port)
    cat $WEB_API_CONF | jq ".clusters[].mode = \"FIXED_LIST\"" | jq ".clusters[].sqlMember = \"$sqlMember\"" | jq ".clusters[].name = \"$cluster_name\"" | jq ".clusters[].transactionMember = \"$transactionMember\"" > ${WEB_API_CONF_TMP}
    mv ${WEB_API_CONF_TMP} ${WEB_API_CONF}
  fi

  if [ "$cluster_mode" = "MULTICAST" ]; then
    read notification_address notification_port < <(extract_notification_address_port $master_address $master_port)
    cat $WEB_API_CONF | jq ".clusters[].mode = \"MULTICAST\"" | jq ".clusters[].address = \"$notification_address\"" | jq ".clusters[].port = $notification_port" | jq ".clusters[].jdbcAddress = \"$notification_address\"" | jq ".clusters[].name = \"$cluster_name\"" > ${WEB_API_CONF_TMP}
    mv ${WEB_API_CONF_TMP} ${WEB_API_CONF}
    fi

  if [ "$cluster_mode" = "PROVIDER" ]; then
    provider_url=$(extract_provider_host $master_address $master_port)
    cat $WEB_API_CONF | jq ".clusters[].mode = \"PROVIDER\"" | jq ".clusters[].providerUrl = \"$provider_url\"" | jq ".clusters[].name = \"$cluster_name\"" > ${WEB_API_CONF_TMP}
    mv ${WEB_API_CONF_TMP} ${WEB_API_CONF}
  fi
}

function config_gsadmin {
  echo "Configure GS_ADMIN."
  cluster_name=$1
  master_address=$2
  echo 'admin,8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918' > ${GS_ADMIN_PASSWORD}
  echo 'system,6ee4a469cd4e91053847f5d3fcb61dbcc91e8f0ef10be7748da4c4a1ba382d17' >> ${GS_ADMIN_PASSWORD}
  GS_ADMIN_CONF_TMP=${GS_ADMIN_CONF}.tmp
  cat ${GS_ADMIN_CONF} | jq ".nodes[].address = \"$master_address\"" | jq ".nodes[].clusterName = \"$cluster_name\""> ${GS_ADMIN_CONF_TMP}
  mv ${GS_ADMIN_CONF_TMP} ${GS_ADMIN_CONF}
  jq -s '.[1].clusters[] as $cluster_config | .[0]|.clusters[] = $cluster_config' ${GS_ADMIN_CONF} ${WEB_API_CONF} > ${GS_ADMIN_CONF_TMP}
  mv ${GS_ADMIN_CONF_TMP} ${GS_ADMIN_CONF}
}

function config_archive {
  echo "Configure archive."
  sed -i "/clusterName=/ s/=.*/=${cluster_name}/" ${ARCHIVE_CONF}
  cluster_mode=$1
  master_address=$2
  master_port=$3
  if [ "$cluster_mode" = "FIXED_LIST" ]; then
    sed -i "/mode=/ s/=.*/=FIXED_LIST/" ${ARCHIVE_CONF}
    read transactionMember sqlMember < <(extract_transaction_sql_member $master_address $master_port)
    sed -i "/mode=/ s/=.*/=FIXED_LIST/" ${ARCHIVE_CONF}
    sed -i "/notificationMember=/ s/=.*/=${transactionMember}/" ${ARCHIVE_CONF}
    sed -i "/jdbcNotificationMember=/ s/=.*/=${sqlMember}/" ${ARCHIVE_CONF}
  fi
  
  if [ "$cluster_mode" = "MULTICAST" ]; then
    sed -i "/mode=/ s/=.*/=MULTICAST/" ${ARCHIVE_CONF}
    read notification_address notification_port < <(extract_notification_address_port $master_address $master_port)
    sed -i "/mode=/ s/=.*/=MULTICAST/" ${ARCHIVE_CONF}
    sed -i "/hostAddress=/ s/=.*/=${notification_address}/" ${ARCHIVE_CONF}
    sed -i "/hostPort=/ s/=.*/=${notification_port}/" ${ARCHIVE_CONF}
    sed -i "/jdbcAddress=/ s/=.*/=${notification_address}/" ${ARCHIVE_CONF}
    sed -i "/jdbcPort=/ s/=.*/=${notification_port}/" ${ARCHIVE_CONF}
  fi
  
  if [ "$cluster_mode" = "PROVIDER" ]; then
    provider_url=$(extract_provider_host $master_address $master_port)
    sed -i "/mode=/ s/=.*/=PROVIDER/" ${ARCHIVE_CONF}
    sed -i "/notificationProvider.url=/ s,=.*,=${provider_url},g" ${ARCHIVE_CONF}
  fi
}

function config_expimp {
  echo "Configure import/export."
  sed -i "/clusterName=/ s/=.*/=${cluster_name}/" ${EXPIMP_CONF}
  cluster_mode=$1
  master_address=$2
  master_port=$3
  if [ "$cluster_mode" = "FIXED_LIST" ]; then
    sed -i "/mode=/ s/=.*/=FIXED_LIST/" ${EXPIMP_CONF}
    read transactionMember sqlMember < <(extract_transaction_sql_member $master_address $master_port)
    sed -i "/notificationMember=/ s/=.*/=${transactionMember}/" ${EXPIMP_CONF}
    sed -i "/jdbcNotificationMember=/ s/=.*/=${sqlMember}/" ${EXPIMP_CONF}
  fi
  
  if [ "$cluster_mode" = "MULTICAST" ]; then
    sed -i "/mode=/ s/=.*/=MULTICAST/" ${EXPIMP_CONF}
    read notification_address notification_port < <(extract_notification_address_port $master_address $master_port)
    sed -i "/mode=/ s/=.*/=MULTICAST/" ${EXPIMP_CONF}
    sed -i "/hostAddress=/ s/=.*/=${notification_address}/" ${EXPIMP_CONF}
    sed -i "/hostPort=/ s/=.*/=${notification_port}/" ${EXPIMP_CONF}
    sed -i "/jdbcAddress=/ s/=.*/=${notification_address}/" ${EXPIMP_CONF}
    sed -i "/jdbcPort=/ s/=.*/=${notification_port}/" ${EXPIMP_CONF}
  fi
  
  if [ "$cluster_mode" = "PROVIDER" ]; then
    provider_url=$(extract_provider_host $master_address $master_port)
    sed -i "/mode=/ s/=.*/=PROVIDER/" ${EXPIMP_CONF}
    sed -i "/notificationProvider.url=/ s,=.*,=${provider_url},g" ${EXPIMP_CONF}
  fi
}

function extract_transaction_sql_member {
  master_address=$1
  master_port=$2
  nodes_list=$(su - gsadm -c "gs_stat -s ${master_address} -p ${master_port} -u admin/admin" | jq -r '.cluster.nodeList[].address')
  IFS=' ' read -r -a array <<< $nodes_list
  for index in "${!array[@]}"
  do
    array_trans+=("${array[index]}":10001)
    array_sql+=("${array[index]}":20001)
  done
  transactionMember=$(IFS=, ; echo "${array_trans[*]}")
  sqlMember=$(IFS=, ; echo "${array_sql[*]}")
  echo $transactionMember $sqlMember
}

function extract_notification_address_port {
  master_address=$1
  master_port=$2
  GS_CONFIG=/var/lib/gridstore/gs_config.json
  su - gsadm -c "gs_config -s ${master_address} -p ${master_port} -u admin/admin" > ${GS_CONFIG}
  notification_address=$(cat ${GS_CONFIG} | jq -r '.multicast.address')
  notification_port=$(cat ${GS_CONFIG} | jq -r '.multicast.port')
  rm ${GS_CONFIG}
  echo $notification_address $notification_port
}

function extract_provider_host {
  master_address=$1
  master_port=$2
  provider_url=$(curl --user admin:admin http://${master_address}:${master_port}/node/config | jq -r '.cluster.notificationProvider.url')
  echo $provider_url
}

if [ "$1" = 'client' ]; then
  if [[ -z $GRIDDB_NODE || -z $GRIDDB_PORT ]]; then
    echo 'GRIDDB_NODE and/or GRIDDB_PORT is undefined'
    exit 1
  fi
  
  # Check connection to GridDB cluster
  check_server_status $GRIDDB_NODE $GRIDDB_PORT
  
  if [[ "$connect_success" != "false" ]]; then
    # Get some cluster information
    GS_STAT=/var/lib/gridstore/gs_stat.json
    su - gsadm -c "gs_stat -s $GRIDDB_NODE -p $GRIDDB_PORT -u admin/admin" > ${GS_STAT}
    master_address=$(cat ${GS_STAT} | jq -r '.cluster.master.address')
    master_port=$(cat ${GS_STAT} | jq -r '.cluster.master.port')
    cluster_name=$(cat ${GS_STAT} | jq -r '.cluster.clusterName')
    cluster_mode=$(cat ${GS_STAT} | jq -r '.cluster.notificationMode')
    rm ${GS_STAT}

    # Configure for WebAPI
    config_webapi $cluster_mode $master_address $master_port

    # Configure for GS_ADMIN
    config_gsadmin $cluster_name $master_address

    # Configure for archive
    config_archive $cluster_mode $master_address $master_port

    # Configure for import/export
    config_expimp $cluster_mode $master_address $master_port
  fi
  
  # Start gs_admin (Tomcat)
  su - gsadm -c "cd tomcat/bin && bash startup.sh"
  
  # Start webapi
  SERVICE_SCRIPT=/etc/init.d/griddb-webapi
  sed -i -e '13,14 {s/^[#]*/#/}' $SERVICE_SCRIPT
  service griddb-webapi start
  tail -f $GS_HOME/tomcat/logs/catalina.out
fi

exec "$@"
