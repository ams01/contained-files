start_num=2010000000
max_num=1
passwd=7kkzTyGW

if [ $1 -gt 0 ];
then
    max_num=$1
fi

if [ $2 -gt 0 ];
then
	start_num=2010500000
fi


echo "SEQUENTIAL"
for (( i=0; i<${max_num}; i++ ))
do
	num=$(($start_num + $i))
	echo "$num;example.com;[authentication username=$num@example.com password=$passwd]"
done
