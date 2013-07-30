#!/usr/bin/env bash

set -e 
set -u

# Process command line arguments.

if [ $# -lt 2 ]
then
    echo >&2 "usage: $0 rdip rundeck_yum_repo"
    exit 1
fi

RDIP=$1
RUNDECK_REPO_URL=$2

# Software install
# ----------------
#
# Utilities
# Bootstrap a fedora repo to get xmlstarlet

curl -s http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm -o epel-release.rpm -z epel-release.rpm
if ! rpm -q epel-release
then
    rpm -Uvh epel-release.rpm
fi
yum -y install xmlstarlet coreutils

#
# JRE
#
yum -y install java-1.6.0
#
# Rundeck 
#
if [ -n "$RUNDECK_REPO_URL" ]
then
    curl -# --fail -L -o /etc/yum.repos.d/rundeck.repo "$RUNDECK_REPO_URL" || {
        echo "failed downloading rundeck.repo config"
        exit 2
    }
else
    if ! rpm -q rundeck-repo
    then
        rpm -Uvh http://repo.rundeck.org/latest.rpm 
    fi
fi

yum -y install rundeck

# Reset the home directory permission as it comes group writeable.
# This is needed for ssh requirements.
chmod 755 ~rundeck

# Add the HipChat plugin
cp /vagrant/rundeck-hipchat-plugin-1.0.0.jar /var/lib/rundeck/libext/
chown rundeck:rundeck /var/lib/rundeck/libext/rundeck-hipchat-plugin-1.0.0.jar 

# Configure the system

# Rewrite the rundeck-config.properties to use the IP of this vagrant VM
sed -i "s^grails.serverURL=.*^grails.serverURL=http://$RDIP:4440^g" /etc/rundeck/rundeck-config.properties 

# Add the Anvils specific ACL
cp /vagrant/anvils.aclpolicy /etc/rundeck/
chown rundeck:rundeck /etc/rundeck/anvils.aclpolicy
chmod 444 /etc/rundeck/anvils.aclpolicy

# Add user/roles to the realm.properties
cat >> /etc/rundeck/realm.properties <<EOF
admin:admin,user,admin,anvils
dev:dev,dev,user,anvils
ops:ops,ops,user,anvils
releng:releng,releng,user,anvils
EOF

#
# Disable the firewall so we can easily access it from the host
service iptables stop
#


# Start up rundeck
# ----------------
#
set +e
if ! /etc/init.d/rundeckd status
then
    echo "Starting rundeck..."
    (
        exec 0>&- # close stdin
        /etc/init.d/rundeckd start 
    ) &> /var/log/rundeck/service.log # redirect stdout/err to a log.

    let count=0
    let max=18
    while [ $count -le $max ]
    do
        if ! grep  "Started SocketConnector@" /var/log/rundeck/service.log
        then  printf >&2 ".";# progress output.
        else  break; # successful message.
        fi
        let count=$count+1;# increment attempts
        [ $count -eq $max ] && {
            echo >&2 "FAIL: Execeeded max attemps "
            exit 1
        }
        sleep 10
    done
fi

echo "Rundeck started."

exit $?