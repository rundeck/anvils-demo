#!/usr/bin/env bash

set -eu

if (( $# != 1 ))
then
    echo >&2 "usage: $0 <project>"
    exit 1
fi
PROJECT=$1

export RD_URL=$(awk -F= "/grails.serverURL/ {print \$2}" /etc/rundeck/rundeck-config.properties)
export RD_USER=admin RD_PASSWORD=admin
export RD_PROJECT=$PROJECT

# Initialize a new yaml
ETC=/var/rundeck/projects/${PROJECT}/etc
mkdir -p $ETC
 > $ETC/anvils-nodes.yaml

CATALOG_D=/var/rundeck/$PROJECT/catalog
mkdir -p $CATALOG_D
for category in {partner,inventory,shipping-rates}
do
  cat >$CATALOG_D/${category}.data <<EOF
  category: $category
  date: $(date)
EOF
done

catalog_pw=$(mktemp catalog.password.XXXX)
echo "anvils" > "$catalog_pw"
rd keys create \
    --path "acme/anvils/db/catalog.password" --type password --file "$catalog_pw"

# Fictitious hosts that mascarade as nodes
RESOURCES=( www{1,2} app{1,2} db1 )

# Add a user account and node entry for each Node.
# -----------------------------------------------

for NAME in ${RESOURCES[*]:-}
do
  # Create local system account
	if ! id $NAME 2>/dev/null
	then	 :
	else	 continue
	fi

  echo "Adding system account ${NAME}..."
	useradd -d /home/$NAME -m $NAME

  # Generate an SSH key for this user
  echo "Generate SSH key for user $NAME"
  su - $NAME -c "ssh-keygen -b 2048 -t rsa -f /home/$NAME/.ssh/id_rsa -q -N ''"
  cat /home/$NAME/.ssh/id_rsa.pub >> /home/$NAME/.ssh/authorized_keys
  chmod 600 /home/$NAME/.ssh/authorized_keys
  chown -R $NAME:$NAME /home/$NAME/.ssh
  su - $NAME -c "mkdir /home/$NAME/catalog"

  # Upload SSH key to the keystore
  # ------------------------------
  # key-path convention: {org}/{project}/{user}
  #
  KEYPATH="acme/${PROJECT}/${NAME}/id_rsa"
  rd keys create \
    --path "$KEYPATH" --type privateKey --file "/home/$NAME/.ssh/id_rsa"
  rd keys create \
    --path "$KEYPATH.pub" --type publicKey --file "/home/$NAME/.ssh/id_rsa.pub"

  # Add node definition
  # --------------
  ROLE= INDEX= ICON=
  [[ $NAME =~ ([^0-9]+)([0-9]+) ]] && { ROLE=${BASH_REMATCH[1]} INDEX=${BASH_REMATCH[2]} ; }
  case $ROLE in
    app) ICON=shopping-cart ;;
    db) ICON=hdd ;;
    www) ICON=globe ;;
  esac
  cat >> $ETC/anvils-nodes.yaml <<EOF
${NAME}.anvils.com:
 name: ${NAME}.anvils.com
 tags: $ROLE,anvils
 hostname: localhost
 username: ${NAME}
 description: "A $ROLE server node."
 osFamily: unix
 osName: $(uname -s)
 osVersion: $(uname -r)
 ssh-key-storage-path: "/keys/$KEYPATH"
 "anvils:server-pool": $ROLE
 "anvils:server-pool-id": $INDEX
 "anvils:location": US-East
 "anvils:customer": acme.com
 "anvils:catalog.categories.files": /home/$NAME/catalog
 "ui:icon:name": "glyphicon-$ICON"
---
EOF
    echo "Added node: ${NAME} [role: $ROLE]."
done

chown -R rundeck:rundeck "$ETC"

# List the keys stored for this project.
rd keys list --path acme/${PROJECT}


# Configure SSHD to pass RD environment variables through.
if ! grep -q "^AcceptEnv RD_" /etc/ssh/sshd_config
then
	echo 'AcceptEnv RD_*' >> /etc/ssh/sshd_config
#	/etc/init.d/sshd stop
#	/etc/init.d/sshd start
  service sshd restart
fi

# Create the project now there are keys and model data ready.
# --------------------------

echo "Creating project $PROJECT..."
chown -R rundeck:rundeck /var/rundeck

#
# Create the project

rd projects create -p $PROJECT -- \
  --project.description="manage Anvils online" \
  --project.nodeCache.enabled=false \
  --resources.source.2.config.file=$ETC/anvils-nodes.yaml \
  --resources.source.2.config.generateFileAutomatically=false \
  --resources.source.2.config.includeServerNode=false \
  --resources.source.2.type=file \
  --project.globals.catalog.categories.files=$CATALOG_D

RDECK_NAME=$(awk -F= '/framework.server.name/ {print $2}' /etc/rundeck/framework.properties)
RDECK_HOST=$(awk -F= '/framework.server.hostname/ {print $2}' /etc/rundeck/framework.properties)


cat > $ETC/resources.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>

<project>
  <node name="${RDECK_NAME// /}" hostname="${RDECK_HOST// /}" username="rundeck"
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

echo "List the nodes matching filter, tags: anvils ..."
rd nodes list --filter "tags: anvils" -% "%nodename - %description"

# Add the project level ACLs
echo "Loading project level ACL policy files ..."
for acl in /vagrant/aclpolicy/project/*.aclpolicy
do
    rd projects acls create --file $acl --name $(basename $acl)
done

rd projects acls list


# Run a local ad-hoc command for sanity checking.
echo "Running a adhoc command across the nodes tagged for anvils ..."
rd adhoc -p $PROJECT --follow --filter 'tags: anvils' -- whoami \&\& echo " -- \${node.description}"

# Add jobs, scripts and options
# -----------------------------

mkdir -p /var/www/html/$PROJECT/options
cp -r /vagrant/options/* /var/www/html/$PROJECT/options/
chown -R apache:rundeck /var/www/html/$PROJECT/options

# Load the jobs
echo "Loading jobs for $PROJECT project ..."
for job in $(find /vagrant/jobs -name \*.xml)
do
	rd jobs load --file "$job" --project $PROJECT
done

# List the jobs
rd jobs list -p $PROJECT

# Create a readme
readme=$(mktemp -t "readme.XXXX")
cat >$readme<<EOF

__Welcome!__

This project is used to manage the routine operations for "Anvils Online",
the one place stop for all you anvils buying needs.

Use the top navigation bar to go to [Jobs](/project/anvils/jobs),
[Nodes](/project/anvils/nodes), and [Activity](/project/anvils/activity).

<img width="300"
     src="http://vignette1.wikia.nocookie.net/clubpenguin/images/c/cf/Smoothie_Smash_Anvil.png/revision/latest?cb=20120909235841"/>

### Jobs

Jobs are organized into several areas according to role:

* [catalog](/project/anvils/jobs/catalog): Nightly and adhoc jobs to manage the catalog database
* [ops](/project/anvils/jobs/ops): Restart, status actions for the web and app tiers
* [release](/project/anvils/jobs/release): Promote the software to production

### Nodes

Nodes are tagged according to role.

* [anvils](/project/anvils/nodes?filter=tags%3A anvils): All the nodes used by the anvils site
* [app](/project/anvils/nodes?filter=tags%3A app): the app servers
* [db](/project/anvils/nodes?filter=tags%3A db): the database server
* [www](/project/anvils/nodes?filter=tags%3A www): the web servers


Nodes can use icons for extra effect [glyphicons](http://glyphicons.bootstrapcheatsheets.com/).
For example, you can use a different icon for your node by declaring an attribute for it
(eg, for the "app" nodes, declare the shopping car icon: \`"ui:icon:name": glyphicon-shopping-cart\`).


EOF

rd projects readme put --file $readme --project $PROJECT
# Create a motd
rd projects readme put --motd --text "Watch your feet at all times!" --project $PROJECT



exit $?
