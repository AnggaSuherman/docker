#!/bin/bash
chown gsadm.gridstore /var/lib/gridstore/data

IP=`grep $HOSTNAME /etc/hosts | awk ' { print $1 }'`

cat << EOF > /var/lib/gridstore/conf/gs_cluster.json
{
        "dataStore":{
                "partitionNum":128,
                "storeBlockSize":"64KB"
        },
        "cluster":{
                "clusterName":"myCluster",
                "replicationNum":1,
                "notificationInterval":"5s",
                "heartbeatInterval":"5s",
                "loadbalanceCheckInterval":"180s",
				"notificationMember": [
					{
						  "cluster":     {"address":"172.17.0.2", "port":10010},
						  "sync":        {"address":"172.17.0.2", "port":10020},
						  "system":      {"address":"172.17.0.2", "port":10040},
						  "transaction": {"address":"172.17.0.2", "port":10001},
						  "sql":         {"address":"172.17.0.2", "port":20001}
					}
				]
        },
        "sync":{
                "timeoutInterval":"30s"
        }
}
EOF

gs_passwd admin -p admin
gs_startnode

while gs_stat -u admin/admin | grep RECOV > /dev/null; do
    echo Waiting for GridDB to be ready.
    sleep 5
done

gs_joincluster -c myCluster -u admin/admin

tail -f /var/lib/gridstore/log/gridstore*.log

