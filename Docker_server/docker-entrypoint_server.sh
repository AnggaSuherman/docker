#!/bin/bash
set -e

function replace_config {
  grep "$1" "$3" > /dev/null
  if [ $? -eq 0 ]; then
    echo "replaced $1 to $2 in $3"
    sed -i -e "s/$1/$2/g" $3
    if (( $? )); then
      echo "replace_config failed. $1 $2 $3"
      exit 1
    fi
  fi
}

if [ "$1" = 'griddb' ]; then

  GS_HOME=/var/lib/gridstore
  GS_CLUSTER_JSON=$GS_HOME/conf/gs_cluster.json
  GS_NODE_JSON=$GS_HOME/conf/gs_node.json
  SERVICE_CONF=/etc/sysconfig/gridstore/gridstore.conf
  JQ="jq --indent -1"
  IS_NEWSQL=$(cat $GS_CLUSTER_JSON | $JQ 'has("sql")')

  CLUSTERNAME=${GRIDDB_CLUSTERNAME:-myCluster}
  MIN_NODE_NUM=${GRIDDB_NODE_NUM:-1}

  replace_config '"clusterName": *".*"' '"clusterName": "'$CLUSTERNAME'"' $GS_CLUSTER_JSON
  replace_config 'CLUSTER_NAME=.*' CLUSTER_NAME=$CLUSTERNAME $SERVICE_CONF
  replace_config 'MIN_NODE_NUM=.*' MIN_NODE_NUM=$MIN_NODE_NUM $SERVICE_CONF
  SERVICE_SCRIPT=/etc/init.d/gridstore
  sed -i -e '13,14 {s/^[#]*/#/}' $SERVICE_SCRIPT

  # extra modification based on environment variable
  if ( [[ ! -z $NOTIFICATION_ADDRESS ]] && [[ ! -z $NOTIFICATION_MEMBER ]] ) || \
       ( [[ ! -z $NOTIFICATION_PROVIDER ]] && [[ ! -z $NOTIFICATION_MEMBER ]] ) || \
       ( [[ ! -z $NOTIFICATION_PROVIDER ]] && [[ ! -z $NOTIFICATION_ADDRESS ]] ); then
    echo "Configure GridDB failed: NOTIFICATION_ADDRESS, NOTIFICATION_MEMBER, NOTIFICATION_PROVIDER are exclusive."
    exit 1
  fi

  echo -n "Run GridDB in "

  # MULTICAST mode
  if [ ! -z $NOTIFICATION_ADDRESS ]; then

    echo "MULTICAST mode"

    GS_CLUSTER_JSON_TMP=$(cat $GS_CLUSTER_JSON | \
        $JQ ".cluster.notificationAddress = \"$NOTIFICATION_ADDRESS\"" | \
        $JQ ".transaction.notificationAddress = \"$NOTIFICATION_ADDRESS\"")

    if [[ $IS_NEWSQL = "true" ]]; then
      GS_CLUSTER_JSON_TMP=$($JQ ".sql.notificationAddress = \"$NOTIFICATION_ADDRESS\"" <<< $GS_CLUSTER_JSON_TMP)
    fi

    $JQ '.' <<< $GS_CLUSTER_JSON_TMP > ${GS_CLUSTER_JSON}
  fi


  # FIXED_LIST mode
  if [ ! -z $NOTIFICATION_MEMBER ]; then

    echo "FIXED_LIST mode"

    # convert to array
    IFS=',' read -r -a member_array <<< "$NOTIFICATION_MEMBER"

    if [ "$MIN_NODE_NUM" != "${#member_array[@]}" ]; then
      echo "Failed: size of member list (${#member_array[@]}) is not equal to specified node count ($MIN_NODE_NUM)."
      exit 1
    fi

    # convert to JSON array
    member_json_array=[]
    for index in ${!member_array[@]}; do
      member_json_array=`echo $member_json_array | $JQ ".[$index] = \"${member_array[$index]}\""`;
    done

    # Build notification member list
    notificationMember=$( $JQ '[.[] | {"address":.}]' <<< $member_json_array )

    if [[ $IS_NEWSQL = "true" ]]; then
      notificationMember=$( $JQ '[.[] | {"cluster":.,"sync":.,"system":.,"transaction":.,"sql":.}]' <<< $notificationMember )
    else
      notificationMember=$( $JQ '[.[] | {"cluster":.,"sync":.,"system":.,"transaction":.}]' <<< $notificationMember )
    fi

    notificationMember=$( echo $notificationMember | \
        $JQ '[.[] | .cluster.port=10010]' | \
        $JQ '[.[] | .sync.port=10020]' | \
        $JQ '[.[] | .system.port=10040]' | \
        $JQ '[.[] | .transaction.port=10001]' )

    if [[ $IS_NEWSQL = "true" ]]; then
        notificationMember=$( $JQ '[.[] | .sql.port=20001]' <<< $notificationMember )
    fi

    # Update cluster definition
    GS_CLUSTER_JSON_TMP=$( cat $GS_CLUSTER_JSON | \
        $JQ "del(.cluster.notificationAddress)" | \
        $JQ "del(.cluster.notificationPort)" | \
        $JQ ".cluster.notificationMember = $notificationMember" )

    $JQ '.' <<< $GS_CLUSTER_JSON_TMP > ${GS_CLUSTER_JSON}
  fi
  
  # PROVIDER mode
  if [ ! -z $NOTIFICATION_PROVIDER ]; then

    echo "PROVIDER mode"

    GS_CLUSTER_JSON_TMP=$( cat $GS_CLUSTER_JSON | \
        $JQ "del(.cluster.notificationAddress)" | \
        $JQ "del(.cluster.notificationPort)" | \
        $JQ ".cluster.notificationProvider = {\"url\":\"$NOTIFICATION_PROVIDER\",\"updateInterval\":\"60s\"}" )

    $JQ '.' <<< $GS_CLUSTER_JSON_TMP > ${GS_CLUSTER_JSON}
  fi


  # Update node definition
  if [ ! -z $SERVICE_ADDRESS ]; then

    echo "Service address: $SERVICE_ADDRESS"

    GS_NODE_JSON_TMP=$( cat $GS_NODE_JSON | \
        $JQ ".cluster.serviceAddress = \"$SERVICE_ADDRESS\"" | \
        $JQ ".sync.serviceAddress = \"$SERVICE_ADDRESS\"" | \
        $JQ ".system.serviceAddress = \"$SERVICE_ADDRESS\"" | \
        $JQ ".transaction.serviceAddress = \"$SERVICE_ADDRESS\"" )

    if [[ $IS_NEWSQL = "true" ]]; then
        GS_NODE_JSON_TMP=$( $JQ ".sql.serviceAddress = \"$SERVICE_ADDRESS\"" <<< $GS_NODE_JSON_TMP )
    fi

    $JQ '.' <<< $GS_NODE_JSON_TMP > ${GS_NODE_JSON}
  fi

  service gridstore start

  tail -f $GS_HOME/log/gsstartup.log
fi

exec "$@"
