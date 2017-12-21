#!/bin/bash
EXPECTED_ARGS=3
E_BADARGS=65
if [ $# -lt 1 ]
then
  echo "Usage: `basename $0` <serviceID> <ACL_ID> <API Key>"
  echo "Example: `basename $0` 1f1BjH8xCMPZwK7fTRLUpH 2cFflPOskFLhmnZJEfUake \$FASTLY_TOKEN"
    exit $E_BADARGS
fi
if [ $# -gt $EXPECTED_ARGS ]
then
echo "Too many arguments"
        exit $E_BADARGS
fi
SERVICE_ID=$1
ACL_ID=$2
API_KEY=$3


echo "Cleaning current TOR IP list"
ACL_IDS=$(curl -s -H "Fastly-Key: $API_KEY" -H "Content-Type: application/json" -H "Accept: application/json" -XGET "https://api.fastly.com/service/$SERVICE_ID/acl/$ACL_ID/entries" | egrep -o '"id"\:\"(.*?)\"' | cut -d : -f 2 | tr -d '"')

CLEANUP_ACL="{
  \"entries\": [
"

IP_COUNT=0
for id in $ACL_IDS
do
  CLEANUP_ACL="$CLEANUP_ACL {
      \"op\": \"delete\",
      \"id\": \"$id\"
    },"
    IP_COUNT=$(($IP_COUNT+1))
done

#add trailing json closers
CLEANUP_ACL="$CLEANUP_ACL ]
}"

#remove last ,
CLEANUP_ACL=$(echo $CLEANUP_ACL | sed 's/\}\, \] \}/} ] }/g')

echo "Cleaning $IP_COUNT IPs from ACL ID: $ACL_ID"
#Making patch call to delete all old ACLs
echo $CLEANUP_ACL > .cleanup.json
curl -w "\n" -s -H "Fastly-Key: $API_KEY" -H "Content-Type: application/json" -H "Accept: application/json" -XPATCH "https://api.fastly.com/service/$SERVICE_ID/acl/$ACL_ID/entries" -d @.cleanup.json

echo "Retriving Lastest TOR IP list"
TOR_IP=$(curl -s https://check.torproject.org/exit-addresses | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
#add init json struct
ACL="{
  \"entries\": [
"
#go through each IP and create an entry for it
IP_COUNT=0
for ip in $TOR_IP
do
  ACL="$ACL {
      \"op\": \"create\",
      \"ip\": \"$ip\",
      \"subnet\": \"32\"
    },"
    IP_COUNT=$(($IP_COUNT+1))
done
echo "Retrived $IP_COUNT IPs from TOR"
#add trailing json closers
ACL="$ACL ]
}"

#remove last ,
ACL=$(echo $ACL | sed 's/\}\, \] \}/} ] }/g')

echo "Adding IPs to Fastly"
#Making patch call to add new IPs
echo $ACL > .tor_acl.json
curl -w "\n" -s -H "Fastly-Key: $API_KEY" -H "Content-Type: application/json" -H "Accept: application/json" -XPATCH "https://api.fastly.com/service/$SERVICE_ID/acl/$ACL_ID/entries" -d @.tor_acl.json
