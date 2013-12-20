#!/bin/bash
#/ usage: status.sh ?dir?

set -e
set -u

[[ $# != 1 ]] && {
	grep '^#/ usage:' <"$0" | cut -c4- >&2
	exit 2	
}
DIR=$1
[[ ! -f $DIR/pid ]] && { echo DOWN; exit 1; }

PID=$(cat $DIR/pid)

if [[ -z "$PID" ]]
then
	echo "DOWN"; exit 1;
else 
	echo "- RUNNING (pid=$PID)"
fi	

exit $?
