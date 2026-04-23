#!/bin/bash

# MOnitor free space in disk
FU=$(df -H | egrep -v "Filesystem|tmpfs" | grep "sda2" | awk '{print $5}' | tr -d %)
TO="your_mail@gmail.com"

# Send alert to mail if disk space is low!
# For sending mail we nned to setup postfix in our server or machine

if [[ $FU -ge 20 ]]
then
	echo "Warning, disk space is low - $FU %" | mail -s "DISK SPACE ALERT IN SERVER" $TO
else
	echo "All Good"
fi

