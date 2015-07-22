#!/bin/bash
#/ usage: status.sh ?dir?

set -eu

(( $# != 1 )) && {
	grep '^#/ usage:' <"$0" | cut -c4- >&2
	exit 2	
}
DIR=$1
[[ ! -f $DIR/pid ]] && { echo DOWN; exit 1; }

PID=$(< $DIR/pid)

if [[ -z "${PID:-}" ]]
then
	echo "DOWN"; exit 1;
else 
	echo "RUNNING"
fi	

exit $?
