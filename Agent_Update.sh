#!/bin/bash

# Create Enrolled Node Server List. It is one time process
mkdir -p "/tmp/agent_upgrade"
echo "Check enolled_node_list file exist"
if [[ -f "/tmp/agent_upgrade/enrolled_node_list.txt" ]]; then
   echo "/tmp/agent_upgrade/enrolled_node_list.txt exists."
else
   echo "Creating enolled_node_list file"
   /opt/HP/BSM/opr/bin/opr-node.sh -list_nodes -rc_file /tmp/tmp_rc -ln | egrep "Primary DNS Name|Operating System|OA Version" > /tmp/agent_upgrade/enrolled_node_list.txt
fi

#Check Failed Job count if it is more then 10 then exit from Script
Failed_Job_Count=`/opt/HP/BSM/opr/bin/opr-jobs -rc_file /tmp/tmp_rc  -list failed | wc -l`
echo "Failed_Job_Count:$Failed_Job_Count"
if [[ $Failed_Job_Count -gt 15 ]]; then
   echo "Agent Upgrade is Stopped. Because already $Failed_Job_Count deployment Jobs failed or Retry. Fix it first"
   exit 3
fi

i=0
j=0
while read Primary_DNS_Name; read Operating_System; read OA_Version
do
    OA_Version=`echo "$OA_Version" | awk -F "=" '{ print $2}' | awk '{$1=$1};1'`
    Primary_DNS_Name=`echo "$Primary_DNS_Name" | awk -F "=" '{ print $2}' | awk '{$1=$1};1'`
    Operating_System=`echo "$Operating_System" | awk -F "=" '{ print $2}' | awk '{$1=$1};1'`

    if [[ $OA_Version != "12.20.005" ]]; then
        echo "$Primary_DNS_Name" 
        echo "$Operating_System" 
        echo "$OA_Version" 
        
        #Check Connection between OBM Server and Node
        /opt/OV/bin/bbcutil -ping $Primary_DNS_Name &> /dev/null
        if [[ $? == 0 ]] ; then
           agent_upgrade[$i]="$Primary_DNS_Name|$Operating_System|$OA_Version"
           i=`expr $i + 1`
        else
           # Add in remove list
           echo "Remove $Primary_DNS_Name from Enrolled node list file"
           remove_list[$j]="$Primary_DNS_Name"
           j=`expr $j + 1`
           #sed -e '/$Primary_DNS_Name/,+2 d'
        fi 
        
        if [[ "${#agent_upgrade[@]}" -ge "13" ]]; then
            echo "Array values : ${agent_upgrade[@]}"
            break
        fi

    else
        continue        
    fi
done <  /tmp/agent_upgrade/enrolled_node_list.txt

#LOOP remove agent detail from list Which have issue
echo "Welcome"
echo "Value in remove list: ${remove_list[@]}"
echo "Value in agent update list : ${agent_upgrade[@]}"
echo "ASHOK"

for i in "${remove_list[@]}"
do
   echo "Remove from list : $i"
   #sed "/$i/,+2 d" /tmp/agent_upgrade/enrolled_node_list.txt  &> /dev/null
   sed -i.bak -e "/$i/,+2 d" /tmp/agent_upgrade/enrolled_node_list.txt
done

echo "Good Day Well Done"
echo "Have Nice Day Ashok"