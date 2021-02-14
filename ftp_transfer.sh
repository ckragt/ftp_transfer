#!/bin/bash

# version:	3
# scripter: 	Christopher Kragt <ck@kragt.pro>
# depencies:	mysql-client (depends on logtype = file or logtype = db)

# environment
spid=$$;basepath=$(pwd);logfile="$basepath/run.dev.log";logdb="$basepath/log.db";lock="$basepath/lock.tmp";uuid=$(uuidgen)
declare -A ftpoption; declare -A journaloption; declare -A diroption

diroption=([local]="/ftpfs/user/test/_empf" [files]="*.csv")

# ftp settings
ftpoption=([mode]="binary" [host]="10.1.1.190" [user]="datax" [pass]="test123" [dir]="/datain")

# journal settings
journaloption=([type]="db" [access]="$basepath/config.sql.conf" [host]="10.1.1.190" [port]="3306" [database]="journal" [table]="ftptrans_test")

# script settings - do not edit below this line


function __log () {
	local logtype=$1
	local logsystem=$2;local loglevel=$3;local logdescription=$4;local logdate=$(date '+%d.%m.%Y');local logtime=$(date '+%H:%M:%S')
	local logformat="%-36s %-1s %-10s %-1s %-8s %-1s %-15s %-1s %-7s %-1s %-45s %-1s\n"

	function __logToFile () {
		if [ ! -f $logfile ]; then
			touch $logfile;chmod 777 $logfile
			printf "$logformat" "UUID" "|" "DATE" "|" "TIME" "|" "SYSTEM" "|" "LEVEL" "|" "DESCRIPTION" "|" >> $logfile
			printf "$logformat" "----" "|" "----" "|" "----" "|" "------" "|" "-----" "|" "-----------" "|" >> $logfile
		fi
		printf "$logformat" "$uuid" "|" "$logdate" "|" "$logtime" "|" "$logsystem" "|" "$loglevel" "|" "$logdescription" "|" >> $logfile
		if grep -q $uuid $logfile; then
			return 0
		else
			return 1
		fi
	}

	function __logToDatabase () {
		mysql --defaults-extra-file=${journaloption[access]} -h ${journaloption[host]} <<-sqlcmd
			USE ${journaloption[database]};
			INSERT INTO ${journaloption[table]} (uuid,date,time,system,level,description) VALUES ('$uuid','$logdate','$logtime','$logsystem','$loglevel','$logdescription');
		sqlcmd
	}

	if [ "$logtype" == "file" ]; then
		__logToFile
	elif [ "$logtype" == "db" ]; then
		#if nc -z -v -w2 ${journaloption[host]} ${journaloption[port]} &> /dev/null; then
		nc -z -v -w2 ${journaloption[host]} ${journaloption[port]} &> /dev/null
		if [ $? = 0 ]; then
			__logToDatabase
		else

			__logToFile
		fi
	fi
}

function __exit () {
	local exitcode=$1
	rm $lock

	if [ -z "$exitcode" ]; then
		unset ftpoption; unset journaloption; unset diroption
		exit 0
	else
		unset ftpoption; unset journaloption; unset diroption
		exit $exitcode
	fi
}

function __run () {
	if [ -z "$(ls -A "${diroption[local]}")" ]; then
		__log "db" "filesystem" "info" "directory is empty"
		__exit 0
	else
		__log "db" "ftp" "info" "filetransfer connection opened"
		ftp -n ${ftpoption[host]} >> /dev/null <<-ftpcmd
			quote USER ${ftpoption[user]}
			quote PASS ${ftpoption[pass]}
			${ftpoption[mode]}
			lcd ${diroption[local]}
			cd ${ftpoption[dir]}
			prompt
			mput ${diroption[files]}
			quit
		ftpcmd
		lastexitcode=$?
		__log "db" "ftp" "info" "filetransfer connection closed"
		__exit 0
	fi
}

if [ ! -f $lock ]; then
	touch $lock;echo "PID: $spid USER: $(whoami)" >> $lock;sleep 1
	__run
else
	__log "db" "Runtime" "error" "lockfile found. script still running? aborting."
	__log "db" "Runtime" "info" "lockfileinfo: $(cat $lock)"
	__exit 1
fi
