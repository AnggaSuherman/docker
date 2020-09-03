#!/bin/bash
gawk  '{ printf "{\"datetime\" : \"%s %s\",  \"sensor\" : \"%s\", \"translate01\": \"%s\",  \"translate02\": \"%s\", \"message\":\"%s\", \"sensoractivity\": \"%s\", \"location\": \"csh101\"   }\n", $1, $2, $3, $4, $5, $6, $7 }'  csh101.rawdata.txt
