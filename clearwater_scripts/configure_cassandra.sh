#!/bin/bash


cd /home/nsl/scripts

cat >> log1.txt << EOF1
EOF1

docker cp configure_users.sh clearwaterdocker_cassandra_1:/usr/bin/configure_users.sh

sleep 1

docker exec clearwaterdocker_cassandra_1 bash -c /usr/bin/configure_users.sh >> log1.txt


cat >> log1.txt << EOF1
"-------------------------------------------------"
EOF1
