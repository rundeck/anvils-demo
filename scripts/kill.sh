#!/bin/bash
#/ usage: kill.sh ?dir?

set -e
set -u

[[ $# != 1 ]] && {
	grep '^#/ usage:' <"$0" | cut -c4- >&2
	exit 2	
}
DIR=$1



echo 'Web killed!'
