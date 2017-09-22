#!/bin/bash

delay=50ms

if [ $1 ]
then
    delay=$1
fi

cat >> log.txt << EOF1
"Delay Value : $delay"
EOF1

#docker exec clearwaterdocker_sprout_1 bash -c "tc -s qdisc ls dev eth0" >> log.txt
#docker exec clearwaterdocker_sprout_1 bash -c "tc qdisc del dev eth0 root" >> log.txt
#docker exec clearwaterdocker_sprout_1 bash -c "tc qdisc add dev eth0 root netem delay $delay" >> log.txt


docker exec clearwaterdocker_sprout_1 bash -c "sudo tc qdisc add dev eth0 root handle 1: prio priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0" >> log.txt
docker exec clearwaterdocker_sprout_1 bash -c "sudo tc qdisc add dev eth1 parent 1:2 handle 20: netem delay $delay" >> log.txt
docker exec clearwaterdocker_sprout_1 bash -c "sudo tc filter add dev eth1 parent 1:0 protocol ip u32 match ip dport 8888 0xffff flowid 1:2" >> log.txt
docker exec clearwaterdocker_sprout_1 bash -c "sudo tc filter add dev eth1 parent 1:0 protocol ip u32 match ip dport 5052 0xffff flowid 1:2" >> log.txt


cat >> log.txt << EOF1
"-------------------------------------------------"
EOF1
