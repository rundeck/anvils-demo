#!/usr/bin/env bash

set -e
set -u


if [ $# -ne 1 ]
then
    echo >&2 "usage: add-project project"
    exit 1
fi
PROJECT=$1

# Fictitious hosts that mascarade as local nodes

USERS=( www_{1,2} app_{1,2} db_1 )

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

su - rundeck -c "rd-project -a create -p $PROJECT"

# Run simple commands to double check.
su - rundeck -c "dispatch -p $PROJECT"
# Run an adhoc command.
su - rundeck -c "dispatch -p $PROJECT -f '*' whoami"

# Add resources
# --------------
NODES=( ${USERS[*]} )

RESOURCES=/var/rundeck/projects/${PROJECT}/etc/resources.xml

for NAME in ${NODES[*]}
do
	if ! xmlstarlet sel -t -m "/project/node[@name='${NAME}']" -v @name $RESOURCES
	then
	ROLE=${NAME%%_*}
    echo "Adding node: ${NAME}."
    	xmlstarlet ed -P -S -L -s /project -t elem -n NodeTMP -v "" \
    	    -i //NodeTMP -t attr -n "name" -v "${NAME}.anvils.com" \
        	-i //NodeTMP -t attr -n "description" -v "A $ROLE server node." \
	        -i //NodeTMP -t attr -n "tags" -v "${ROLE},anvils" \
    	    -i //NodeTMP -t attr -n "hostname" -v "localhost" \
        	-i //NodeTMP -t attr -n "username" -v "${NAME}" \
        	-i //NodeTMP -t attr -n "osFamily" -v "unix" \
        	-i //NodeTMP -t attr -n "osName" -v "Linux" \
        	-i //NodeTMP -t attr -n "osArch" -v "x86_64" \
        	-i //NodeTMP -t attr -n "osVersion" -v "2.6.32-279.el6.x86_64" \
        	-i //NodeTMP -t attr -n "anvils-location" -v "US-East" \
        	-i //NodeTMP -t attr -n "anvils-customer" -v "acme.com" \
	        -i //NodeTMP -t attr -n "ssh-keypath" -v "/var/lib/rundeck/.ssh/id_rsa" \
    	    -r //NodeTMP -v node \
        	$RESOURCES
	else
    	echo "Node $NAME already defined in resources.xml"
	fi
done

# Add jobs, scripts and options
# -----------------------------

mkdir -p /var/www/html/$PROJECT/{scripts,options,jobs}
cp -r /vagrant/jobs/*    /var/www/html/$PROJECT/jobs/
cp -r /vagrant/scripts/* /var/www/html/$PROJECT/scripts/
cp -r /vagrant/options/* /var/www/html/$PROJECT/options/
chown -R rundeck:apache /var/www/html/$PROJECT/{scripts,options,jobs}

# Add jobs
for job in /var/www/html/$PROJECT/jobs/*.xml
do
	su - rundeck -c "rd-jobs load -f $job"
done

# List the jobs
su - rundeck -c "rd-jobs list -p $PROJECT"


exit $?