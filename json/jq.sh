#!/bin/sh

ext="*.json"

if [ ! -d "./jq" ]; then
    mkdir "jq"; retval=$?
    echo "mkdir[$retval]"
fi

for json in $ext
do
    echo $json
    tail -1 $json | jq . > "jq/$json"
done
