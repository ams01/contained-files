#!/bin/bash

iterations_config=10
flush_iterations_config=15
time=60
num=0
hy="_"
gsleep=60
round=0
restart_clearwater=1
disable_flush=0

# The following need to be updated
# hostname
# clearwater_ip
# <dispatcher_ip:port> (can use the default port 5060)

# the user name used is : username
hostname=<Server running clearwater>

resultfile=final_result.csv
datafile=data_dump.csv

declare -a ratearr=("300" "600" "900" "1200" "1500" "1600" "1700" "1800" "1900")
declare -a delayarr=("0ms" "5ms" "10ms" "15ms" "20ms" "25ms" "30ms" "40ms" "50ms")

dfile=dfile.txt
echo "" > itr.txt
echo " ------------------------------------------------------------------------"

# this function is called when Ctrl-C is sent
function exit_handler ()
{
    # perform cleanup here
    echo "Ctrl-C caught...performing clean up"
 
    echo "Doing cleanup"
    pkill -9 sipp
    ssh username@$hostname screen -d -m  stop_clearwater
    ssh username@$hostname screen -d -m  stop_dispatcher.sh

    echo "Done"
    mv *.err logfiles/
 
    # exit shell script with error code 2
    # if omitted, shell script will continue execution
    exit 2
}
 
# initialise trap to call trap_ctrlc function
# when signal 2 (SIGINT) is received
trap "exit_handler" 2


#stash the old reports
current_time=$(date "+%Y.%m.%d-%H.%M.%S")
new_resultfile=resultfile_$current_time.csv
new_datafile=datafile_$current_time.csv
mv $resultfile $new_resultfile
mv $datafile $new_datafile
cp $new_resultfile result_bk/
cp $new_datafile result_bk/


rm *.txt
rm *.csv
rm *.xlsx
rm *.xls
rm *.err

echo "Delay,Sample Size, Elapsed Time,Target Rate,Actual Rate, Total Calls, Successful Calls, Failed Calls" >  $resultfile
echo "Delay,Elapsed Time,Target Rate,Actual Rate, Total Calls, Successful Calls, Failed Calls" >  $datafile

screen_log=0
experimental=0
while getopts ":s:e:r:" opt; do
  case $opt in
    s) screen_log=1
    ;;
    e) experimental=1
    ;;
    r) echo "Setting restart clearwater to false" 
       restart_clearwater=0
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

echo "---------- screen_log :$screen_log---------------"

if [ $experimental -gt 0 ]
then
	iterations=2
	time=2
	gsleep=2
	disable_flush=1
	declare -a ratearr=("1600")
	declare -a delayarr=("10ms" "25ms" )

fi

echo "---------- experimental :$experimental---------------"

echo "---------- restart_clearwater :$restart_clearwater---------------"

ratelength=${#ratearr[@]}
max_calls=$((${ratearr[$ratelength-1]}))
echo "max calls : $max_calls"


check_process() {
  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -n $1` ] && return 1 || return 0
}

check_process "sipp"
retval = $? 
if [ $retval -eq 1 ]
then
	echo " Killing existing Sipp exe"
	pkill -9 sipp
	sleep 10
fi


my_sleep()
{
	timer=5
	sleep_duration=$1
	echo "Sleeping for $sleep_duration seconds"
	echo ""
	
	sleep_period=$(($sleep_duration/5))
	for (( itrt=0; itrt<sleep_period; itrt++ ));
	do
		sleep 5
                printf "%d " $(($timer*($itrt+1)))
	done
	echo " "	
}

# clearwater token management results in packet drops when run for the first time at high call rates
# flush it with the max callrate before we begin
flush_clearwater_throttle()
{

	dispatcher_run=$1	
	flush_callnum=108000
	flush_callrate=1800
	
	filename=user_details.cfg

	exec_cmd="./sipp "
	if [ $dispatcher_run -gt 0 ]
	then
	echo "Flush Dispatcher"
	   exec_cmd="./sipp <dispatcher_ip:port>"	
	fi

	if [ $disable_flush -gt 0 ]
	then
		echo " Flush disabled"
		return 0	
	fi
	
	echo "Running flush_clearwater_throttle"
	if [ $screen_log -gt 0 ]
	then
			$exec_cmd -sf REGISTER_client.xml -trace_screen -trace_stat -trace_rtt --stat_delimiter ,  \
			-trace_err -trace_error_codes -error_file err.err -fd 1  \
			-nr -stf result_failure.csv -m $flush_callnum -recv_timeout 10s -inf $filename -l $flush_callnum -r $flush_callrate 
			pkill -9 sipp
	else
			$exec_cmd -sf REGISTER_client.xml -trace_screen -trace_stat -trace_rtt --stat_delimiter ,  \
			-trace_err -trace_error_codes -error_file err.err -fd 1 \
			-nr -stf result_failure.csv -m $flush_callnum -recv_timeout 10s -inf $filename -l $flush_callnum -r $flush_callrate -bg
			my_sleep 60
			pkill -9 sipp
	fi
	
	round=$(($round + 1))
	
	echo "Finished flush_clearwater_throttle"
	
	awk ' BEGIN {FS=","}
	{ target_rate += $6; call_rate += $8; total_calls += $13; suc += $16; failed += $18; }
	END { printf("%s,%.2f,%.2f,%.2f,%.2f,%.2f \n",$5,$6,$8,$13,$16,$18)}' result_failure.csv

	echo "Waiting to 120 seconds in flush_clearwater_throttle"
	my_sleep 120	
}


# Init clearwater with dispatcher
init_clearwater_d()
{
        state=0
        if [ $restart_clearwater -gt 0 ]
        then

                while [[ $state -lt 3 ]]; 
                do
                        echo "Rebooting Clearwater"
                        ssh username@$hostname screen -d -m  stop_clearwater_d
                        my_sleep 5
                        ssh username@$hostname screen -d -m  stop_dispatcher.sh
                        ssh username@$hostname screen -d -m  start_clearwater_d
                        echo "Restarting Clearwater"
						# It may take an arbitrary long time for clearwater containers to come up, this can be checked by executing the script state.sh on the system running Clearwater
						# 20 should be long enough
                        for (( itr=0; itr<20; itr++ ));
                        do
                            my_sleep 30
                            ssh username@$hostname state.sh > temp_state.txt
                            state=$(cat temp_state.txt | grep -c "normal")
                            if [ $state -eq 3 ]
                            then
                                    echo "Completed"
                                    break;
                            else
                                    echo "Waiting for 10 more seconds"
                                    my_sleep 10
                            fi
                        done
                done

				# Cassandra has to be configured after every reboot, to ensure that user auth vectors are created.	
                echo "Configuring Cassandra"
                ssh username@$hostname clearwater-docker/utils/show_cluster_state.sh
                ssh username@$hostname screen -d -m configure_cassandra.sh
                my_sleep 90
        else
                my_sleep 30
        fi

}


run_dispatcher(){
	ind_delay=0

	logfile=logfile_dispatcher.txt
	rm $logfile
	ssh username@$hostname screen -d -m  restart_dispatcher.sh
	echo "Sleeping for 10s"
	sleep 10
	#Clear the delay from sprout	
	ssh username@$hostname screen -d -m  clear_delay.sh
	sleep 10
	
	iterations=$iterations_config	
        echo "Dispatcher updated iterations to $iterations" >> itr.txt
	# get length of an array
	ratelength=${#ratearr[@]}

	echo "Rate Length : $ratelength"
	
	iterations=$iterations_config	
	echo "Dispatcher updated iterations to $iterations callrate : $callrate" >> itr.txt
	echo "Delay updated iterations to $iterations" >> itr.txt
	flush=0
	flush_rate=1800

	for (( it=1; it<${ratelength}+1; it++ ));
	do
  	    flush_clearwater_throttle 1
		rm *.log
		callrate=$((${ratearr[$it-1]}))    
	    callnum=$(($callrate * $time))
		flag=0
		for (( i=0; i<$iterations; i++ ))
		do

		# incase there are sufficient users on clearwater, change the SIPp config and contiunue
	        if [ `expr $round % 2` -eq 0 ]
	        then
	                filename=user_details.cfg
	        else
	                filename=user_details.cfg
	        fi

		iterations=$iterations_config	
	    echo "Dispatcher updated iterations to $iterations callrate : $callrate" >> itr.txt

		send_rate=$(($callrate/10))
		echo "send rate : $send_rate"
		rm *.log
	        round=$(($round + 1))

			send_rate=$(($callrate/10))
		   	echo "Filename : $filename CallRate : $callrate Send Rate : $send_rate Iteration : $i"

			if [ $screen_log -gt 0 ]
			then
		        	./sipp <dispatcher_ip:port> -sf REGISTER_client.xml -trace_screen -trace_stat -trace_rtt --stat_delimiter , \
					-trace_err -trace_error_codes -error_file log_dis$hy$callrate$hy$i.err  -fd 1  -stf result_dis$hy$callrate$hy$i.csv \
		       		 	-nr -m $callnum -recv_timeout 10s -inf $filename -l $callnum -r $send_rate -rp 100 
				pkill -9 sipp
			else

		        	./sipp <dispatcher_ip:port> -sf REGISTER_client.xml -trace_screen -trace_stat -trace_rtt --stat_delimiter , \
					-trace_err -trace_error_codes -error_file log_dis$hy$callrate$hy$i.err  -fd 1  -stf result_dis$hy$callrate$hy$i.csv \
		       		 	-nr -m $callnum -recv_timeout 10s -inf $filename -l $callnum -r $send_rate -rp 100 -bg
				echo "Sleeping for $time + 5 seconds"
				my_sleep $time
				my_sleep 5
				pkill -9 sipp
			fi

	        echo "" >> $logfile
	        echo "" >> $logfile
	        echo "" >> $logfile
	        echo "***********************************************" >> $logfile
	        echo "Filename : $filename CallRate : $callrate Dispatcher" >> $logfile
	        echo "***********************************************" >> $logfile
			ls -l *.log >> $logfile	
	        sed -n 13,38p *.log >> $logfile

	       	if [ $flag -eq 0 ]
	        then
	        	awk 'NR==1; END{print}' result_dis$hy$callrate$hy$i.csv  >> result_dis$hy$callrate.csv
	            flag=$(($flag + 1))
	    	else
	        	awk 'END{print}' result_dis$hy$callrate$hy$i.csv  >> result_dis$hy$callrate.csv
	        fi

           	printf "dispatcher," >> $datafile
            	awk ' BEGIN {FS=","}
            	{ target_rate += $6; call_rate += $8; total_calls += $13; suc += $16; failed += $18; }
           	 END { printf("%s,%.2f,%.2f,%.2f,%.2f,%.2f \n",$5,$6,$8,$13,$16,$18)}' result_dis$hy$callrate.csv >> $datafile

		head -1 $datafile
		tail -1 $datafile


		# skip on the last iteration
		if (($i < ${iterations} - 1))
			then
					echo " Iteration $i finished, Waiting for REGISTER timeout : $gsleep seconds"

					if [ $flush -gt 0 ]
					then
							if [ $callrate -gt $flush_rate ]
							then
									init_clearwater_d
									ssh username@$hostname screen -d -m  restart_dispatcher.sh
									flush_clearwater_throttle 1
							else
									my_sleep $gsleep
							fi
					else
							my_sleep $gsleep
					fi
			fi


		mv *.log logfiles/
	    done
	
	    printf "dispatcher," >> $resultfile
	    # awk ' BEGIN {FS=","}
    	    # NR>1{target_rate += $6; call_rate += $8; total_calls += $13; suc += $16; failed += $18; }
    	    # END { if (NR > 1) printf("%s,%.2f,%.2f,%.2f,%.2f,%.2f \n"\
    	    # ,$5,(target_rate/(NR-1)),(call_rate/(NR-1)),(total_calls/(NR-1)),(suc/(NR-1)),(failed/(NR-1)))}' result_dis$hy$callrate.csv >> $resultfile
			
		awk ' BEGIN {FS=","}
		(NR>1 && $16 > 0 && $16 > $13/1.2 ){sample_size +=1; target_rate += $6; call_rate += $8; total_calls += $13; suc += $16; failed += $18; }
		END { if (NR > 1) printf("%d,%s,%.2f,%.2f,%.2f,%.2f,%.2f"\
		,sample_size,$5,(target_rate/(sample_size)),(call_rate/(sample_size)),(total_calls/(sample_size)),(suc/(sample_size)),(failed/(sample_size)))}' result_dis$hy$callrate.csv >> $resultfile
		
		printf "\n" >> $resultfile
	done
	dos2unix $logfile
	cat $logfile
	cat $logfile >> $dfile
	current_time=$(date "+%Y.%m.%d-%H.%M.%S")
	new_fileName=logfile_dispatcher_$current_time.txt
	mv $logfile $new_fileName    
	#./sync_dropbox 
}

#Init Clearwater without dispatcher
init_clearwater()
{
        state=0
        if [ $restart_clearwater -gt 0 ]
        then

                while [[ $state -lt 3 ]]; 
                do
                        echo "Rebooting Clearwater"
                        ssh username@$hostname screen -d -m  stop_clearwater
                        my_sleep 5
                        ssh username@$hostname screen -d -m  stop_dispatcher.sh
                        ssh username@$hostname screen -d -m  start_clearwater
                        echo "Restarting Clearwater"
                        my_sleep 30
                        for (( itr=0; itr<18; itr++ ));
                        do
                            my_sleep 10
                            ssh username@$hostname state.sh > temp_state.txt
                            state=$(cat temp_state.txt | grep -c "normal")
                            if [ $state -eq 3 ]
                            then
                                    echo "Completed"
                                    break;
                            else
                                    echo "Waiting for 10 more seconds"
                                    my_sleep 10
                            fi
                        done
                done

                echo "Configuring Cassandra"

                ssh username@$hostname clearwater-docker/utils/show_cluster_state.sh

                ssh username@$hostname screen -d -m configure_cassandra.sh
                my_sleep 90
        else
	        echo "Reboot Disabled : Not Rebooting clearwater"
                my_sleep 5
	
        fi

}

run_delay(){

	# Add the delay to sprout
	ind_delay=$1 
	flush_rate=1500

	logfile=logfile_$ind_delay.txt
	rm $logfile
	echo "Delay : $ind_delay"
	
	# Set the latency on sprout
	ssh username@$hostname screen -d -m  add_delay.sh $ind_delay
	sleep 10

	iterations=$iterations_config	

    echo "Delay updated iterations to $iterations" >> itr.txt
	if [ "$ind_delay" == "0ms" ] 
	then
		echo "Running No Delay"		
		flush=0
		flush_rate=2400
	fi

	flush=0
	if [ "$ind_delay" == "5ms" ] || [ "$ind_delay" == "10ms" ] || [ "$ind_delay" == "15ms" ]
	then
		flush=1	
		flush_rate=1400
		echo "Setting Flush to 1 and flush rate to $flush_rate"	
		
	fi


	if [ "$ind_delay" == "20ms" ]
	then
		flush=1	
		flush_rate=500
		echo "Setting Flush to 1 and flush rate to $flush_rate"	
		
	fi
	
	if [ "$ind_delay" == "25ms" ] ||  [ "$ind_delay" == "30ms" ] || [ "$ind_delay" == "40ms" ] || [ "$ind_delay" == "50ms" ]
	then
		flush=1
		flush_rate=200
		echo "Setting Flush to 1 and flush rate to $flush_rate"	
	fi
	
	 
	# get length of an array
	ratelength=${#ratearr[@]}

	echo "Rate Length : $ratelength"
	for (( it=1; it<${ratelength}+1; it++ ));
	do

	    iterations=$iterations_config	
	    callrate=$((${ratearr[$it-1]}))    
	    callnum=$(($callrate * $time))
     
            echo "Delay updated iterations to $iterations callrate : $callrate" >> itr.txt
            if [ $flush -gt 0 ]
            then
           	 if [ $callrate -gt $flush_rate ]
                 then
                 	echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
                        echo "Flush is true and callrate greater $flush_rate, Rebooting clearewater"
                        init_clearwater
                        flush_clearwater_throttle 0
			iterations=$flush_iterations_config	
                        echo "updated iterations to $iterations Callrate: $callrate" >> itr.txt
                 else
					# Run flush with no delay to ensure the connections to sprout are recreted 
					flush_clearwater_throttle 0
                 fi
            else
				# Run flush with no delay to ensure the connections to sprout are recreted 
				flush_clearwater_throttle 0
            fi
		
	    rm *.log
	    flag=0
	    for (( i=0; i<$iterations; i++ ))
	    do
	    # incase there are sufficient users on clearwater, change the SIPp config and contiunue
	        if [ `expr $round % 2` -eq 0 ]
	        then
	                filename=user_details.cfg
	        else
	                filename=user_details.cfg
	        fi

			if [ "$ind_delay" != "0ms" ] 
			then
				echo "Adding delay $ind_delay"
				ssh username@$hostname screen -d -m  add_delay.sh $ind_delay
				my_sleep 5
			fi	

		    round=$(($round + 1))
			send_rate=$(($callrate/10))
			echo "send rate : $send_rate"
			rm *.log
		        echo "Filename : $filename CallRate : $callrate Delay : $ind_delay Iteration : $i"
		        sleep 1

			if [ $screen_log -gt 0 ]
			then
		        	./sipp <clearwater_ip> -sf REGISTER_client.xml -trace_screen -trace_stat -trace_rtt --stat_delimiter ,  \
					-trace_err -trace_error_codes -error_file log$hy$ind_delay$hy$callrate$hy$i.err  -fd 1  -stf result$hy$ind_delay$hy$callrate$hy$i.csv \
		        		-nr -m $callnum -recv_timeout 10s -inf $filename -l $callnum -r $send_rate -rp 100
			    	pkill -9 sipp
		        else
				./sipp <clearwater_ip> -sf REGISTER_client.xml -trace_screen -trace_stat -trace_rtt --stat_delimiter , \
					-trace_err -trace_error_codes -error_file log$hy$ind_delay$hy$callrate$hy$i.err  -fd 1  -stf result$hy$ind_delay$hy$callrate$hy$i.csv \
		        		-nr -m $callnum -recv_timeout 10s -inf $filename -l $callnum -r $send_rate -rp 100 -bg
				echo "Sleeping for $time seconds"
				my_sleep $time
				my_sleep 5
			    pkill -9 sipp
			fi

			if [ "$ind_delay" != "0ms" ] 
			then
				ssh username@$hostname screen -d -m  clear_delay.sh
				sleep 2
			fi 
			
	        echo "" >> $logfile
	        echo "" >> $logfile
	        echo "" >> $logfile
	        echo "***********************************************" >> $logfile
	        echo "Filename : $filename CallRate : $callrate Delay : $ind_delay" >> $logfile
	        echo "***********************************************" >> $logfile
	        sed -n 13,38p *.log >> $logfile
			ls -l *.log >> $logfile
		       
			if [ $flag -eq 0 ]
	        then
	        	awk 'NR==1; END{print}' result$hy$ind_delay$hy$callrate$hy$i.csv  >> result$hy$ind_delay$hy$callrate.csv
	        	flag=$(($flag + 1))
	    	else
	        	awk 'END{print}' result$hy$ind_delay$hy$callrate$hy$i.csv  >> result$hy$ind_delay$hy$callrate.csv
	        fi

	       	printf "$ind_delay," >> $datafile
	        	awk ' BEGIN {FS=","}
	        	{ target_rate += $6; call_rate += $8; total_calls += $13; suc += $16; failed += $18; }
	       	 END { printf("%s,%.2f,%.2f,%.2f,%.2f,%.2f \n",$5,$6,$8,$13,$16,$18)}' result$hy$ind_delay$hy$callrate.csv >> $datafile
			head -1 $datafile
			tail -1 $datafile
					
			awk ' BEGIN {FS=","}
			{ target_rate += $6; call_rate += $8; total_calls += $13; suc += $16; failed += $18; }
			END { printf("%s,%.2f,%.2f,%.2f,%.2f,%.2f \n",$5,$6,$8,$13,$16,$18)}' result$hy$ind_delay$hy$callrate.csv > reg.tmp

			cat reg.tmp

			tail -n 1 reg.tmp > temp_count.txt

			v1=( $(awk 'BEGIN {FS=","} {printf("%d",$5)}' temp_count.txt))
			suc_num=${v1[0]}	    

			echo "Finished Running CallRate : $callrate Delay : $ind_delay Successful calls : $suc_num"

			if [ $callrate -gt 0 ] && [ $suc_num -eq 0 ] && [ $flush -gt 0 ]
			then
				
				if [ $callrate -gt $flush_rate ]
				then
					echo " ******************************************************************************** "
					echo "No reboot Necesary Flush is set"
				else
					echo " -------------------------------------------------------------------------------------"
					echo "Number of successful calls are $suc_num , Rebooting Clearwater] "	
					init_clearwater
	   				flush_clearwater_throttle 0					
				fi
			else
				echo "Not Rebooting  CallRate : $callrate Delay : $ind_delay Successful calls : $suc_num"
			fi
			
			
		# skip on the last iteration
	    if (($i < ${iterations} - 1))
		then
		        echo " Iteration $i finished, Waiting for REGISTER timeout : $gsleep seconds"
			
	   		if [ $flush -gt 0 ]
	   		then
	   			if [ $callrate -gt $flush_rate ]
	    			then
					init_clearwater
	   				flush_clearwater_throttle 0
	    			else
					my_sleep $gsleep
				fi
	    		else
				my_sleep $gsleep
			fi
		fi
		

		mv *.log logfiles/
	    done
		
	    printf "$ind_delay," >> $resultfile
			
		awk ' BEGIN {FS=","}
			(NR>1 && $16 > 0){sample_size +=1; target_rate += $6; call_rate += $8; total_calls += $13; suc += $16; failed += $18; }
			END { if (NR > 1) printf("%d,%s,%.2f,%.2f,%.2f,%.2f,%.2f"\
			,sample_size,$5,(target_rate/(sample_size)),(call_rate/(sample_size)),\
			(total_calls/(sample_size)),(suc/(sample_size)),(failed/(sample_size)))}' result$hy$ind_delay$hy$callrate.csv >> $resultfile
			
		printf "\n" >> $resultfile
	     if (($it < ${ratelength}))
	     then
		pkill -9 sipp
		echo "Rate $callrate finished : Waiting for REGISTER timeout : $gsleep seconds"
		my_sleep $gsleep
	     fi
	done
	dos2unix $logfile
	cat $logfile
	cat $logfile >> $dfile
	current_time=$(date "+%Y.%m.%d-%H.%M.%S")
	new_fileName=logfile_$ind_delay_$current_time.txt
	mv $logfile $new_fileName    
	#./sync_dropbox  
}



start_with_delay(){

	delaylength=${#delayarr[@]}
	echo "Delay Length : $delaylength"
	for (( itd=0; itd<${delaylength}; itd++ ));
	do
		init_clearwater
		echo "Inducing Delay : ${delayarr[$itd]}"
		run_delay ${delayarr[$itd]}
		echo "--------------------------"
		
	done
}

ssh username@$hostname screen -d -m cpu.sh
start_dispatcher(){

	echo "starting Dispatcher"
	init_clearwater_d
	run_dispatcher
}

start_with_delay

start_dispatcher

ssh username@$hostname screen -d -m kill_cpu.sh

mv *.err logfiles/

unoconv --format  xls $resultfile
unoconv --format  xls $datafile

ssh username@$hostname screen -d -m  stop_clearwater_d
sleep 5
ssh username@$hostname screen -d -m  stop_clearwater 
echo "Done"
