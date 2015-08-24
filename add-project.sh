#!/usr/bin/env bash

set -eu


if (( $# != 1 ))
then
    echo >&2 "usage: add-project project"
    exit 1
fi
PROJECT=$1

fwk_prop_read() {
  local propkey=$1
  value=$(awk -F= "/framework.$propkey/ {print \$2}" /etc/rundeck/framework.properties)
  printf "%s" "${value//[[:space:]]/}"
}

RDECK_URL=$(fwk_prop_read  server.url)
RDECK_USER=$(fwk_prop_read server.username)
RDECK_PASS=$(fwk_prop_read server.password)
RDECK_NAME=$(fwk_prop_read server.name)
RDECK_HOST=$(fwk_prop_read server.hostname)

# Create a directory for the resource model
ETC=/var/rundeck/projects/${PROJECT}/etc
RESOURCES_D=$ETC/resources.d
mkdir -p "$RESOURCES_D"

# Fictitious hosts that mascarade as nodes
RESOURCES=( www{1,2} app{1,2} db1 )

# Add a user account and node entry for each resource.
# -------------------------------------

for NAME in ${RESOURCES[*]:-}
do
  # Create local host account
	if ! id $NAME
	then	 :
	else	 continue
	fi		
  
  echo "Add host user ${NAME}."
	useradd -d /home/$NAME -m $NAME

  # Generate an SSH key for this user
  echo "Generate SSH key for user $NAME"
  su - $NAME -c "ssh-keygen -b 2048 -t rsa -f /home/$NAME/.ssh/id_rsa -q -N ''"
  cat /home/$NAME/.ssh/id_rsa.pub >> /home/$NAME/.ssh/authorized_keys
  chmod 600 /home/$NAME/.ssh/authorized_keys
  chown -R $NAME:$NAME /home/$NAME/.ssh
 
  # Upload SSH key
  # --------------
  # key-path convention: {org}/{app}/{user}
  #
  KEYPATH="acme/${PROJECT}/${NAME}/id_rsa"

  rerun  rundeck-admin: key-upload \
    --keypath $KEYPATH --format private --file /home/$NAME/.ssh/id_rsa \
    --user $RDECK_USER --password $RDECK_PASS --url ${RDECK_URL} 
  rerun  rundeck-admin: key-upload \
    --keypath $KEYPATH.pub --format public --file /home/$NAME/.ssh/id_rsa.pub \
    --user $RDECK_USER --password $RDECK_PASS --url ${RDECK_URL} 

  # List the keys
  rerun  rundeck-admin: key-list \
    --keypath acme/${PROJECT}/${NAME} \
    --user $RDECK_USER --password $RDECK_PASS --url ${RDECK_URL}

  # Add node definition
  # --------------
  ROLE= INDEX=
  [[ $NAME =~ ([^0-9]+)([0-9]+) ]] && { ROLE=${BASH_REMATCH[1]} INDEX=${BASH_REMATCH[2]} ; }

  cat > $RESOURCES_D/$NAME.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>

<project>    
  <node name="${NAME}.anvils.com" hostname="localhost" username="${NAME}"
      description="A $ROLE server node." tags="${ROLE},anvils"
      osFamily="unix" osName="$(uname -s)" osArch="$(uname -m)" osVersion="$(uname -r)"
      ssh-key-storage-path="/keys/$KEYPATH"
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
chown -R rundeck:rundeck $RESOURCES_D

# Configure SSHD to pass RD environment variables through.
if ! grep -q "^AcceptEnv RD_" /etc/ssh/sshd_config
then	
	echo 'AcceptEnv RD_*' >> /etc/ssh/sshd_config
	/etc/init.d/sshd stop
	/etc/init.d/sshd start
fi

# Create an example project
# --------------------------

echo "Creating project $PROJECT..."
chown -R rundeck:rundeck /var/rundeck

#
# Create the project

su - rundeck -c "rd-project -a create -p $PROJECT --resources.source.2.type=directory --resources.source.2.config.directory=$RESOURCES_D"

cat > $ETC/resources.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>

<project>    
  <node name="$RDECK_NAME" hostname="$RDECK_HOST" username="rundeck"
      description="Rundeck server node." tags=""
      osFamily="unix" osName="$(uname -s)" osArch="$(uname -m)" osVersion="$(uname -r)"
      >
    <!-- configure bash as the local node executor -->
    <attribute name="script-exec-shell" value="bash -c"/>
    <attribute name="script-exec" value="\${exec.command}"/>
    <attribute name="local-node-executor" value="script-exec"/>
  </node>
</project>
EOF

# Run a local ad-hoc command for sanity checking.
su - rundeck -c "dispatch -p $PROJECT"
# Run a distributed ad-hoc command across all nodes
su - rundeck -c "dispatch -p $PROJECT -f '*' whoami"

# Add jobs, scripts and options
# -----------------------------

mkdir -p /var/www/html/$PROJECT/{scripts,options,jobs}
cp -r /vagrant/jobs/*    /var/www/html/$PROJECT/jobs/
cp -r /vagrant/scripts/* /var/www/html/$PROJECT/scripts/
cp -r /vagrant/options/* /var/www/html/$PROJECT/options/
chown -R apache:rundeck /var/www/html/$PROJECT/{scripts,options,jobs}
chmod 640 /var/www/html/$PROJECT/jobs/*

# Load the jobs
for job in /var/www/html/$PROJECT/jobs/*.xml
do
	su - rundeck -c "rd-jobs load -f $job"
done

# List the jobs
su - rundeck -c "rd-jobs list -p $PROJECT"


exit $?
