#!/bin/bash

set -eu


# Software install
# ----------------

# Apache httpd
yum install -y httpd

# Create directory for webdav lock files
mkdir -p /var/lock/apache
chown apache:apache /var/lock/apache

# Create a login for accessing the webdav content.
(echo -n "admin:DAV-upload:" && echo -n "admin:DAV-upload:admin" |
	md5sum |
	awk '{print $1}' ) >> /etc/httpd/webdav.passwd

# Generate the configuration into the includes directory.
cat > /etc/httpd/conf.d/webdav.conf<<EOF
DavLockDB /var/lock/apache/DavLock

Alias /rundeck "/var/www/html"

<Directory /var/www/html>
    Dav On
    Order Allow,Deny
    Allow from all

    AuthType Digest
    AuthName DAV-upload

    # You can use the htdigest program to create the password database:
    #   htdigest -c "/etc/httpd/webdav.passwd" DAV-upload admin
    AuthUserFile "/etc/httpd/webdav.passwd"
    AuthDigestProvider file

    # Allow universal read-access, but writes are restricted
    # to the admin user.
    <LimitExcept GET OPTIONS>
        require user admin
    </LimitExcept>

</Directory>
EOF

# Create subdirectories for webdav content.
mkdir -p /var/www/html/anvils
cat > /var/www/html/anvils/hi.txt<<EOF
hi
EOF
chown -R rundeck:apache /var/www/html/anvils

# start the httpd service
service httpd start

# Ensure httpd is started on reboot of machine
chkconfig httpd on


# turn off fire wall, Centos 6
# service iptables stop
# chkconfig iptables off

# turn off fire wall, Centos 7
systemctl disable firewalld
systemctl stop firewalld
