#!/bin/sh
# posixLibrary.sh
#!/bin/sh


#------------------------------------------------------------------------
# Adds parameter to $PATH if it's missing in it

Add2Path() {
	Dir=${1}
	x=`echo :${PATH}: | grep :$Dir:`
	if [ -z "$x" ]
	then
		PATH=$PATH:$Dir
		export PATH
	fi
}

#------------------------------------------------------------------------
# Global stuff init

Answer=""
OrigPasswd=""
TmpFile=""
FBRootDir=/opt/firebird
export FBRootDir
FBBin=$FBRootDir/bin
export FBBin
SecurityDatabase=security2.fdb
ArchiveDateTag=`date +"%Y%m%d_%H%M"`
export ArchiveDateTag
ArchiveMainFile="${FBRootDir}_${ArchiveDateTag}"
export ArchiveMainFile
#this solves a problem with sudo env missing sbin
Add2Path /usr/sbin
Add2Path /sbin

#------------------------------------------------------------------------
# Create temporary file. In case mktemp failed, do something...

MakeTemp() {
	TmpFile=`mktemp $mktOptions /tmp/firebird_install.XXXXXX`
	if [ $? -ne 0 ]
	then
		TmpFile=/tmp/firebird_install
		touch $TmpFile
	fi
}

#------------------------------------------------------------------------
# Prompt for response, store result in Answer

AskQuestion() {
    Test=$1
    DefaultAns=$2
    echo -n "${1}"
    Answer="$DefaultAns"
    read Answer

    if [ -z "$Answer" ]
    then
        Answer="$DefaultAns"
    fi
}


#------------------------------------------------------------------------
# Prompt for yes or no answer - returns non-zero for no

AskYNQuestion() {
    while echo -n "${*} (y/n): "
    do
        read answer rest
        case $answer in
        [yY]*)
            return 0
            ;;
        [nN]*)
            return 1
            ;;
        *)
            echo "Please answer y or n"
            ;;
        esac
    done
}


#------------------------------------------------------------------------
# Run $1. If exit status is not zero, show output to user.

runSilent() {
	MakeTemp
	$1 >$TmpFile 2>&1
	if [ $? -ne 0 ]
	then
		cat $TmpFile
		echo ""
		rm -f $TmpFile
		return 1
	fi
	rm -f $TmpFile
	return 0
}


#------------------------------------------------------------------------
# Check for a user, running install, to be root

checkRootUser() {

    if [ "`whoami`" != "root" ];
      then
        echo ""
        echo "--- Stop ----------------------------------------------"
        echo ""
        echo "    You need to be 'root' user to do this change"
        echo ""
        exit 1
    fi
}

#alias
checkInstallUser() {
	checkRootUser
}


#------------------------------------------------------------------------
#  resetInetdServer
#  Works for both inetd and xinetd

resetInetdServer() {
	pid=`ps -ef$psOptions | grep inetd | grep -v grep | awk '{print $2}'`
    if [ "$pid" ]
    then
        kill -HUP $pid
    fi
}


#------------------------------------------------------------------------
# remove the xinetd config file(s)
# take into account possible pre-firebird xinetd services

removeXinetdEntry() {
	for i in `grep -l "service gds_db" /etc/xinetd.d/*`
	do
        rm -f $i
    done
}


#------------------------------------------------------------------------
# remove the line from inetd file

removeInetdEntry() {
    FileName=/etc/inetd.conf
    oldLine=`grep "^gds_db" $FileName`
    removeLineFromFile "$FileName" "$oldLine"
}


#------------------------------------------------------------------------
#  Remove (x)inetd service entry and restart the service.
#  Check to see if we have xinetd installed or plain inetd.  
#  Install differs for each of them.

removeInetdServiceEntry() {
    if [ -d /etc/xinetd.d ] 
    then
        removeXinetdEntry
    elif [ -f /etc/inetd.conf ]
	then
        removeInetdEntry
    fi

    # make [x]inetd reload configuration
	resetInetdServer
}


#------------------------------------------------------------------------
#  check if it is running

checkIfServerRunning() {

    stopSuperServerIfRunning

# Check is server is being actively used.

    checkString=`ps -ef$psOptions | egrep "\b(fbserver|fbguard)\b" |grep -v grep`

    if [ ! -z "$checkString" ]
    then
        echo "An instance of the Firebird Super server seems to be running."
        echo "Please quit all Firebird applications and then proceed."
        exit 1
    fi

    checkString=`ps -ef$psOptions | egrep "\b(fb_inet_server|gds_pipe)\b" |grep -v grep`

    if [ ! -z "$checkString" ]
    then
        echo "An instance of the Firebird Classic server seems to be running."
        echo "Please quit all Firebird applications and then proceed."
        exit 1
    fi


# The following check for running interbase or firebird 1.0 servers.

    checkString=`ps -ef$psOptions | egrep "\b(ibserver|ibguard)\b" |grep -v grep`

    if [ ! -z "$checkString" ] 
    then
        echo "An instance of the Firebird/InterBase Super server seems to be running." 
        echo "(the ibserver or ibguard process was detected running on your system)"
        echo "Please quit all Firebird applications and then proceed."
        exit 1 
    fi

    checkString=`ps -ef$psOptions | egrep "\b(gds_inet_server|gds_pipe)\b" |grep -v grep`

    if [ ! -z "$checkString" ] 
    then
        echo "An instance of the Firebird/InterBase Classic server seems to be running." 
        echo "(the gds_inet_server or gds_pipe process was detected running on your system)"
        echo "Please quit all Firebird applications and then proceed." 
        exit 1 
    fi

	removeInetdServiceEntry
	
# Stop lock manager if it is the only thing running.

    for i in `ps -ef$psOptions | grep "fb_lock_mgr" | grep -v "grep" | awk '{print $2}' `
	do
        kill $i
	done

}


#------------------------------------------------------------------------
#  ask user to enter CORRECT original DBA password

askForOrigDBAPassword() {
    OrigPasswd=""
    while [ -z "$OrigPasswd" ]
    do
        AskQuestion "Please enter current password for SYSDBA user: "
        OrigPasswd=$Answer
        if ! runSilent "$FBBin/gsec -user sysdba -password $OrigPasswd -di"
		then
			OrigPasswd=""
		fi
	done
}


#------------------------------------------------------------------------
#  Modify DBA password to value, asked from user. 
#  $1 may be set to original DBA password
#  !! This routine is interactive !!

askUserForNewDBAPassword() {

	if [ -z $1 ]
	then
		askForOrigDBAPassword
	else
		OrigPasswd=$1
	fi

    NewPasswd=""
    while [ -z "$NewPasswd" ]
    do
        AskQuestion "Please enter new password for SYSDBA user: "
        NewPasswd=$Answer
        if [ ! -z "$NewPasswd" ]
        then
            if ! runSilent "$FBBin/gsec -user sysdba -password $OrigPasswd -modify sysdba -pw $NewPasswd"
            then
				NewPasswd=""
			fi
		fi
	done
}


#------------------------------------------------------------------------
# add a line in the (usually) /etc/services or /etc/inetd.conf file
# Here there are three cases, not found         => add
#                             found & different => replace
#                             found & same      => do nothing
#                             

replaceLineInFile() {
    FileName="$1"
    newLine="$2"
    oldLine=`grep "$3" $FileName`

    if [ -z "$oldLine" ] 
      then
        echo "$newLine" >> "$FileName"
    elif [ "$oldLine" != "$newLine"  ]
      then
		MakeTemp
        grep -v "$oldLine" "$FileName" > "$TmpFile"
        echo "$newLine" >> $TmpFile
        cp $TmpFile $FileName && rm -f $TmpFile
        echo "Updated $1"
    fi
}


#------------------------------------------------------------------------
# "edit" file $1 - replace line starting from $2 with $3
# This should stop ed/ex/vim/"what else editor" battle.
# I hope awk is present in any posix system? AP.

editFile() {
    FileName=$1
    Starting=$2
    NewLine=$3
	
	AwkProgram="(/^$Starting.*/ || \$1 == \"$Starting\") {\$0=\"$NewLine\"} {print \$0}"
	MakeTemp
	awk "$AwkProgram" <$FileName >$TmpFile && mv $TmpFile $FileName || rm -f $TmpFile
}


#------------------------------------------------------------------------
# remove line from config file if it exists in it.

removeLineFromFile() {
    FileName=$1
    oldLine=$2

    if [ ! -z "$oldLine" ] 
    then
        cat $FileName | grep -v "$oldLine" > ${FileName}.tmp
        cp ${FileName}.tmp $FileName && rm -f ${FileName}.tmp
    fi
}


#------------------------------------------------------------------------
# Write new password to the /opt/firebird/SYSDBA.password file

writeNewPassword() {
    NewPasswd=$1
	DBAPasswordFile=$FBRootDir/SYSDBA.password

	cat <<EOT >$DBAPasswordFile
# Firebird generated password for user SYSDBA is:

ISC_USER=sysdba
ISC_PASSWD=$NewPasswd

EOT

    if [ $NewPasswd = "masterkey" ]
    then
        echo "# for install on `hostname` at time `date`" >> $DBAPasswordFile
        echo "# You should change this password at the earliest oportunity" >> $DBAPasswordFile
    else 
        echo "# generated on `hostname` at time `date`" >> $DBAPasswordFile
    fi
	
	cat <<EOT >>$DBAPasswordFile

# Your password can be changed to a more suitable one using the
# /opt/firebird/bin/changeDBAPassword.sh script
EOT

    chmod u=r,go= $DBAPasswordFile


    # Only if we have changed the password from the default do we need
    # to update the entry in the database

    if [ $NewPasswd != "masterkey" ]
    then
        runSilent "$FBBin/gsec -user sysdba -password masterkey -modify sysdba -pw $NewPasswd"
    fi
}


#------------------------------------------------------------------------
#  Generate new sysdba password - this routine is used only in the 
#  rpm file not in the install script.

generateNewDBAPassword() {
    # openssl generates random data.
	openssl </dev/null >/dev/null 2&>/dev/null
    if [ $? -eq 0 ]
    then
        # We generate 20 random chars, strip any '/''s and get the first 8
        NewPasswd=`openssl rand -base64 20 | tr -d '/' | cut -c1-8`
    fi

    # mkpasswd is a bit of a hassle, but check to see if it's there
    if [ -z "$NewPasswd" ]
    then
        if [ -f /usr/bin/mkpasswd ]
        then
            NewPasswd=`/usr/bin/mkpasswd -l 8`
        fi
    fi

	# On some systems the mkpasswd program doesn't appear and on others
	# there is another mkpasswd which does a different operation.  So if
	# the specific one isn't available then keep the original password.
    if [ -z "$NewPasswd" ]
    then
        NewPasswd="masterkey"
    fi

    writeNewPassword $NewPasswd
}


#------------------------------------------------------------------------
#  Change sysdba password.

changeDBAPassword() {
    if [ -z "$InteractiveInstall" ]
      then
        generateNewDBAPassword
      else
        askUserForNewDBAPassword masterkey
    fi
}


#------------------------------------------------------------------------
#  buildUninstallFile
#  This will work only for the .tar.gz install and it builds an
#  uninstall shell script.  The RPM system, if present, takes care of it's own.

buildUninstallFile() {
    cd "$origDir"

    if [ ! -f manifest.txt ]  # Only exists if we are a .tar.gz install
    then
        return
    fi

    cp manifest.txt $FBRootDir/misc

    cp -r scripts $FBRootDir/misc/
	[ -f scripts/tarMainUninstall.sh ] && cp scripts/tarMainUninstall.sh $FBRootDir/bin/uninstall.sh
	[ -f scripts/tarmainUninstall.sh ] && cp scripts/tarmainUninstall.sh $FBRootDir/bin/uninstall.sh
	[ -f $FBRootDir/bin/uninstall.sh ] && chmod u=rx,go= $FBRootDir/bin/uninstall.sh
}


#------------------------------------------------------------------------
# Remove if only a link

removeIfOnlyAlink() {
	Target=$1

    if [ -L $Target ]
    then
        rm -f $Target
    fi
}


#------------------------------------------------------------------------
# re-link new file only if target is a link or missing

safeLink() {
	Source=$1
	Target=$2
	
	removeIfOnlyAlink $Target
    if [ ! -e $Target ]
    then
        ln -s $Source $Target
    fi
}


#------------------------------------------------------------------------
#  createLinksForBackCompatibility
#  Create links for back compatibility to InterBase and Firebird1.0 
#  linked systems.

createLinksForBackCompatibility() {

    # These two links are required for compatibility with existing ib programs
    # If the program had been linked with libgds.so then this link is required
    # to ensure it loads the fb equivalent.  Eventually these should be 
    # optional and in a seperate rpm install.  MOD 7-Nov-2002.

	if [ "$1" ]
	then
		# Use library name from parameter
		newLibrary=$FBRootDir/lib/$1
	else
	    # Use DefaultLibrary, set by appropriate install library
    	newLibrary=$FBRootDir/lib/$DefaultLibrary.so
	fi

	safeLink $newLibrary /usr/lib64/libgds.so
	safeLink $newLibrary /usr/lib64/libgds.so.0
}


#------------------------------------------------------------------------
#  removeLinksForBackCompatibility
#  Remove links for back compatibility to InterBase and Firebird1.0 
#  linked systems.

removeLinksForBackCompatibility() {
    removeIfOnlyAlink /usr/lib64/libgds.so
    removeIfOnlyAlink /usr/lib64/libgds.so.0
}

#------------------------------------------------------------------------
#  For security reasons most files in firebird installation are
#  root-owned and world-readable(executable) only (including firebird).

#  For some files RunUser (firebird) must have write access - 
#  lock and log for examples.

MakeFileFirebirdWritable() {
    FileName=$1
    chown $RunUser:$RunUser $FileName
    chmod 0644 $FileName
}


#------------------------------------------------------------------------
#  Set correct permissions for $FbRoot/doc tree

fixDocPermissions() {
	cd $FBRootDir

	for i in `find doc -print`; do
		chown root:root $i
		if [ -d $i ]; then
			chmod 0755 $i
		else
			chmod 0644 $i
		fi
	done
}


#------------------------------------------------------------------------
# Run process and check status

runAndCheckExit() {
    Cmd=$*

    $Cmd
    ExitCode=$?

    if [ $ExitCode -ne 0 ]
    then
        echo "Install aborted: The command $Cmd "
        echo "                 failed with error code $ExitCode"
        exit $ExitCode
    fi
}


#------------------------------------------------------------------------
#  Display message if this is being run interactively.

displayMessage() {
    msgText=$1

    if [ ! -z "$InteractiveInstall" ]
    then
        echo $msgText
    fi
}


#------------------------------------------------------------------------
#  Archive any existing prior installed files.
#  The 'cd' stuff is to avoid the "leading '/' removed message from tar.
#  for the same reason the DestFile is specified without the leading "/"

archivePriorInstallSystemFiles() {
	if [ -z ${ArchiveMainFile} ]
	then
		echo "Variable ArchiveMainFile not set - exiting"
		exit 1
	fi

	tarArc=${ArchiveMainFile}.$tarExt

    oldPWD=`pwd`
    archiveFileList=""

    cd /

    DestFile=${FBRootDir#/}   # strip off leading /
    if [ -e "$DestFile"  ]
    then
        echo ""
        echo ""
        echo ""
        echo "--- Warning ----------------------------------------------"
        echo "    The installation target directory: $FBRootDir"
        echo "    Already contains a prior installation of InterBase/Firebird."
        echo "    This and files found in /usr/include and /usr/lib64 will be"
        echo "    archived in the file : ${tarArc}"
        echo "" 

        if [ ! -z "$InteractiveInstall" ]
        then
            AskQuestion "Press return to continue or ^C to abort"
        fi

        if [ -e $DestFile ]
        then
            archiveFileList="$archiveFileList $DestFile"
        fi
    fi


    for i in ibase.h ib_util.h
    do
        DestFile=usr/include/$i
        if [ -e $DestFile ]
        then
            archiveFileList="$archiveFileList $DestFile"
        fi
    done

    for i in libib_util.so libfbclient.so*
	do
		for DestFile in usr/lib/$i
	    do
        	if [ -e $DestFile ]
	        then
    	        archiveFileList="$archiveFileList $DestFile"
        	fi
		done
    done

#    for i in `cat manifest.txt`
#    do
#        if [ ! -d /$i ]  # Ignore directories 
#        then
#            if [ -e /$i ]
#            then
#                archiveFileList="$archiveFileList $i"          
#            fi
#        fi
#    done

    for i in usr/sbin/rcfirebird etc/init.d/firebird etc/rc.d/init.d/firebird
    do
        DestFile=./$i
        if [ -e /$DestFile ]
        then
            archiveFileList="$archiveFileList $DestFile"
        fi
    done
	
    if [ ! -z "$archiveFileList" ]
    then
        displayMessage "Archiving..."
        runAndCheckExit "tar -c${tarOptions}f $tarArc $archiveFileList"
        displayMessage "Done."

        displayMessage "Deleting..."
        for i in $archiveFileList
        do
            rm -rf $i
        done
        displayMessage "Done."
    fi

    cd $oldPWD
}


#------------------------------------------------------------------------
# removeInstalledFiles
# 
removeInstalledFiles() {

    manifestFile=$FBRootDir/misc/manifest.txt

    if [ ! -f  $manifestFile ]
      then
        return
    fi

    origDir=`pwd`
    
    cd /

    for i in `cat $manifestFile`
      do
        if [ -f $i -o -L $i ]
          then
            rm -f $i
            #echo $i
        fi
    done

    cd "$origDir"
}


#------------------------------------------------------------------------
# removeUninstallFiles
# Under the install directory remove all the empty directories 
# If some files remain then 

removeUninstallFiles() {
    # remove the uninstall scripts files.
    #echo $FBRootDir/misc/scripts
    rm -rf $FBRootDir/misc/scripts
    rm -f $FBRootDir/misc/manifest.txt
    rm -f $FBRootDir/bin/uninstall.sh

}


#------------------------------------------------------------------------
# removeEmptyDirs
# Under the install directory remove all the empty directories 
# If some files remain then 
# This routine loops, since deleting a directory possibly makes
# the parent empty as well

removeEmptyDirs() {

    dirContentChanged='yes'
    while [ ! -z $dirContentChanged ]
      do
        dirContentChanged=''
        for i in `find $FBRootDir -type d -print`; do
            ls $i/* >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                rmdir $i
                dirContentChanged=$i
            fi
        done

        if [ ! -d $FBRootDir ]  # end loop if the FBRootDir was deleted.
          then
            dirContentChanged=''
        fi

      done
}

# classicLibrary.sh
#!/bin/sh

#------------------------------------------------------------------------
# init defaults
DefaultLibrary=libfbembed

#------------------------------------------------------------------------
#  fixFilePermissions
#  Change the permissions to restrict access to server programs to 
#  firebird group only.  This is MUCH better from a saftey point of 
#  view than installing as root user, even if it requires a little 
#  more work.


fixFilePermissions() {
	chown -R $RunUser:$RunGroup $FBRootDir

    # Turn other access off.
    chmod -R o= $FBRootDir

    # Now fix up the mess.

    # fix up directories 
    for i in `find $FBRootDir -print`
    do
        FileName=$i
        if [ -d $FileName ]
        then
            chmod o=rx $FileName
        fi
    done

    # set up the defaults for bin
    cd $FBBin
    for i in `ls`
      do
         chmod ug=rx,o=  $i
    done

    # User can run these programs, they need to talk to server though.
    # and they cannot actually create a database.
    chmod a=rx isql 
    chmod a=rx qli
    
    # Root SUID is still needed for group direct access.  
	# General users cannot run though.
    for i in fb_lock_mgr
    do
		if [ -f $i ]
		then
			chown root $i
	        chmod ug=rx,o= $i
    	    chmod ug+s $i
		fi
    done
	
	# set up libraries
	cd $FBRootDir
	cd lib
	chmod a=rx lib*

	# set up include files
	cd $FBRootDir
	cd include
	chmod a=r *

    # Fix lock files
    cd $FBRootDir
    for i in isc_init1 isc_lock1 isc_event1 isc_monitor1
    do
        FileName=$i.`hostname`
		touch $FileName
		chown $RunUser:$RunUser $FileName
        chmod ug=rw,o= $FileName
    done

    # Fix the rest
	touch firebird.log
    chmod ug=rw,o= firebird.log
	chmod a=r aliases.conf
	chmod a=r firebird.conf
    chmod a=r firebird.msg
    chmod a=r help/help.fdb
    chmod ug=rw,o= $SecurityDatabase
	chmod a=r *License.txt

	if [ "$RunUser" = "root" ]
	# In that case we must open databases to the world...
	# That's a pity, but required if root RunUser choosen.
	then
    	chmod a=rw $SecurityDatabase
	fi

	# fix up examples' permissions
    cd examples

    # set a default of read all files in examples
    for i in `find . -name '*' -type f -print`
    do
         chmod a=r $i
    done

    # set a default of read&search all dirs in examples
    for i in `find . -name '*' -type d -print`
    do
         chmod a=rx $i
    done

    # make examples db's writable by group
    for i in `find . -name '*.fdb' -print`
    do
		chown $RunUser:$RunUser $i
        chmod ug=rw,o= $i
    done
	
	# fix up doc permissions
	fixDocPermissions

	cd $FBRootDir
}


#------------------------------------------------------------------------
#  changeXinetdServiceUser
#  Change the run user of the xinetd service

changeXinetdServiceUser() {
    InitFile=/etc/xinetd.d/firebird
    if [ -f $InitFile ] 
    then
        editFile $InitFile user "\tuser\t\t\t= $RunUser"
    fi
}


#------------------------------------------------------------------------
#  Update inetd service entry
#  This just adds/replaces the service entry line

updateInetdEntry() {
    newLine="gds_db  stream  tcp     nowait.30000      $RunUser $FBBin/fb_inet_server fb_inet_server # Firebird Database Remote Server"
    replaceLineInFile /etc/inetd.conf "$newLine" "^gds_db"
}


#------------------------------------------------------------------------
#  Update xinetd service entry

updateXinetdEntry() {
    cp $FBRootDir/misc/firebird.xinetd /etc/xinetd.d/firebird
    changeXinetdServiceUser
}


#------------------------------------------------------------------------
#  Update inetd service entry 
#  Check to see if we have xinetd installed or plain inetd.  
#  Install differs for each of them.

updateInetdServiceEntry() {
    if [ -d /etc/xinetd.d ] 
    then
        updateXinetdEntry
    else
        updateInetdEntry
    fi
}


#------------------------------------------------------------------------
#  change init.d RunUser

changeInitRunUser() {
	# do nothing for CS
	return 0
}


#------------------------------------------------------------------------
#  start init.d service

startService() {
	# do nothing for CS
	return 0
}

# linuxLibrary.sh
#!/bin/sh

RunUser=firebird
export RunUser
RunGroup=firebird
export RunGroup
PidDir=/var/run/firebird
export PidDir

#------------------------------------------------------------------------
# Get correct options & misc.

psOptions=ww
export psOptions
mktOptions=-q
export mktOptions
tarOptions=z
export tarOptions
tarExt=tar.gz
export tarExt

#------------------------------------------------------------------------
#  Add new user and group

TryAddGroup() {

	AdditionalParameter=$1
	testStr=`grep firebird /etc/group`
	
    if [ -z "$testStr" ]
      then
        groupadd $AdditionalParameter firebird
    fi
	
}


TryAddUser() {

	AdditionalParameter=$1
	testStr=`grep firebird /etc/passwd`
	
    if [ -z "$testStr" ]
      then
        useradd $AdditionalParameter -d $FBRootDir -s /bin/false \
            -c "Firebird Database Owner" -g firebird firebird 
    fi

}


addFirebirdUser() {

	TryAddGroup "-g 84 -r" >/dev/null 2>&1
	TryAddGroup "-g 84" >/dev/null 2>&1
	TryAddGroup "-r" >/dev/null 2>&1
	TryAddGroup " "
	
	TryAddUser "-u 84 -r -M" >/dev/null 2>&1
	TryAddUser "-u 84 -M" >/dev/null 2>&1
	TryAddUser "-r -M" >/dev/null 2>&1
	TryAddUser "-M"
	TryAddUser "-u 84 -r" >/dev/null 2>&1
	TryAddUser "-u 84" >/dev/null 2>&1
	TryAddUser "-r" >/dev/null 2>&1
	TryAddUser " "

}


#------------------------------------------------------------------------
#  Detect Distribution.
#	AP: very beautiful, but unused. Let's keep alive for a while. (2005)

detectDistro() {

    # it's not provided...
    if [ -z "$linuxDistro"  ]
    then
	if [ -e /etc/SuSE-release  ]
	then
	    # SuSE
	    linuxDistro="SuSE"
	elif [ -e /etc/mandrake-release ]
	then
	    # Mandrake
	    linuxDistro="MDK"
	elif [ -e /etc/debian_version ]
	then
	    # Debian
	    linuxDistro="Debian"
	elif [ -e /etc/gentoo-release ]
	then
	    # Debian
	    linuxDistro="Gentoo"
	elif [ -e /etc/rc.d/init.d/functions ]
	then
	    # very likely Red Hat
	    linuxDistro="RH"
	elif [ -d /etc/rc.d/init.d ]
	then
	    # generic Red Hat
	    linuxDistro="G-RH"
	elif [ -d /etc/init.d ]
	then
	    # generic SuSE
	    linuxDistro="G-SuSE"
	fi
    fi
}


#------------------------------------------------------------------------
#  print location of init script

getInitScriptLocation() {
    if [ -f /etc/rc.d/init.d/firebird ]
	then
		echo -n /etc/rc.d/init.d/firebird
    elif [ -f /etc/rc.d/rc.firebird ]
	then
		echo -n /etc/rc.d/rc.firebird
    elif [ -f /etc/init.d/firebird ]
	then
		echo -n /etc/init.d/firebird
    fi
}


#------------------------------------------------------------------------
#  stop super server if it is running

stopSuperServerIfRunning() {
    checkString=`ps -efww| egrep "\b(fbserver|fbguard)\b" |grep -v grep`

    if [ ! -z "$checkString" ]
    then
		init_d=`getInitScriptLocation`

        if [ -x "$init_d" ]
		then
       	    $init_d stop
			sleep 1
		fi
    fi
}

#!/bin/sh
#
#  This library is part of the FirebirdSQL project
#
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public
#  License as published by the Free Software Foundation; either
#  version 2.1 of the License, or (at your option) any later version.
#  You may obtain a copy of the Licence at
#  http://www.gnu.org/licences/lgpl.html
#  
#  As a special exception this file can also be included in modules
#  with other source code as long as that source code has been 
#  released under an Open Source Initiative certificed licence.  
#  More information about OSI certification can be found at: 
#  http://www.opensource.org 
#  
#  This module is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Lesser General Public Licence for more details.
#  
#  This module was created by members of the firebird development 
#  team.  All individual contributions remain the Copyright (C) of 
#  those individuals and all rights are reserved.  Contributors to 
#  this file are either listed below or can be obtained from a CVS 
#  history command.
# 
#   Created by:  Mark O'Donohue <mark.odonohue@ludwig.edu.au>
# 
#   Contributor(s):
#  
# 
#   $Id: tarMainInstall.sh.in,v 1.2 2005-08-16 10:04:11 alexpeshkoff Exp $
# 

#  Install script for FirebirdSQL database engine
#  http://www.firebirdsql.org


InteractiveInstall=1
export InteractiveInstall


checkInstallUser

BuildVersion=2.1.7.18553
PackageVersion=0
CpuType=amd64

Version="$BuildVersion-$PackageVersion.$CpuType"


cat <<EOF

Firebird classic $Version Installation

EOF



#AskQuestion "Press Enter to start installation or ^C to abort"


# Here we are installing from a install tar.gz file

if [ -e scripts ]
  then
    echo "Extracting install data"
    runAndCheckExit "./scripts/preinstall.sh"
    runAndCheckExit "./scripts/tarinstall.sh"
    runAndCheckExit "./scripts/postinstall.sh"

fi

echo "Install completed"

