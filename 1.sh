i=0
while read Primary_DNS_Name; read Operating_System; read OA_Version
do
    OA_Version=`echo "$OA_Version" | awk -F "=" '{ print $2}' | awk '{$1=$1};1'`
    Primary_DNS_Name=`echo "$Primary_DNS_Name" | awk -F "=" '{ print $2}' | awk '{$1=$1};1'`
    Operating_System=`echo "$Operating_System" | awk -F "=" '{ print $2}' | awk '{$1=$1};1'`
    if [[ $OA_Version != "12.20.005" ]]; then
        echo "$Primary_DNS_Name" 
        echo "$Operating_System" 
        echo "$OA_Version" 
        
        /opt/OV/bin/bbcutil -ping $Primary_DNS_Name &> /dev/null
        if [[ $? == 0 ]] ; then
           agent_upgrade[$i]="$Primary_DNS_Name|$Operating_System|$OA_Version"
           i=`expr $i + 1`
        fi
        
        if [[ ${#agent_upgrade[@]} >= 3 ]]; then
            echo "Array values : ${agent_upgrade[@]}"
            break
        fi

    else
        continue        
    fi
done <  /tmp/agent_upgrade/enrolled_node_list.txt


