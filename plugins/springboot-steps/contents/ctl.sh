#!/usr/bin/env bash
set -eu

EXECUTABLE=$RD_CONFIG_JARFILE

action() {
   printf "Running $EXECUTABLE $1"
}

case $1 in
	start)   echo "$(action $1) ... OK" ;;
    stop)    echo "$(action $1) ... OK" ;;
    restart) echo "$(action $1) ... OK" ;;
	status)   echo "$(action $1) ... OK" ;;
	deploy-jar) echo "deploying $RD_CONFIG_JARFILE ... OK" ;;
    *) echo "$0: unrecognized sub-command: '$1'" ; exit 2 ;;
esac

exit $?
