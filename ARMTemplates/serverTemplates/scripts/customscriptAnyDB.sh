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
    ipaddr=`host $host | awk '/has address/ { print $4 }'`

    host_entry="${ipaddr} ${host}"
    echo "$host_entry" | tee -a /etc/hosts > /dev/null

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
         
        saptune solution apply NETWEAVER     
        saptune daemon start

        # for Azure backup
        # zypper install -y unixODBC, not needed?
    
    else 
        #RHEL
        yum update -y
        yum update rhui-azure-rhel8-sap-ha -y # workaround for missing repo
	    	    
        #yum in -y gtk2 libicu xulrunner sudo tcsh libssh2 expect cairo graphviz iptraf-ng krb5-workstation krb5-libs libpng12 nfs-utils lm_sensors rsyslog openssl PackageKit-gtk3-module libcanberra-gtk2 libtool-ltdl xorg-x11-xauth numactl xfsprogs net-tools bind-utils compat-sap-c++-7 libatomic tuned-profiles-sap-hana cifs-utils
        yum in -y uuidd libnsl tcsh psmisc nfs-utils bind-utils cifs-utils 

        # for pacemaker
        yum in -y pcs pacemaker fence-agents-azure-arm nmap-ncat resource-agents resource-agents-sap

        systemctl start tuned
        systemctl enable tuned  

        setenforce 0
        sed -i 's/\(SELINUX=enforcing\|SELINUX=permissive\)/SELINUX=disabled/g' /etc/selinux/config
         
        systemctl start uuidd
        systemctl enable uuidd

        sysctl -w net.ipv4.tcp_timestamps=0

        #for Azure backup
        #yum install rh-dotnet22-dotnet-runtime-2.2 unixODBC -y
        #scl enable rh-dotnet22 bash

    fi

    #azcopy
    cd /tmp
    wget -O azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux 
	tar -xf azcopy.tar.gz
    mv azcopy_linux_* azcopy
    export PATH=$PATH:/tmp/azcopy
    
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
    
    mkdir /media
    mount -t nfs mysapfileshare.file.core.windows.net:/mysapfileshare/jltshare/media /media -o vers=4,minorversion=1,sec=sys
    bash -c 'echo "mysapfileshare.file.core.windows.net:/mysapfileshare/jltshare/media /media  nfs vers=4,minorversion=1,sec=sys" >> /etc/fstab'

    log "mounting Azure File share done"
}

function prepareSAPBins()
{
    log "preparing SAP Medias"

    mkdir /mnt/media
    cd /mnt/media

    rsync --progress /media/SAPCAR .
    rsync --progress -r /media/SWPM .

    cd /mnt/media/SWPM
    ../SAPCAR -xvf *.SAR
    
    useradd sapadmin
    echo hacluster:Heslo.123 | chpasswd

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