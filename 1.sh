# Create Enrolled Node Server List. It is one time process
mkdir -p "/tmp/agent_upgrade"
echo "Check enolled_node_list file exist"

#Exclusion Sever list 
#Any deployment is running skip for next cycle

if [[ -f "/tmp/agent_upgrade/enrolled_node_list.txt" ]]; then
   echo "/tmp/agent_upgrade/enrolled_node_list.txt exists."
else
    #Check upgrade agent in installed in OBM
    upgrade_agent_in_obm=`/opt/HP/BSM/opr/bin/opr-package-manager.sh -rc_file /tmp/tmp_rc -lp | grep -i "12.20.005" | wc -l`
    if [[ $upgrade_agent_in_obm -eq 0 ]]; then
        echo "expect agent 12.20.005 is not present in OBM"
        exit 1
    fi

    #Creating enolled_node_list file
    echo "Creating enolled_node_list file"
    /opt/HP/BSM/opr/bin/opr-node.sh -list_nodes -rc_file /tmp/tmp_rc -ln | egrep "Primary DNS Name|Operating System|OA Version" > /tmp/agent_upgrade/enrolled_node_list.txt

    #Get Agent status of the enrolled nodes
    /opt/HP/BSM/opr/bin/opr-agt -rc_file /tmp/tmp_rc -status -all > /tmp/agent_upgrade/nodes_agent_status.txt

    #Remove Agent error node from enrolled node list 
    for i in `grep -i "383: ERROR" /tmp/agent_upgrade/nodes_agent_status.txt | awk -F ":" '{ print $1 }'`
    do
        echo "Remove from list : $i"
        sed -i.bak -e "/$i/,+2 d" /tmp/agent_upgrade/enrolled_node_list.txt
    done
fi