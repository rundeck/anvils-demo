#!/usr/bin/env bash

set -eu


if [[ $# -ne 1 ]]
then
    echo >&2 "usage: add-project project"
    exit 1
fi
PROJECT=$1

# Fictitious hosts that mascarade as local nodes

USERS=( www{1,2} app{1,2} db1 )

# Add a user account for each role/user
# -------------------------------------

for user in ${USERS[*]}
do
	if ! grep $user /etc/passwd
	then		:
	else		continue
	fi		
    echo "Adding user ${user}."
	useradd -d /home/$user -m $user
	mkdir /home/$user/.ssh
	ssh-keygen -b 2048 -t rsa -f /home/$user/.ssh/id_rsa -q -N ""
	cat ~rundeck/.ssh/id_rsa.pub >> /home/$user/.ssh/authorized_keys
	chmod 600 /home/$user/.ssh/authorized_keys
	chown -R $user:$user /home/$user/.ssh
done

# Configure SSHD to pass environment variables to shell.
if ! grep -q "AcceptEnv RD_" /etc/ssh/sshd_config
then	
	echo 'AcceptEnv RD_*' >> /etc/ssh/sshd_config
	/etc/init.d/sshd stop
	/etc/init.d/sshd start
fi

# Create an example project
# --------------------------

echo Creating project $PROJECT...

# Configure directory resource source
RESOURCES_D=/var/rundeck/projects/${PROJECT}/etc/resources.d
mkdir -p $RESOURCES_D
chown -R rundeck:rundeck /var/rundeck

su - rundeck -c "rd-project -a create -p $PROJECT --resources.source.2.type=directory --resources.source.2.config.directory=$RESOURCES_D"

# Run simple commands for sanity checking.
su - rundeck -c "dispatch -p $PROJECT"
# Run an adhoc command.
su - rundeck -c "dispatch -p $PROJECT -f '*' whoami"

# Add node resources
# --------------
NODES=( ${USERS[*]} )

# Generate resource model for each node.
for NAME in ${NODES[*]}
do
	ROLE= INDEX=
    [[ $NAME =~ ([^0-9]+)([0-9]+) ]] && { ROLE=${BASH_REMATCH[1]} INDEX=${BASH_REMATCH[2]} ; }
    cat > $RESOURCES_D/$NAME.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>

<project>    
  <node name="${NAME}.anvils.com" hostname="localhost" username="${NAME}"
      description="A $ROLE server node." tags="${ROLE},anvils"
      osFamily="unix" osName="$(uname -s)" osArch="$(uname -m)" osVersion="$(uname -r)"
      ssh-keypath="/var/lib/rundeck/.ssh/id_rsa"
      >
    <!-- anvils specific attributes -->
    <attribute name="anvils:server-pool" value="$ROLE"/>
    <attribute name="anvils:server-pool-id" value="$INDEX"/>
    <attribute name="anvils:location" value="US-East"/>
    <attribute name="anvils:customer" value="acme.com"/>
  </node>
</project>
EOF
    echo "Added node: ${NAME} [role: $ROLE]."
done
chown rundeck:rundeck $RESOURCES_D/*.xml

# Add jobs, scripts and options
# -----------------------------

mkdir -p /var/www/html/$PROJECT/{scripts,options,jobs}
cp -r /vagrant/jobs/*    /var/www/html/$PROJECT/jobs/
cp -r /vagrant/scripts/* /var/www/html/$PROJECT/scripts/
cp -r /vagrant/options/* /var/www/html/$PROJECT/options/
chgrp -R rundeck /var/www/html/$PROJECT/{scripts,options,jobs}

# Load the jobs
for job in /var/www/html/$PROJECT/jobs/*.xml
do
	su - rundeck -c "rd-jobs load -f $job"
done

# List the jobs
su - rundeck -c "rd-jobs list -p $PROJECT"


exit $?