#!/bin/bash
# A script to back up a Bitwarden vault with attachments and store the data in a Keepass database

cleanup() {
    unset BW_CLIENTID
    unset BW_CLIENTSECRET
    unset BW_MASTER
    unset KP_PASS
    rm -r $SAVE_FOLDER
    bw lock
    if [ "$LOGOUT" = true ] ; then
        bw logout
    fi
}

#Set locations to save export files
SAVE_FOLDER="./export/"
SAVE_FOLDER_ATTACHMENTS="./export/attachments/"

mkdir -p $SAVE_FOLDER_ATTACHMENTS

## create and delete them dynamically each time? 

echo "Starting export script..."

#Prompt for keychain password
echo "Enter keychain password: "
read -rs KEYCHAIN_PASSWORD
echo 

security unlock-keychain -p "$KEYCHAIN_PASSWORD" bwstuff.keychain

echo "Reading credentials..."
BW_CLIENTID=$(security find-generic-password -w -a api-client-id -g bwstuff.keychain)
BW_CLIENTSECRET=$(security find-generic-password -w -a api-client-secret -g bwstuff.keychain)
BW_MASTER=$(security find-generic-password -w -a master -g bwstuff.keychain)
KP_PASS=$(security find-generic-password -w -s keepass -g bwstuff.keychain)

export BW_CLIENTID
export BW_CLIENTSECRET
export BW_MASTER

unset KEYCHAIN_PASSWORD
security lock-keychain bwstuff.keychain

echo "Connecting to Bitwarden..."

LOGOUT=false

#Login user if not already authenticated
if [[ $(bw status | jq -r .status) == "unauthenticated" ]]
then 
    echo "Performing login..."
    bw login --apikey --quiet
    LOGOUT=true
fi

if [[ $(bw status | jq -r .status) == "unauthenticated" ]]
then 
    >&2 echo "ERROR: Failed to authenticate!"
    cleanup
    echo
    exit 1
fi

BW_SESSION=$(bw unlock --passwordenv BW_MASTER --raw)

#Clear credentials
unset BW_CLIENTID
unset BW_CLIENTSECRET
unset BW_MASTER

#Verify that unlock succeeded
if [[ $BW_SESSION == "" ]]
then 
    >&2 echo "ERROR: Failed to unlock!"
    cleanup
    exit 1
else
    echo "Login successful!"
fi

export BW_SESSION

#Export the personal vault 
echo
echo "Exporting personal vault..."
bw export --format json --output $SAVE_FOLDER

#Download all attachments (file backup)
if [[ $(bw list items | jq -r '.[] | select(.attachments != null)') != "" ]]
then
    echo
    echo "Saving attachments..."
    bash <(bw list items | jq -r '.[] 
    | select(.attachments != null) 
    | "bw get attachment \"\(.attachments[].fileName)\" --itemid \(.id) --output \"'"$SAVE_FOLDER_ATTACHMENTS"'\(.name)/\""' )
else
    echo
    echo "No attachments exist, so nothing to export."
fi 

echo
echo "Vault export complete."

tar -zcf export.tar.gz $SAVE_FOLDER

echo
echo "Starting import..."

if echo "$KP_PASS" | keepassxc-cli attachment-import -f -y 2 ~/codes.kdbx bw export.tar.gz export.tar.gz; 
then
    rm export.tar.gz 
fi

echo
echo "Cleaning up..."

cleanup

echo
echo "Backup complete."
