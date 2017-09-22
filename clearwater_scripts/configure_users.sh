
#!/bin/bash

cd /usr/share/clearwater/crest/tools/sstable_provisioning
sudo ./BulkProvision homestead-local 2010000000 2010099999 example.com 7kkzTyGW
sudo ./BulkProvision homestead-local 2010100000 2010199999 example.com 7kkzTyGW 
#sudo ./BulkProvision homestead-local 2010200000 2010299999 example.com 7kkzTyGW 
#sudo ./BulkProvision homestead-local 2010300000 2010399999 example.com 7kkzTyGW 

sleep 1
#sudo ./BulkProvision homestead-local 2010500000 2010599999 example.com 7kkzTyGW  
#sudo ./BulkProvision homestead-local 2010600000 2010699999 example.com 7kkzTyGW  
#sudo ./BulkProvision homestead-local 2010700000 2010799999 example.com 7kkzTyGW
#sudo ./BulkProvision homestead-local 2010800000 2010899999 example.com 7kkzTyGW

. /etc/clearwater/config
sleep 1
sstableloader -v -d ${cassandra_hostname:-$local_ip} homestead_cache/impi
sstableloader -v -d ${cassandra_hostname:-$local_ip} homestead_cache/impu
sstableloader -v -d ${cassandra_hostname:-$local_ip} homestead_provisioning/implicit_registration_sets
sstableloader -v -d ${cassandra_hostname:-$local_ip} homestead_provisioning/public
sstableloader -v -d ${cassandra_hostname:-$local_ip} homestead_provisioning/private
