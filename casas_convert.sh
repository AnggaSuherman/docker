#!/bin/bash
gawk  '{ printf "{\"datetime\" : \"%s %s\",  \"sensor\" : \"%s\", \"translate01\": \"%s\",  \"translate02\": \"%s\", \"message\":\"%s\", \"sensoractivity\": \"%s\", \"location\": \"'${1}'\"   }\n", $1, $2, $3, $4, $5, $6, $7 }'  ${1}/${1}.rawdata.txt 

for loc in `ls`; do
   ./casas_convert.sh | /kafka_2.13-2.6.0/bin/kafka-console-producer.sh  --bootstrap-server localhost:9092 --topic casas
done
