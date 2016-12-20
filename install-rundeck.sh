#!/usr/bin/env bash

set -eu

# Process command line arguments.

if [[ $# -lt 2 ]]
then
    echo >&2 "usage: $0 rdip rundeck_yum_repo"
    exit 2
fi

RDIP=$1
RUNDECK_REPO_URL=$2

# Software install
# ----------------
#
# Utilities
#
yum -y install coreutils

#
# JRE
#
yum -y install java-1.8.0
#
# Rundeck server and CLI
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

yum -y install rundeck rundeck-cli

# Reset the home directory permission as it comes group writeable.
# This is needed for ssh requirements.
chmod 755 ~rundeck

# Add Plugins
LIBEXT=/var/lib/rundeck/libext
# Hipchat
[[ ! -f $LIBEXT/rundeck-hipchat-plugin-1.0.0.jar ]] && {
    cp /vagrant/rundeck-hipchat-plugin-1.0.0.jar $LIBEXT
}
# nexus
[[ ! -f $LIBEXT/nexus-step-plugins-1.0.0.jar ]] && {
curl -sfL -o $LIBEXT/nexus-step-plugins-1.0.2.jar https://github.com/rundeck-plugins/nexus-step-plugins/releases/download/1.0.2/nexus-step-plugins-1.0.2.jar
}
# puppet
[[ ! -f $LIBEXT/puppet-apply-step.zip ]] && {
curl -sfL -o $LIBEXT/puppet-apply-step.zip https://github.com/rundeck-plugins/puppet-apply-step/releases/download/v1.0.0/puppet-apply-step-1.0.0.zip
}
# jira
[[ ! -f $LIBEXT/jira-workflow-step-1.0.0.jar ]] && {
curl -sfL -o $LIBEXT/jira-workflow-step-1.0.0.jar https://github.com/rundeck-plugins/jira-workflow-step/releases/download/v1.0.0/jira-workflow-step-1.0.0.jar
}
[[ ! -f $LIBEXT/jira-notification-1.0.0.jar ]] && {
curl -sfL -o $LIBEXT/jira-notification-1.0.0.jar https://github.com/rundeck-plugins/jira-notification/releases/download/v1.0.0/jira-notification-1.0.0.jar
}
# jabber
[[ ! -f $LIBEXT/jabber-notification-1.0.jar ]] && {
curl -sfL -o $LIBEXT/jabber-notification-1.0.jar https://github.com/rundeck-plugins/jabber-notification/releases/download/v1.0/jabber-notification-1.0.jar
}
# pagerduty
[[ ! -f $LIBEXT/PagerDutyNotification.groovy ]] && {
curl -sfL -o $LIBEXT/PagerDutyNotification.groovy https://raw.githubusercontent.com/rundeck-plugins/pagerduty-notification/master/src/PagerDutyNotification.groovy
}
# EC2
[[ ! -f $LIBEXT/rundeck-ec2-nodes-plugin-1.5.3.jar ]] && {
curl -sfL -o $LIBEXT/rundeck-ec2-nodes-plugin-1.5.3.jar https://github.com/rundeck-plugins/rundeck-ec2-nodes-plugin/releases/download/v1.5.3/rundeck-ec2-nodes-plugin-1.5.3.jar
}

# nixy/file
curl -sfL -o $LIBEXT/nixy-file.zip "https://dl.bintray.com/rundeck/rundeck-plugins/nixy-file-1.0.0.zip"

# nixy/waitfor
curl -sfL -o $LIBEXT/nixy-waitfor.zip "https://dl.bintray.com/rundeck/rundeck-plugins/nixy-waitfor-1.0.0.zip"

chown -R rundeck:rundeck $LIBEXT

# Configure the system

# Rewrite the rundeck-config.properties to use the IP of this vagrant VM
sed -i "s^grails.serverURL=.*^grails.serverURL=http://$RDIP:4440^g" /etc/rundeck/rundeck-config.properties 

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
        if ! grep  "Connector@" /var/log/rundeck/service.log
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

echo "Waiting 30s for startup..."
sleep 30
echo "Rundeck started."

echo "Loading system level ACL policy files ..."

export RD_URL=$(awk -F= "/grails.serverURL/ {print \$2}" /etc/rundeck/rundeck-config.properties)
export RD_USER=admin RD_PASSWORD=admin

# Add the Anvils system level ACLs
for acl in /vagrant/aclpolicy/system/*.aclpolicy
do
    rd system acls create --file $acl --name $(basename $acl)
done

rd system acls list

exit $?
