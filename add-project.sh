#!/usr/bin/env bash

set -eu

if (( $# != 1 ))
then
    echo >&2 "usage: $0 project"
    exit 1
fi
PROJECT=$1

export RD_URL=$(awk -F= "/grails.serverURL/ {print \$2}" /etc/rundeck/rundeck-config.properties)
export RD_USER=admin RD_PASSWORD=admin
export RD_PROJECT=$PROJECT

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
	if ! id $NAME 2>/dev/null
	then	 :
	else	 continue
	fi		
  
  echo "Adding user account ${NAME}..."
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
  rd keys create \
    --path "$KEYPATH" --type privateKey --file "/home/$NAME/.ssh/id_rsa"
  rd keys create \
    --path "$KEYPATH.pub" --type publicKey --file "/home/$NAME/.ssh/id_rsa.pub"

  # List the keys
  rd keys list --path acme/${PROJECT}/${NAME} 

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
chown -R rundeck:rundeck "$RESOURCES_D"

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

rd projects create -p $PROJECT -- --resources.source.2.type=directory --resources.source.2.config.directory=$RESOURCES_D

RDECK_NAME=$(awk -F= "/framework.server.name/ {print \$2}" /etc/rundeck/framework.properties)
RDECK_HOST=$(awk -F= "/framework.server.hostname/ {print \$2}" /etc/rundeck/framework.properties)


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



# Add the Anvils project level ACLs
echo "Loading project level ACL policy files ..."
for acl in /vagrant/aclpolicy/project/*.aclpolicy
do
    rd projects acls create --file $acl --name $(basename $acl)
done

rd projects acls list


# Run a local ad-hoc command for sanity checking.
echo "Running a adhoc command across the nodes tagged for anvils ..."
rd adhoc -p $PROJECT --follow --filter 'tags: anvils' -- whoami

# Add jobs, scripts and options
# -----------------------------

mkdir -p /var/www/html/$PROJECT/options
cp -r /vagrant/options/* /var/www/html/$PROJECT/options/
chown -R apache:rundeck /var/www/html/$PROJECT/options

# Load the jobs
echo "Loading jobs for $PROJECT project ..."
for job in /vagrant/jobs/*.xml
do
	rd jobs load --file "$job" --project $PROJECT
done

# List the jobs
rd jobs list -p $PROJECT


exit $?
