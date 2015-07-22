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
# Bootstrap a fedora repo to get xmlstarlet

if ! rpm -q epel-release
then
    curl -s http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm -o epel-release.rpm 
    rpm -Uvh epel-release.rpm
    sed -i -e 's/^mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/epel.repo
    sed -i -e 's/^#baseurl=/baseurl=/g' /etc/yum.repos.d/epel.repo
fi

yum -y install xmlstarlet coreutils

#
# JRE
#
yum -y install java-1.7.0
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

# Add Plugins

# Hipchat
[[ ! -f /var/lib/rundeck/libext/rundeck-hipchat-plugin-1.0.0.jar ]] && {
    cp /vagrant/rundeck-hipchat-plugin-1.0.0.jar /var/lib/rundeck/libext/
}
# nexus
[[ ! -f /var/lib/rundeck/libext/nexus-step-plugins-1.0.0.jar ]] && {
curl -sfL -o /var/lib/rundeck/libext/nexus-step-plugins-1.0.0.jar https://github.com/rundeck-plugins/nexus-step-plugins/releases/download/v1.0.0/nexus-step-plugins-1.0.0.jar
}
# puppet
[[ ! -f /var/lib/rundeck/libext/puppet-apply-step.zip ]] && {
curl -sfL -o /var/lib/rundeck/libext/puppet-apply-step.zip https://github.com/rundeck-plugins/puppet-apply-step/releases/download/v1.0.0/puppet-apply-step-1.0.0.zip
}
# jira
[[ ! -f /var/lib/rundeck/libext/jira-workflow-step-1.0.0.jar ]] && {
curl -sfL -o /var/lib/rundeck/libext/jira-workflow-step-1.0.0.jar https://github.com/rundeck-plugins/jira-workflow-step/releases/download/v1.0.0/jira-workflow-step-1.0.0.jar
}
[[ ! -f /var/lib/rundeck/libext/jira-notification-1.0.0.jar ]] && {
curl -sfL -o /var/lib/rundeck/libext/jira-notification-1.0.0.jar https://github.com/rundeck-plugins/jira-notification/releases/download/v1.0.0/jira-notification-1.0.0.jar
}
# jabber
[[ ! -f /var/lib/rundeck/libext/jabber-notification-1.0.jar ]] && {
curl -sfL -o /var/lib/rundeck/libext/jabber-notification-1.0.jar https://github.com/rundeck-plugins/jabber-notification/releases/download/v1.0/jabber-notification-1.0.jar
}
# pagerduty
[[ ! -f /var/lib/rundeck/libext/PagerDutyNotification.groovy ]] && {
curl -sfL -o /var/lib/rundeck/libext/PagerDutyNotification.groovy https://raw.githubusercontent.com/rundeck-plugins/pagerduty-notification/master/src/PagerDutyNotification.groovy
}
# EC2
[[ ! -f /var/lib/rundeck/libext/rundeck-ec2-nodes-plugin-1.5.jar ]] && {
curl -sfL -o /var/lib/rundeck/libext/rundeck-ec2-nodes-plugin-1.5.jar https://github.com/rundeck-plugins/rundeck-ec2-nodes-plugin/releases/download/1.5/rundeck-ec2-nodes-plugin-1.5.jar
}

# file-util
curl -sfL -o /var/lib/rundeck/libext/file-util.zip https://bintray.com/artifact/download/rundeck-plugins/rerun-remote-node-steps/file-util/1.0.0/file-util.zip

# waitfor
curl -sfL -o /var/lib/rundeck/libext/waitfor.zip https://bintray.com/artifact/download/rundeck-plugins/rerun-remote-node-steps/waitfor/1.1.0/waitfor.zip

chown -R rundeck:rundeck /var/lib/rundeck/libext

# Configure the system

# Rewrite the rundeck-config.properties to use the IP of this vagrant VM
sed -i "s^grails.serverURL=.*^grails.serverURL=http://$RDIP:4440^g" /etc/rundeck/rundeck-config.properties 

# Add the Anvils specific ACL
cp /vagrant/aclpolicy/*.aclpolicy /etc/rundeck/
chown rundeck:rundeck /etc/rundeck/*.aclpolicy
chmod 444 /etc/rundeck/*.aclpolicy

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

echo "Rundeck started."

exit $?
