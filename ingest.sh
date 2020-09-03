#!/bin/bash
for loc in `ls`; do
   ./casas_convert.sh | /kafka_2.13-2.6.0/bin/kafka-console-producer.sh  --bootstrap-server localhost:9092 --topic casas
done
