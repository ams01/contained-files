#!/bin/bash


cat >> log.txt << EOF1
EOF1


docker exec clearwaterdocker_sprout_1 bash -c "tc -s qdisc ls dev eth0" >> log.txt
docker exec clearwaterdocker_sprout_1 bash -c "tc qdisc del dev eth0 root" >> log.txt


cat >> log.txt << EOF1
"-------------------------------------------------"
EOF1
