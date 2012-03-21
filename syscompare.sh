#!/bin/bash
#==============================================================================
# Syscompare
#
# This script compares files from two different sources and detects differences
# between them. Its purpose is to help detect and troubleshoot inconsistent
# system behaviour and help detect modified binaries and libraries.
#
# Notes:
# The script supports remote checking of hosts using ssh, but password auth is
# not supported. A SSH key must be set up when using remote checking. Also,
# this will GREATLY increase the time needed for verification. If possible
# mount the remote host(s) locally using NFS, sshfs or smbfs.
#
# Author: Diego Alencar Alves de Lima <diego.lima@4linux.com.br>
#==============================================================================

SOURCE=(/lib /usr /bin /sbin /var/lib)
TARGET=(/mnt/lib /mnt/usr /mnt/bin /mnt/sbin /mnt/var/lib)

LOGFILE=/tmp/syscompare

# Source Host user and password
LUSER=""
LHOST=""
LDISTRO="debian"
LPKGFILE="/tmp/syscompare-pkg-local.txt"

# Target Host user and password
TUSER="lima"
THOST="192.168.0.141"
TDISTRO="debian"
TPKGFILE="/tmp/syscompare-pkg-remote.txt"

NSOURCE=${#SOURCE[@]}
NTARGET=${#TARGET[@]}

if ! [ $NSOURCE = $NTARGET ]; then 
	echo "The number or sources and targets must be the same"
	exit 1
fi

echo "" >> $LOGFILE
echo "START - `date +%Y%m%d%H%M%S`" >> $LOGFILE

if [ "$LDISTRO" = "$TDISTRO" ]; then
	if [ "$LDISTRO" = "debian" ]; then
		CMD="dpkg -l"
	elif [ "$LDISTRO" = "rh" ]; then
		CMD="rpm -qa"
	else
		echo "Unsupported distribution. Skipping native package manager check" >> $LOGFILE
		CMD=""
	fi

	if [ "$CMD" ]; then
		$CMD 		       > $LPKGFILE
		ssh $TUSER@$THOST $CMD > $TPKGFILE
		diff $LPKGFILE $TPKGFILE &>/dev/null || echo "DIFF - package list" >> $LOGFILE
	fi
fi

for((i=0;i<$NSOURCE;i++)); do
	echo Comparing files in ${SOURCE[$i]} and ${TARGET[$i]}	
	for file in `find ${SOURCE[$i]} -type f`; do

		if [ "`echo ${SOURCE[$i]}|cut -c-3`" = "SSH" ]; then
			echo "Remote Source"
			lcmd="ssh $LUSER@$LHOST"
			file="`echo $file|cut -f2- -d:`"
		else
			lcmd=""
		fi
		#TODO: Remote sync using SSH is very expensive. Redesign this using a single connection.
		if [ "`echo ${TARGET[$i]}|cut -c-3`" = "SSH" ]; then
			echo "Remote target: $file"
			tcmd="ssh $TUSER@$THOST"
		else
			tcmd=""
		fi


		tfile=`echo $file|sed "s|${SOURCE[$i]}|$(echo ${TARGET[$i]}|cut -f2- -d:)|g"`
		SSIZE=`${lcmd} ls -l $file|awk '{print $5}'`
		TSIZE=`${tcmd} ls -l $tfile 2>/dev/null|awk '{print $5}'`
		if [ "x${TSIZE}" != "x" ]; then
			if [ $SSIZE != $TSIZE ]; then
				echo "DIFF - size - $file || $tfile" >> $LOGFILE
			else
				#File sizes match. Do a more expensive md5 sum check
				SMD5=`${lcmd} md5sum $file|cut -f1 -d" "`
				TMD5=`${tcmd} md5sum $tfile|cut -f1 -d" "`
				if [ "$SMD5" != "$TMD5" ]; then
					echo "DIFF - md5 - $file || $tfile" >> $LOGFILE
				else
					#MD5 match. Do a more expensive sha1 sum check
					SSHA=`${lcmd} sha1sum $file|cut -f1 -d" "`
					TSHA=`${tcmd} sha1sum $tfile|cut -f1 -d" "`
					if [ "$SSHA" != "$TSHA" ]; then
						echo "DIFF - sha - $file || $tfile" >> $LOGFILE
					else
						echo "Match: $file || $tfile" >> $LOGFILE
					fi
				fi
			fi
		else
			# File doesn't exist at target
			echo "FDE @ target - $tfile" >> $LOGFILE
		fi
	done
done

echo "FINISH - `date +%Y%m%d%H%M%S`" >> $LOGFILE
echo "Cleaning up files..."
tar -cvzf /tmp/syscompare-results.tar.gz $LOGFILE $LPKGFILE $TPKGFILE
rm $LOGFILE $LPKGFILE $TPKGFILE
echo "Cleanup done"
