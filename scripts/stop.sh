#!/bin/bash
#/ usage: stop.sh ?dir? ?method? 

set -eu

(( $# != 2 )) && {
	grep '^#/ usage:' <"$0" | cut -c4- >&2
	exit 2
}
DIR=$1
METHOD=$2

if [[ -f $DIR/pid ]]
then	
	PID=$(< $DIR/pid)	
	echo "kill $PID"
	rm -f $DIR/pid
	echo "- Web stopped (pid=${PID}) using method: $METHOD"
fi

