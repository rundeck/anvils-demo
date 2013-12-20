#!/bin/bash
#/ usage: stop.sh ?dir? ?method? 

set -e
set -u

[[ $# != 2 ]] && {
	grep '^#/ usage:' <"$0" | cut -c4- >&2
	exit 2
}
DIR=$1
METHOD=$2

if [[ -f $DIR/pid ]]
then	
	pid=$(cat $DIR/pid)	
	# kill $pid ;
	rm -f $DIR/pid
	echo "- Web stopped (pid=${pid}) using method: $METHOD"
fi

