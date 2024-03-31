#!/bin/bash
#
###############################################################
# /**
# * Copyright StrongAuth, Inc. All Rights Reserved.
# *
# * Use of this source code is governed by the GNU Lesser General Public License v2.1
# * The license can be found at https://github.com/StrongKey/fido2/blob/master/LICENSE
# */
###############################################################

. /etc/skfsrc

CURRENT_SKFS_BUILDNO=$(ls -1 $STRONGKEY_HOME/fido/Version* 2> /dev/null | sed -r 's|.*VersionFidoServer-||')

SCRIPT_HOME=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SOFTWARE_HOME=/usr/local/software
STRONGKEY_HOME=/usr/local/strongkey

GLASSFISH_HOME=$STRONGKEY_HOME/payara5/glassfish
MARIA_HOME=$STRONGKEY_HOME/mariadb-10.6.8

GLASSFISH_ADMIN_PASSWORD=adminadmin
MARIA_ROOT_PASSWORD=BigKahuna
MARIA_SKFSDBUSER_PASSWORD=AbracaDabra
SERVICE_LDAP_BIND_PASS=Abcd1234!
SERVICE_LDAP_BASEDN='dc=strongauth,dc=com'

SAKA_DID=1

ROLLBACK=Y

# 4.11.0 Upgrade Variables

function check_exists {
for ARG in "$@"
do
    if [ ! -f $ARG ]; then
        >&2 echo -e "$ARG Not Found. Check to ensure the file exists in the proper location and try again."
        exit 1
    fi
done
}

function version_less_than { # Is first version num less than second version num
        first_num=$(echo $1 | sed 's/[^0-9.]//g') # Strip everything except numbers and periods
        second_num=$(echo $2 | sed 's/[^0-9.]//g')
        if [[ $first_num == $second_num ]]; then
                echo 'false'
        else
                before=$(printf "%s\n" "$first_num" "$second_num")
                sorted=$(sort -V <<<"$before")
                if [[ $before == $sorted ]]; then
                        echo 'true'
                else
                        echo 'false'
                fi
        fi
}

# Check that the script is run as root
if [ "$(whoami)" != "root" ]; then
        >&2 echo "$0 must be run as root"
        exit 1
fi

# Check that variables are set
if [ -z $GLASSFISH_HOME ]; then
        >&2 echo "Variable GLASSFISH_HOME not set correctly."
        exit 1
fi

# Check glassfish status
if ! ps -efww | grep "$GLASSFISH_HOME/modules/glassfish.ja[r]" &>/dev/null; then
        >&2 echo "Glassfish must be running in order to perform this upgrade"
        exit 1
fi

# Get GlassFish admin password
echo "$GLASSFISH_ADMIN_PASSWORD" > /tmp/password
while ! $GLASSFISH_HOME/bin/asadmin --user admin --passwordfile /tmp/password list . &> /dev/null; do
        echo -n "This upgrade requires the glassfish 'admin' password. Please enter the password now: "
        echo
        read -s GLASSFISH_ADMIN_PASSWORD
        echo "AS_ADMIN_PASSWORD=$GLASSFISH_ADMIN_PASSWORD" > /tmp/password
done

# Check that the SKFS is at least version 4.10.0
if [ $(version_less_than $CURRENT_SKFS_BUILDNO "4.10.0") = "true" ]; then
        >&2 echo "SKFS must be at least version 4.10.0 in order to upgrade using this script."
        exit 1
fi

# Determine which package manager is on the system
YUM_CMD=$(which yum  2>/dev/null)
APT_GET_CMD=$(which apt-get 2>/dev/null)

# Undeploy SKFS
echo
echo "Undeploying old skfs build..."
$GLASSFISH_HOME/bin/asadmin --user admin --passwordfile /tmp/password undeploy fidoserver

# Start upgrade to 4.11.0
if [ $(version_less_than $CURRENT_SKFS_BUILDNO "4.11.0") = "true" ]; then
        echo "Upgrading to 4.11.0"

        # Nothing needed to be done in 4.11.0 upgrade other than undeploy the old fidoserver build and deploy the new fidoserver build

        mv $STRONGKEY_HOME/fido/VersionFidoServer-4.10.0 $STRONGKEY_HOME/fido/VersionFidoServer-4.11.0
fi # End of 4.11.0 Upgrade

# Start Glassfish
echo
echo "Starting Glassfish..."
service glassfishd restart

#adding sleep to ensure glassfish starts up correctly
sleep 10

# Deploy NEW SKFS
echo
echo "Deploying new skfs build..."

check_exists "$SCRIPT_HOME/fidoserver.ear"

cp $SCRIPT_HOME/fidoserver.ear /tmp
# Deploy SKFS
$GLASSFISH_HOME/bin/asadmin --user admin --passwordfile /tmp/password deploy /tmp/fidoserver.ear

rm /tmp/fidoserver.ear
rm /tmp/password

echo
echo "Restarting glassfish..."
service glassfishd restart

echo
echo "Upgrade finished!"

exit 0
