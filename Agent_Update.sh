#!/bin/bash

read_config_file()
{
  file="$1"
  while IFS="=" read -r key value; do
    case "$key" in
      "agent_upgrading_version")   agent_upgrading_version="$value" ;;
      "no_of_nodes_upgrade_parallel") no_of_nodes_upgrade_parallel="$value" ;;
      "exclusion_nodes")   exclusion_nodes="$value" ;;
      "data_path")   data_path="$value" ;;
      "log_path")   log_path="$value" ;;
      "stop_upgrade_if_failed_count")  stop_upgrade_if_failed_count="$value" ;;
    esac
  done < "$file"
}

logstart() 
{   
   echo "================================================================"| tee -a "${log_path}"/agent_upgrade.log
   echo "[`date`] - Starting Cycle " | tee -a "${log_path}"/agent_upgrade.log
   echo "[`date`] - ${*}" | tee -a "${log_path}"/agent_upgrade.log
   echo "================================================================"| tee -a "${log_path}"/agent_upgrade.log
}

logit() 
{   
   echo "[`date`] - ${*}" | tee -a "${log_path}"/agent_upgrade.log
}

logend() 
{
   echo "================================================================"| tee -a "${log_path}"/agent_upgrade.log
   echo "[`date`] - ${*}" | tee -a "${log_path}"/agent_upgrade.log
   echo "[`date`] - Ending Cycle " | tee -a "${log_path}"/agent_upgrade.log
   echo "================================================================"| tee -a "${log_path}"/agent_upgrade.log
   echo " " | tee -a "${log_path}"/agent_upgrade.log
}
#=========================================================================================================================
# Read Configuration and set variable Value
# Create data directory and log directory
#=========================================================================================================================
read_config_file ./agent_upgrade_config.cfg
mkdir -p "${data_path}"
mkdir -p "${log_path}"
logstart "Starting"
logit "Created data and log directory"
logit "Readed configuration file"

#=========================================================================================================================
# Set OBM username and Password
#=========================================================================================================================
if [[ ! -f /tmp/tmp_rc ]]; then
   logit "Enter OBM application credential" 
   printf "OBM Username: "
   read USERNAME
   stty -echo
   printf "OBM assword: "
   read PASSWORD
   stty echo
   printf "\n"
   sudo /opt/HP/BSM/opr/bin/opr-node.sh -rc_file /tmp/tmp_rc -set_rc username="$USERNAME";
   sudo /opt/HP/BSM/opr/bin/opr-node.sh -rc_file /tmp/tmp_rc -set_rc password="$PASSWORD";
fi

#=========================================================================================================================
# Check master_node_list.txt exist in data_path else craete it
#=========================================================================================================================
logit "Check enolled_node_list file exist"
if [[ -f "${data_path}/enrolled_node_list.txt" ]]; then
   logit "enrolled_node_list.txt file is exists in data directory."
   logit "Start Agent upgrading"
else
   logit "enolled_node_list file is not found"
   logit "Creating Master node list"
   rm -rf ${data_path}/master_node_list.txt

   #=========================================================================================================================
   #1. Check upgrade agent version is installed in OBM Server. if upgrade agent is not installed then exit
   #=========================================================================================================================
   logit "Step 1: Check upgrade agent [ ${agent_upgrading_version} ] is installed in OBM server "
   upgrade_agent_in_obm=`/opt/HP/BSM/opr/bin/opr-package-manager.sh -rc_file /tmp/tmp_rc -lp | grep -i "${agent_upgrading_version}" | wc -l`
   if [[ $upgrade_agent_in_obm -eq 0 ]]; then
      logend "Expected agent ${agent_upgrading_version} is not present in OBM"
      exit 0
   fi

   #=========================================================================================================================
   #2. Get OBM Enrolled node list
   #=========================================================================================================================
   logit "Step 2: Creating enolled_node_list file"
   /opt/HP/BSM/opr/bin/opr-node.sh -list_nodes -rc_file /tmp/tmp_rc -ln | egrep "Primary DNS Name|Operating System|OA Version" > "${data_path}/enrolled_node_list.txt"

   while read Primary_DNS_Name; read Operating_System; read OA_Version
   do
      OA_Version=`echo "$OA_Version" | awk -F "=" '{ print $2 }' | awk '{$1=$1};1'`
      Primary_DNS_Name=`echo "$Primary_DNS_Name" | awk -F "=" '{ print $2 }' | awk '{$1=$1};1'`
      Operating_System=`echo "$Operating_System" | awk -F "=" '{ print $2 }' | awk '{$1=$1};1'`

      if [[ $OA_Version != "${agent_upgrading_version}" ]]; then
         echo "$Primary_DNS_Name|$Operating_System|$OA_Version" >> "${data_path}/master_node_list.txt"
      fi
   done <  "${data_path}/enrolled_node_list.txt"

   cp "${data_path}/master_node_list.txt" "${data_path}/m_be_master_node_list.txt"
   
   #=========================================================================================================================
   #3. Remove node from Master node list which has mentioned in exclusion list in configuration file
   #=========================================================================================================================
   logit "Step 3: Remove node from Master list which has mentioned in exclusion list in config file"
   for i in $(echo $exclusion_nodes | sed "s/,/ /g")
   do
      #sed -i.bak -e "/$i/,+2 d" "${data_path}/master_node_list.txt"
      sed -i.bak -e "/$i/d" "${data_path}/master_node_list.txt"
   done

   cp "${data_path}/master_node_list.txt" "${data_path}/m_ae_master_node_list.txt"

   #=========================================================================================================================
   #4. Get Agent status of the enrolled nodes and remove node from master list if agent have any error or not running status.
   #=========================================================================================================================
   logit "Step 4: Get Agent status of the enrolled nodes"
   /opt/HP/BSM/opr/bin/opr-agt -rc_file /tmp/tmp_rc -status -all > ${data_path}/nodes_agent_status.txt

   logit "Step 5: Remove Agent error node from enrolled node list "
   for i in `grep -i "383: ERROR" ${data_path}/nodes_agent_status.txt | awk -F ":" '{ print $1 }'`
   do
      #echo "Remove from list : $i"
      #sed -i.bak -e "/$i/,+2 d" "${data_path}/master_node_list.txt"
      sed -i.bak -e "/$i/d" "${data_path}/master_node_list.txt"
   done
   logend "Ending Master node list creation Cycle"
   exit 0
fi

#=========================================================================================================================
# Step 1: Exit if Failed Job count is more then configured value
#=========================================================================================================================

logit "Step 1: Exit if Failed Job count is more then configured value"
Failed_Job_Count=`/opt/HP/BSM/opr/bin/opr-jobs -rc_file /tmp/tmp_rc  -list failed | wc -l`
logit "Failed_Job_Count: ${Failed_Job_Count}"
logit "Deployment job failed count: ${stop_upgrade_if_failed_count}"

if [[ $Failed_Job_Count -gt ${stop_upgrade_if_failed_count} ]]; then
   logit "Agent Upgrade is Stopped. Because already $Failed_Job_Count deployment Jobs failed or Retry."
   exit 3
fi



#=========================================================================================================================
# Looping master node list
#=========================================================================================================================

#Declare variable i and J for array index
i=0
j=0
logit "looping master node list records"
while read Record
do
   Primary_DNS_Name=`echo "$Record" | awk -F "|" '{ print $1}' | awk '{$1=$1};1'`
   Operating_System=`echo "$Record" | awk -F "|" '{ print $2}' | awk '{$1=$1};1'`
   OA_Version=`echo "$Record" | awk -F "|" '{ print $3}' | awk '{$1=$1};1'`

   #=========================================================================================================================
   # Step 2: Check Connection between OBM Server and Node
   #=========================================================================================================================
   /opt/OV/bin/bbcutil -ping $Primary_DNS_Name &> /dev/null
   if [[ $? != 0 ]] ; then
      # Add in remove list
      logit "bbcutil ping failed : $Primary_DNS_Name"
      remove_list[$j]="$Primary_DNS_Name"
      j=`expr $j + 1`
      continue
   fi

   #=========================================================================================================================
   # Step 3: Check required Space in node end
   #=========================================================================================================================
   if [[ $Operating_System =~ ^Linux.* ]]; then
      #/opt/OV/bin/ovdeploy -ovrg server -cmd 'df -k /opt/OV /opt/perf /var/opt/OV'  -host ilg01gtcrh701.pdxc-dev.pdxc.com  | awk 'NR !=1 {print "\t"($2/1024 "MB")"\t\t",$0}'
      opt_size=`/opt/OV/bin/ovdeploy -ovrg server -cmd 'df -m /opt' -host $Primary_DNS_Name | awk 'NR !=1 {print $4 }'`
      var_opt=`/opt/OV/bin/ovdeploy -ovrg server -cmd 'df -m /var/opt/OV' -host $Primary_DNS_Name | awk 'NR !=1 {print $4 }'`
   elif [[ $Operating_System =~ ^Windows.*  ]]; then
      c_drive=`/opt/OV/bin/ovdeploy -ovrg server -cmd 'fsutil volume diskfree c:'  -host $Operating_System | awk -F ":" '/avail free/{ print $2 }' | awk '{ print $1/1000000 }'`
      #echo "Less $Primary_DNS_Name c_drive is $c_drive"
   else
      echo "OS type Currently not support my $0 script"
      continue
   fi

   if [[ $opt_size -lt 150 || $var_opt -lt 150 || $c_drive -lt 150 ]]; then
      logit "Less $Primary_DNS_Name opt_size is $opt_size"
      logit "Less $Primary_DNS_Name var_opt is $var_opt"
      logit "Less $Primary_DNS_Name var_opt is $c_drive"
      # Add in remove list
      remove_list[$j]="$Primary_DNS_Name"
      j=`expr $j + 1`
      continue
   else
      #agent_upgrade[$i]="$Primary_DNS_Name|$Operating_System|$OA_Version"
      agent_upgrade[$i]="$Primary_DNS_Name"
      i=`expr $i + 1`
   fi  
   #=========================================================================================================================
   # Step 4: Number of server to agent upgrade it each then break the loop
   #=========================================================================================================================
   if [[ "${#agent_upgrade[@]}" -ge "${no_of_nodes_upgrade_parallel}" ]]; then
      logit "agent_upgrade array values : ${agent_upgrade[@]}"
      break
   fi

done <  "${data_path}/master_node_list.txt"

#=========================================================================================================================
# Step 4: Number of server to agent upgrade it each then break the loop
#=========================================================================================================================
#LOOP remove agent detail from list Which have issue
logit "Value in remove list: ${remove_list[@]}"
logit "Value in agent update list : ${agent_upgrade[@]}"

#=========================================================================================================================
# Step 5: Agent upgrade process
#=========================================================================================================================
logit "Agent upgrading......"
lst=$( IFS=','; echo "${agent_upgrade[*]}" ); echo $lst
echo sudo /opt/HP/BSM/opr/bin/opr-package-manager.sh -username admin -deploy_package Operations-agent -deploy_mode VERSION -package_ID 12.20.005 -node_list "$lst"

#=========================================================================================================================
# Step 6: Pre-request not meet in following server. log it in prerequest_issue.txt
#=========================================================================================================================
#Pre-request not meet in following server.
for i in "${remove_list[@]}"
do
   echo "$i"  >> ${data_path}/prerequest_issue.txt
   echo "write immeditatly"
done


#=========================================================================================================================
# Step 7: Remove servers name from master_node_list.txt
#=========================================================================================================================
# Remove servers name from enrollement list
for i in "${remove_list[@]}" "${agent_upgrade[@]}"
do
   logit "Remove from master node list : $i"
   #sed -i.bak -e "/$i/,+2 d" ${data_path}/master_node_list.txt
   sed -i.bak -e "/$i/d" ${data_path}/master_node_list.txt
done

exit 0
