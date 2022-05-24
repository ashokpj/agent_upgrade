Operating_System="Linux Red Hat 7.9 3.10.0"
if [[ $Operating_System =~ ^Linux.* ]]; then
    echo "Linux"
elif [[ $Operating_System =~ ^Windows.*  ]]; then
    echo "Windows"
fi