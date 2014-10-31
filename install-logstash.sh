#!/usr/bin/env bash

set -e 
set -u

LOGSTASH_JAR="https://logstash.objects.dreamhost.com/release/logstash-1.2.1-flatjar.jar"

if ! grep -q logstash /etc/group
then groupadd logstash
fi

if ! grep -q logstash /etc/passwd
then useradd -m -d /var/lib/logstash -g logstash logstash
fi


#curl -s --fail -L "$LOGSTASH_JAR" -o /var/lib/logstash/logstash.jar
cp /vagrant/logstash-*.jar /var/lib/logstash/logstash.jar

curl -s --fail -L "http://cookbook.logstash.net/recipes/using-init/logstash.sh" -o /etc/init.d/logstash

sed -i \
	-e "s,LOCATION=.*,LOCATION=/var/lib/logstash,g" \
	-e "s,CONFIG_DIR=.*,CONFIG_DIR=/var/lib/logstash/etc,g" \
	-e "s,LOGFILE=.*,LOGFILE=/var/log/logstash/logstash.log,g" \
	-e "s,JARNAME=.*,JARNAME=logstash.jar,g" \
	/etc/init.d/logstash
chmod +x /etc/init.d/logstash

mkdir -p /var/log/logstash
chown logstash:logstash /var/log/logstash

mkdir -p /var/lib/logstash/etc
cat >>/var/lib/logstash/etc/rundeck-logstash.conf<<EOF
input {

  tcp {
    debug => true 
    host => "localhost"
    mode => server
    port => 9700
    tags => ["rundeck"]
    type => "rundeck"
  }

}

output { 
  stdout { }

  elasticsearch { embedded => true }
}
EOF

chown -R logstash:logstash /var/lib/logstash

if [[ -f /var/lib/rundeck/libext/LogstashPlugin.groovy ]]
then
curl -s --fail -L https://raw.github.com/gschueler/rundeck-logstash-plugin/master/LogstashPlugin.groovy -o /var/lib/rundeck/libext/LogstashPlugin.groovy
echo "Logstash plugin installed."
fi

if ! grep -q LogstashPlugin /etc/rundeck/rundeck-config.properties
then
cat >>/etc/rundeck/rundeck-config.properties<<EOF
rundeck.execution.logs.streamingWriterPlugins=LogstashPlugin
EOF
echo "configured rundeck to use logstash plugin."
fi

if ! grep -q LogstashPlugin /etc/rundeck/framework.properties
then
cat >>/etc/rundeck/framework.properties<<EOF
framework.plugin.StreamingLogWriter.LogstashPlugin.port=9700
framework.plugin.StreamingLogWriter.LogstashPlugin.host=localhost
EOF
echo "Configured rundeck to logstash: localhost:9700"
fi


# Start up logstash
# ----------------
#
set +e
if ! /etc/init.d/logstash status
then
    echo "Starting logstash..."
    /etc/init.d/logstash start 

    let count=0
    let max=18
    while [ $count -le $max ]
    do 
        if ! /etc/init.d/logstash status
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

echo "logstash started."

exit $?

