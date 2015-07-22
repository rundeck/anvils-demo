#!/bin/bash
#/ usage: start.sh ?dir?

set -eu

(( $# != 1 )) && {
	grep '^#/ usage:' <"$0" | cut -c4- >&2
	exit 2	
}
DIR=$1

mkdir -p $DIR
echo $$ > $DIR/pid

echo "- Web started (pid=$$)" | tee -a $DIR/log
