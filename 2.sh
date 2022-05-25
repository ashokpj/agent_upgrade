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

echo "After"
echo "OS = $upgrading_os_type"
echo "Agent = $agent_upgrading_version"
echo "no_of_nodes_upgrade_parallel = $no_of_nodes_upgrade_parallel"
echo "exclusion_nodes = $exclusion_nodes"
echo "data_path = $data_path"
echo "log_path = $log_path"

