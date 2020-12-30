#!/bin/bash
#
# update and adjust OS
# cat customscript.sh | base64 -w0
#

function log()
{
    message=$@
    echo "$message"
    echo "$(date -Iseconds): $message" >> /tmp/customscript
}

function getInfo()
{
    #get the OS dist
    . /etc/os-release
    OS=$ID
    
    host=$(hostname)
    sid=${host:0:3}
    SID=${sid^^}

    insttype=`echo $host | grep -oP '(?<=-).*(?=-)'`

    #get the VM size via the instance api
    vmsize=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2017-08-01&format=text"`

}

function installPackages()
{
    log "installPackages start"

    if [ $OS == "sles" ]; then
        #/usr/sbin/registercloudguest --force-new
        
        zypper update -y
        zypper in -y socat resource-agents saptune unrar tree sap-suse-cluster-connector
        
        if [ $insttype == "db"]; then
            zypper in -y -t pattern sap-hana
            zypper in -y SAPHanaSR 

            saptune solution apply HANA
        fi
       
        saptune solution apply NETWEAVER     
        saptune daemon start

        # for Azure backup
        # zypper install -y unixODBC, not needed?
    
    else 
        #RHEL
        yum update -y
	    	    
        #yum in -y gtk2 libicu xulrunner sudo tcsh libssh2 expect cairo graphviz iptraf-ng krb5-workstation krb5-libs libpng12 nfs-utils lm_sensors rsyslog openssl PackageKit-gtk3-module libcanberra-gtk2 libtool-ltdl xorg-x11-xauth numactl xfsprogs net-tools bind-utils compat-sap-c++-7 libatomic tuned-profiles-sap-hana cifs-utils
        yum in -y uuidd libnsl tcsh psmisc nfs-utils bind-utils cifs-utils

        systemctl start tuned
        systemctl enable tuned

        if [ $insttype == "db"]; then
            yum in -y expect graphviz iptraf-ng krb5-workstation libatomic libcanberra-gtk2 libibverbs libicu libpng12 libssh2 lm_sensors numactl PackageKit-gtk3-module xorg-x11-xauth tuned-profiles-sap-hana
            tuned-adm profile sap-hana
        fi       

        setenforce 0
        sed -i 's/\(SELINUX=enforcing\|SELINUX=permissive\)/SELINUX=disabled/g' /etc/selinux/config
         
        systemctl start uuidd
        systemctl enable uuidd

        #for Azure backup
        #yum install rh-dotnet22-dotnet-runtime-2.2 unixODBC -y
        #scl enable rh-dotnet22 bash

    fi
    
    log "installPackages done"
}

function enableSwap()
{
    log "enableSwap start"
    
    sed -i.bak "s/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/" /etc/waagent.conf 
    sed -i.bak "s/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=2048/" /etc/waagent.conf
    
    #service waagent restart

    log "enableSwap done"  
}

function mountAzurefiles()
{
    log "mounting Azure File share start"
    
    sudo mkdir -p /mnt/mysapfileshare/jltshare
    sudo mount -t nfs mysapfileshare.file.core.windows.net:/mysapfileshare/jltshare /mnt/mysapfileshare/jltshare -o vers=4,minorversion=1,sec=sys

    log "mounting Azure File share done"
}

function prepareSAPBins()
{
    log "preparing SAP Medias"

    mkdir /media
    cd /media
    
    rsync --progress /mnt/mysapstorageaccount/Media/SAPCAR .
    rsync --progress /mnt/mysapstorageaccount/Media/HANA/IMDB_SERVER20_043_0-80002031.SAR .
    rsync --progress /mnt/mysapstorageaccount/Media/HANA/IMDB_CLIENT20_004_162-80002082.SAR .
    rsync --progress /mnt/mysapstorageaccount/Media/HANA/HWCCT_237_0-20011536.SAR .
    
    ./SAPCAR -xvf IMDB_CLIENT20_004_162-80002082.SAR
    ./SAPCAR -xvf IMDB_SERVER20_043_0-80002031.SAR
    ./SAPCAR -xvf IMDB_SERVER20_043_0-80002031.SAR SIGNATURE.SMF -manifest SIGNATURE.SMF


    useradd admin
    echo admin:Heslo.123 | chpasswd

    #./sapinst SAPINST_REMOTE_ACCESS_USER=admin

    log "preparing SAP Medias done"
}

################
# ### MAIN ### #
################

log $@
log "custom script start"

getInfo
installPackages
enableSwap
mountAzurefiles
prepareSAPBins

log "custom script done"

exit