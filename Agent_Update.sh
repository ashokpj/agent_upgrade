#!/bin/bash

read_config_file()
{
  file="$1"
  while IFS="=" read -r key value; do
    case "$key" in
      "upgrading_os_type")  upgrading_os_type="$value" ;;
      "agent_upgrading_version")   agent_upgrading_version="$value" ;;
      "no_of_nodes_upgrade_parallel") no_of_nodes_upgrade_parallel="$value" ;;
      "exclusion_nodes")   exclusion_nodes="$value" ;;
      "data_path")   data_path="$value" ;;
      "log_path")   log_path="$value" ;;
    esac
  done < "$file"
}

read_config_file ./agent_upgrade_config.cfg

mkdir -p "${data_path}"
mkdir -p "${log_path}"


# Create Enrolled Node Server List. It is one time process
mkdir -p "/tmp/agent_upgrade"
echo "Check enolled_node_list file exist"

#Exclusion Sever list 
#Any deployment is running skip for next cycle

if [[ -f "${data_path}/enrolled_node_list.txt" ]]; then
   echo "${data_path}/enrolled_node_list.txt exists."
else
   rm -rf ${data_path}/master_node_list.txt
   #Check upgrade agent in installed in OBM
   upgrade_agent_in_obm=`/opt/HP/BSM/opr/bin/opr-package-manager.sh -rc_file /tmp/tmp_rc -lp | grep -i "12.20.005" | wc -l`
   if [[ $upgrade_agent_in_obm -eq 0 ]]; then
      echo "expect agent 12.20.005 is not present in OBM"
      exit 1
   fi
   echo "Creating enolled_node_list file"
   /opt/HP/BSM/opr/bin/opr-node.sh -list_nodes -rc_file /tmp/tmp_rc -ln | egrep "Primary DNS Name|Operating System|OA Version" > "${data_path}/enrolled_node_list.txt"

   while read Primary_DNS_Name; read Operating_System; read OA_Version
   do
      OA_Version=`echo "$OA_Version" | awk -F "=" '{ print $2}' | awk '{$1=$1};1'`
      Primary_DNS_Name=`echo "$Primary_DNS_Name" | awk -F "=" '{ print $2}' | awk '{$1=$1};1'`
      Operating_System=`echo "$Operating_System" | awk -F "=" '{ print $2}' | awk '{$1=$1};1'`

      if [[ $OA_Version != "12.20.005" ]]; then
         echo "$Primary_DNS_Name" 
         echo "$Operating_System" 
         echo "$OA_Version"
         echo "$Primary_DNS_Name|$Operating_System|$OA_Version" >> "${data_path}/master_node_list.txt"
      fi
   done <  "${data_path}/enrolled_node_list.txt"
fi

exit 100



#Check Failed Job count if it is more then 10 then exit from Script
Failed_Job_Count=`/opt/HP/BSM/opr/bin/opr-jobs -rc_file /tmp/tmp_rc  -list failed | wc -l`
echo "Failed_Job_Count:$Failed_Job_Count"
if [[ $Failed_Job_Count -gt 15 ]]; then
   echo "Agent Upgrade is Stopped. Because already $Failed_Job_Count deployment Jobs failed or Retry. Fix it first"
   exit 3
fi

#Declare variable i and J for array index
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
      if [[ $? != 0 ]] ; then
         # Add in remove list
         remove_list[$j]="$Primary_DNS_Name"
         j=`expr $j + 1`
         continue
      fi

      # Check required Space in node end
      if [[ $Operating_System =~ ^Linux.* ]]; then
         echo "Linux : $Primary_DNS_Name"
         #/opt/OV/bin/ovdeploy -ovrg server -cmd 'df -k /opt/OV /opt/perf /var/opt/OV'  -host ilg01gtcrh701.pdxc-dev.pdxc.com  | awk 'NR !=1 {print "\t"($2/1024 "MB")"\t\t",$0}'
         opt_size=`/opt/OV/bin/ovdeploy -ovrg server -cmd 'df -m /opt' -host $Primary_DNS_Name | awk 'NR !=1 {print $4 }'`
         var_opt=`/opt/OV/bin/ovdeploy -ovrg server -cmd 'df -m /var/opt/OV' -host $Primary_DNS_Name | awk 'NR !=1 {print $4 }'`
      elif [[ $Operating_System =~ ^Windows.*  ]]; then
         echo "Windows : $Primary_DNS_Name"
         c_drive=`/opt/OV/bin/ovdeploy -ovrg server -cmd 'fsutil volume diskfree c:'  -host ilg01edgxw1904.pdxc-dev.pdxc.com | awk -F ":" '/avail free/{ print $2 }' | awk '{ print $1/1000000 }'`
         echo "Less $Primary_DNS_Name c_drive is $c_drive"
      else
         echo "OS type Currently not support my $0 script"
         continue
      fi

      if [[ $opt_size -lt 150 || $var_opt -lt 150 || $c_drive -lt 150 ]]; then
         echo "Less $Primary_DNS_Name opt_size is $opt_size"
         echo "Less $Primary_DNS_Name var_opt is $var_opt"
         echo "Less $Primary_DNS_Name var_opt is $c_drive"
         # Add in remove list
         remove_list[$j]="$Primary_DNS_Name"
         j=`expr $j + 1`
         continue
      else
         #agent_upgrade[$i]="$Primary_DNS_Name|$Operating_System|$OA_Version"
         agent_upgrade[$i]="$Primary_DNS_Name"
         i=`expr $i + 1`
      fi  

      # Number of server to agent upgrade it each then break the loop
      if [[ "${#agent_upgrade[@]}" -ge "13" ]]; then
         echo "Array values : ${agent_upgrade[@]}"
         break
      fi

   else
         continue        
   fi
done <  /tmp/agent_upgrade/enrolled_node_list.txt

#LOOP remove agent detail from list Which have issue
echo "Value in remove list: ${remove_list[@]}"
echo "Value in agent update list : ${agent_upgrade[@]}"

#Pre-request not meet in following server.
for i in "${remove_list[@]}"
do
   echo "$i"  >> /tmp/agent_upgrade/prerequest_issue.txt
done

# Remove servers name from enrollement list
for i in "${remove_list[@]}" "${agent_upgrade[@]}"
do
   echo "Remove from list : $i"
   sed -i.bak -e "/$i/,+2 d" /tmp/agent_upgrade/enrolled_node_list.txt
done

echo "Good Day Well Done"
echo "Have Nice Day Ashok"