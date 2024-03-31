###############################################################
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License, as published by the Free Software Foundation and
# available at https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html,
# version 2.1.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# Copyright (c) 2001-2021 StrongAuth, Inc.
#
# $Date$
# $Revision$
# $Author$
# $URL$
#
################################################################

. /etc/bashrc

SCRIPT_HOME=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OPERATION=$1
SAKA_DID=
SERVICE_LDAP_BIND_PASS=
SERVICE_LDAP_BIND_PASS_DEFAULT="Abcd1234!"
SERVICE_LDAP_BASEDN='dc=strongauth,dc=com'
LDAP_USER=
LDAP_GROUPS=

usage_general="
Usage: 
${0##*/} getUsers
${0##*/} getGroups
${0##*/} getUserGroups
${0##*/} addUser
${0##*/} addGroup
${0##*/} addUserToGroup
${0##*/} removeUserFromGroup
${0##*/} changeUserPassword
${0##*/} deleteUser
"
options="
Options:
        -did, --domainid
                The ID for the domain to perform this LDAP action on.

        -u, --user
                The LDAP user to perform this LDAP operation on.

        -g, --group
                The LDAP group to perform this operation on.

        -p, --password
                The LDAP bind password to access the local LDAP.
                If this flag is omitted, this script will attempt to use the default LDAP password, 'Abcd1234!'. If this fails, the password will be prompted.
                If the value of this flag is incorrect, this script will prompt for the bind password.
"

usage_getUsers="
Usage:
        ${0##*/} getUsers -did <domain id> [-p <LDAP bind password>]

Description:
        This operation returns the list of users that exist within the LDAP for the provided domain.
$options"

usage_getGroups="
Usage:
        ${0##*/} getGroups -did <domain id> [-p <LDAP bind password>]

Description:
        This operation returns the list of groups that exist within the LDAP for the provided domain.
$options"

usage_getUserGroups="
Usage:
        ${0##*/} getUserGroups -did <domain id> -u <LDAP user> [-p <LDAP bind password>]

Description:
        This operation returns the LDAP groups that the specified user is a member of.
$options"

usage_addUser="
Usage:
        ${0##*/} addUser -did <domain id> -u <LDAP user> [-p <LDAP bind password>]

Description:
        This operation creates a LDAP user.
$options"

usage_addGroup="
Usage:
        ${0##*/} addGroup -did <domain id> -g <LDAP group> [-u <LDAP user>] [-p <LDAP bind password>]

Description:
        This operation creates a LDAP group. Each LDAP group must contain at least one member, so a LDAP user must either be specified in the command or when prompted.
$options"

usage_addUserToGroup="
Usage:
        ${0##*/} addUserToGroup -did <domain id> -u <LDAP user> -g <LDAP group(s)> [-p <LDAP bind password>]

Description:
        This operation adds the specified user as a member of the provided comma-separated list of groups.
$options"

usage_removeUserFromGroup="
Usage:
        ${0##*/} removeUserFromGroup -did <domain id> -u <LDAP user> -g <LDAP group(s)> [-p <LDAP bind password>]

Description:
        This operation removes the specified user from the provided comma-separated list of groups.
$options"

usage_changeUserPassword="
Usage:
        ${0##*/} changeUserPassword -did <domain id> -u <LDAP user> [-p <LDAP bind password>]

Description:
        This operation changes the password for the specified LDAP user.
$options"

usage_deleteUser="
Usage:
        ${0##*/} deleteUser -did <domain id> -u <LDAP user> [-p <LDAP bind password>]

Description:
        This operation removes the specified user from all groups they are a member of and deletes the user.
$options"

# Check operation
if [ -z "$OPERATION" ]; then # If no operation specified, print general usage and quit
        echo "$usage_general"
        exit 0
else
        if [[ ! "$usage_general" =~ "$OPERATION" ]]; then # If operation provided does not exist, print messange and general usage and quit
                echo "Specified operation does not exist."
                echo "$usage_general"
                exit 1
        fi

        shift

        # Check no input has been added after the operation to display operation usage
        if [ -z $1 ]; then
                operation_usage="usage_$OPERATION"
                echo "${!operation_usage}"
                exit 0
        fi
fi

# Option handling
while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
        -h | --help )
                operation_usage="usage_$OPERATION"
                echo "${!operation_usage}"
                exit 0
                ;;
        -did | --domainid)
                shift;
                SAKA_DID="$1"
                ;;
        -p | --password )
                shift;
                SERVICE_LDAP_BIND_PASS="$1"
                ;;
        -u | --user )
                shift;
                LDAP_USER="$1"
                ;;
        -g | --group )
                shift;
                LDAP_GROUPS="$1"
                ;;
esac; shift; done
if [[ "$1" == '--' ]]; then shift; fi

# General input checks
if [ -z $SAKA_DID ]; then
        echo "No domain ID specified. Please include the -did flag in your command."
        operation_usage="usage_$OPERATION"
        echo "${!operation_usage}"
        exit 1
fi

if [ -z $SERVICE_LDAP_BIND_PASS ]; then
        SERVICE_LDAP_BIND_PASS=$SERVICE_LDAP_BIND_PASS_DEFAULT
fi
# Check if the provided password is correct
ldapwhoami -x -w  "$SERVICE_LDAP_BIND_PASS" -D "cn=Manager,$SERVICE_LDAP_BASEDN" 2> /tmp/Error 1> /dev/null
ERROR=$(</tmp/Error)
rm /tmp/Error
if [ -n "$ERROR" ]; then
        if [ -n $SERVICE_LDAP_BIND_PASS ]; then
                echo "Provided LDAP bind password incorrect."
                echo -n "Please re-enter LDAP bind password: "
        else
                echo -n "Please enter the LDAP bind password: "
        fi
        read -s SERVICE_LDAP_BIND_PASS
        echo ""
        ldapwhoami -x -w  "$SERVICE_LDAP_BIND_PASS" -D "cn=Manager,$SERVICE_LDAP_BASEDN" 2> /tmp/Error 1> /dev/null
        ERROR=$(</tmp/Error)
        rm /tmp/Error
        if [ -n "$ERROR" ]; then
                echo "Incorrect LDAP bind password. Please check the password and try again."
                exit 1
        fi
fi

case $OPERATION in

        getUsers )
                echo "$(ldapsearch -h localhost -x -b "$SERVICE_LDAP_BASEDN" "(cn=*)" | grep "$SAKA_DID, users" | awk -F ' ' '{print substr($2, 1, length($2)-1)}')"
                ;;

        getGroups )
                echo "$(ldapsearch -h localhost -x -b "$SERVICE_LDAP_BASEDN" "(cn=*)" | grep "$SAKA_DID, groups" | awk -F ' ' '{print substr($2, 1, length($2)-1)}')"
                ;;

        getUserGroups )
                if [[ -z "$LDAP_USER" ]]; then
                        echo "Missing user option."
                        operation_usage="usage_$OPERATION"
                        echo "${!operation_usage}"
                        exit 1
                fi

                if [[ ! $(ldapsearch -Y external -H ldapi:/// -b "$SERVICE_LDAP_BASEDN" cn="$LDAP_USER" -LLL 2> /dev/null) =~ "$LDAP_USER" ]]; then
                        echo "LDAP user '$LDAP_USER' does not exist for domain $SAKA_DID."
                        exit 1
                fi

                GROUPS_OUTPUT=$(ldapsearch -o ldif-wrap=no -LLL -Y external -H ldapi:/// -b "$SERVICE_LDAP_BASEDN" "uniqueMember=cn=$LDAP_USER,did=$SAKA_DID,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN" 2> /dev/null | grep dn --color=never | sed 's/dn: //g' | sed 's/--//g')
                if [[ -z $GROUPS_OUTPUT ]]; then
                        echo "User '$LDAP_USER' is not a part of any groups."
                else
                        echo "User '$LDAP_USER' is a part of the following groups:"
                        echo ""
                        echo "$GROUPS_OUTPUT"
                fi
                exit 0
                ;;

        addUser )
                if [[ -z "$LDAP_USER" ]]; then
                        echo "Missing user option."
                        operation_usage="usage_$OPERATION"
                        echo "${!operation_usage}"
                        exit 1
                fi

                echo "Enter Password for New User:"
                PASSWORD=$(slappasswd -h {SSHA})
                if [ -z "$PASSWORD" ]; then
                        exit 1
                fi

                cat > /tmp/ldapuser.ldif << LDAPUSER
dn: cn=$LDAP_USER,did=$SAKA_DID,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN
changetype: add
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: top
userPassword: $PASSWORD
givenName: $LDAP_USER
cn: $LDAP_USER
sn: $LDAP_USER
LDAPUSER
                ldapmodify -x -w  "$SERVICE_LDAP_BIND_PASS" -D "cn=Manager,$SERVICE_LDAP_BASEDN" -f /tmp/ldapuser.ldif 2> /tmp/Error
                ERROR=$(</tmp/Error)
                rm /tmp/ldapuser.ldif /tmp/Error
                if [ -z "$ERROR" ]; then
                        echo "Added User '$LDAP_USER'"
                        # Print out for groups and a prompt to run addusertogroup
                        echo ""
                        tput setaf 1; echo "This User is currently a Member of NO Groups!"
                        tput sgr0; echo "Please use the addUserToGroup operation and specify which of the following LDAP groups in domain $SAKA_DID you wish for $LDAP_USER to be a member of:"
                        echo ""
                        echo "$(ldapsearch -h localhost -x -b "$SERVICE_LDAP_BASEDN" "(cn=*)" | grep "$SAKA_DID, groups" | awk -F ' ' '{print substr($2, 1, length($2)-1)}')"
                        echo ""
                        exit 0
                else
                        echo $ERROR
                        exit 1
                fi
                ;;

        addGroup )
                if [[ -z "$LDAP_GROUPS" ]]; then
                        echo "Missing group option."
                        operation_usage="usage_$OPERATION"
                        echo "${!operation_usage}"
                        exit 1
                fi

                # If user provided, add user to group. If user not provided, display all users in the domain and prompt for a user.
                if [ -n "$LDAP_USER" ]; then
                        while [[ ! $(ldapsearch -Y external -H ldapi:/// -b "$SERVICE_LDAP_BASEDN" cn="$LDAP_USER" -LLL 2> /dev/null) =~ "$LDAP_USER" ]]; do
                                echo "LDAP user '$LDAP_USER' does not exist for domain $SAKA_DID. Please choose a user to be a member of the new group:"
                                echo ""
                                echo "$(ldapsearch -h localhost -x -b "$SERVICE_LDAP_BASEDN" "(cn=*)" | grep "$SAKA_DID, users" | awk -F ' ' '{print substr($2, 1, length($2)-1)}')"
                                echo ""
                                read -p "User to be added to '$LDAP_GROUPS': " LDAP_USER
                                echo ""
                        done
                else
                        echo "Upon creation, each LDAP group must contain at least 1 member. Please specify an existing user for domain $SAKA_DID to add to this new group:"
                        echo ""
                        echo "$(ldapsearch -h localhost -x -b "$SERVICE_LDAP_BASEDN" "(cn=*)" | grep "$SAKA_DID, users" | awk -F ' ' '{print substr($2, 1, length($2)-1)}')"
                        echo ""
                        read -p "User to be added to the new LDAP group '$LDAP_GROUPS': " LDAP_USER
                        echo ""
                        while [[ ! $(ldapsearch -Y external -H ldapi:/// -b "$SERVICE_LDAP_BASEDN" cn="$LDAP_USER" -LLL 2> /dev/null) =~ "$LDAP_USER" ]]; do
                                echo "LDAP user '$LDAP_USER' does not exist for domain $SAKA_DID. Please choose a user to be a member of the new group:"
                                echo ""
                                echo "$(ldapsearch -h localhost -x -b "$SERVICE_LDAP_BASEDN" "(cn=*)" | grep "$SAKA_DID, users" | awk -F ' ' '{print substr($2, 1, length($2)-1)}')"
                                echo ""
                                read -p "User to be added to '$LDAP_GROUPS': " LDAP_USER
                                echo ""
                        done
                fi

                cat > /tmp/FidoServiceGroup.ldif <<-LDAPGROUP
dn: cn=$LDAP_GROUPS,did=$SAKA_DID,ou=groups,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN
objectClass: groupOfUniqueNames
objectClass: top
cn: $LDAP_GROUPS
uniqueMember: cn=$LDAP_USER,did=$SAKA_DID,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN
LDAPGROUP

                /bin/ldapadd -x -w $SERVICE_LDAP_BIND_PASS -D "cn=Manager,$SERVICE_LDAP_BASEDN" -f /tmp/FidoServiceGroup.ldif 2> /tmp/Error
                ERROR=$(</tmp/Error)
                rm /tmp/FidoServiceGroup.ldif /tmp/Error
                if [ -z "$ERROR" ]; then
                        echo "Added Group: '$LDAP_GROUPS'"
                        echo ""
                        exit 0
                else
                        echo $ERROR
                        exit 1
                fi
                ;;

        addUserToGroup )
                if [[ -z "$LDAP_USER" || -z "$LDAP_GROUPS" ]]; then
                        echo "Missing user and/or group option(s)."
                        operation_usage="usage_$OPERATION"
                        echo "${!operation_usage}"
                        exit 1
                fi

                if [[ ! $(ldapsearch -Y external -H ldapi:/// -b "$SERVICE_LDAP_BASEDN" cn="$LDAP_USER" -LLL 2> /dev/null) =~ "$LDAP_USER" ]]; then
                        echo "LDAP user '$LDAP_USER' does not exist for domain $SAKA_DID."
                        exit 1
                fi

                IFS=','
                read -a groupsarr <<< "$LDAP_GROUPS"
                for group in "${groupsarr[@]}";
                do
                        if [[ "$(ldapsearch -h localhost -x -b "$SERVICE_LDAP_BASEDN" "(cn=*)" | grep "$SAKA_DID, groups" | awk -F ' ' -v ORS='' '{print $2}')" == *"$group"* ]]; then
                                cat > /tmp/ldapgroup.ldif << LDAPUSER
dn: cn=$group,did=$SAKA_DID,ou=groups,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN
changetype: modify
add: uniqueMember
uniqueMember: cn=$LDAP_USER,did=$SAKA_DID,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN
LDAPUSER
                                ldapmodify -x -w  "$SERVICE_LDAP_BIND_PASS" -D "cn=Manager,$SERVICE_LDAP_BASEDN" -f /tmp/ldapgroup.ldif 2> /tmp/Error
                                ERROR=$(</tmp/Error)
                                rm /tmp/ldapgroup.ldif /tmp/Error
                                if [ -z "$ERROR" ]; then
                                        echo "Added User '$LDAP_USER' to Group '$group'"
                                        echo ""
                                else
                                        if [[ "$ERROR" =~ "already exists" ]]; then
                                                echo "User '$LDAP_USER' is already a part of Group '$group'"
                                                echo ""
                                        else
                                                #echo $ERROR
                                                echo "LDAP group '$group' does not exist for domain $SAKA_DID."
                                                echo ""
                                        fi
                                fi
                        else
                                echo "LDAP group '$group' does not exist for domain $SAKA_DID."
                                echo ""
                        fi
                done
                echo "Done!"
                exit 0
                ;;

        removeUserFromGroup )
                if [[ -z "$LDAP_USER" || -z "$LDAP_GROUPS" ]]; then
                        echo "Missing user and/or group option(s)."
                        operation_usage="usage_$OPERATION"
                        echo "${!operation_usage}"
                        exit 1
                fi

                if [[ ! $(ldapsearch -Y external -H ldapi:/// -b "$SERVICE_LDAP_BASEDN" cn="$LDAP_USER" -LLL 2> /dev/null) =~ "$LDAP_USER" ]]; then
                        echo "LDAP user '$LDAP_USER' does not exist for domain $SAKA_DID."
                        exit 1
                fi

                IFS=','
                read -a groupsarr <<< "$LDAP_GROUPS"
                for group in "${groupsarr[@]}";
                do
                        if [[ "$(ldapsearch -h localhost -x -b "$SERVICE_LDAP_BASEDN" "(cn=*)" | grep "$SAKA_DID, groups" | awk -F ' ' -v ORS='' '{print $2}')" == *"$group"* ]]; then
                                cat > /tmp/ldapgroup.ldif << LDAPUSER
dn: cn=$group,did=$SAKA_DID,ou=groups,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN
changetype: modify
delete: uniqueMember
uniqueMember: cn=$LDAP_USER,did=$SAKA_DID,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN
LDAPUSER
                                ldapmodify -x -w  "$SERVICE_LDAP_BIND_PASS" -D "cn=Manager,$SERVICE_LDAP_BASEDN" -f /tmp/ldapgroup.ldif 2> /tmp/Error
                                ERROR=$(</tmp/Error)
                                rm /tmp/ldapgroup.ldif /tmp/Error
                                if [ -z "$ERROR" ]; then
                                        echo "Removed User '$LDAP_USER' from Group '$group'"
                                        echo ""
                                else
                                        if [[ "$ERROR" =~ "uniqueMember: no such value" ]]; then
                                                echo "User '$LDAP_USER' is not a part of Group '$group'"
                                                echo ""
                                        else
                                                #echo $ERROR
                                                echo "Cannot remove last member of LDAP group '$group'. Each LDAP group must contain at least 1 member."
                                                echo ""
                                        fi
                                fi
                        else
                                echo "LDAP group '$group' does not exist for domain $SAKA_DID."
                                echo ""
                        fi
                done
                echo "Done!"
                exit 0
                ;;

        changeUserPassword )
                if [[ -z "$LDAP_USER" ]]; then
                        echo "Missing user option."
                        operation_usage="usage_$OPERATION"
                        echo "${!operation_usage}"
                        exit 1
                fi

                if [[ ! $(ldapsearch -Y external -H ldapi:/// -b "$SERVICE_LDAP_BASEDN" cn="$LDAP_USER" -LLL 2> /dev/null) =~ "$LDAP_USER" ]]; then
                        echo "LDAP user '$LDAP_USER' does not exist for domain $SAKA_DID."
                        exit 1
                fi

                #PASSWORD_CHANGE_RESULT=$(ldappasswd -v -x -w  "$SERVICE_LDAP_BIND_PASS" -D "cn=Manager,$SERVICE_LDAP_BASEDN" -S "cn=$LDAP_USER,did=$SAKA_DID,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN")
                ldappasswd -x -w  "$SERVICE_LDAP_BIND_PASS" -D "cn=Manager,$SERVICE_LDAP_BASEDN" -S "cn=$LDAP_USER,did=$SAKA_DID,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN"
                if [ $? -eq 1 ]; then
                        echo "Change Password Failed for User: '$LDAP_USER'"
                        exit 1
                fi
                echo "Changed Password for User: '$LDAP_USER'"
                exit 0
                ;;

        deleteUser )
                if [[ -z "$LDAP_USER" ]]; then
                        echo "Missing user option."
                        operation_usage="usage_$OPERATION"
                        echo "${!operation_usage}"
                        exit 1
                fi

                if [[ ! $(ldapsearch -Y external -H ldapi:/// -b "$SERVICE_LDAP_BASEDN" cn="$LDAP_USER" -LLL 2> /dev/null) =~ "$LDAP_USER" ]]; then
                        echo "LDAP user '$LDAP_USER' does not exist for domain $SAKA_DID."
                        exit 1
                fi

                IFS=','
                read -a groupsarr <<< "$(ldapsearch -h localhost -x -b "$SERVICE_LDAP_BASEDN" "(cn=*)" | grep "$SAKA_DID, groups" | awk -F ' ' -v ORS='' '{print $2}')"
                for group in "${groupsarr[@]}";
                do
                        cat > /tmp/ldapgroup.ldif << LDAPUSER
dn: cn=$group,did=$SAKA_DID,ou=groups,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN
changetype: modify
delete: uniqueMember
uniqueMember: cn=$LDAP_USER,did=$SAKA_DID,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN
LDAPUSER
                        ldapmodify -x -w  "$SERVICE_LDAP_BIND_PASS" -D "cn=Manager,$SERVICE_LDAP_BASEDN" -f /tmp/ldapgroup.ldif 2> /tmp/Error 1> /dev/null
                        ERROR=$(</tmp/Error)
                        rm /tmp/ldapgroup.ldif /tmp/Error
                        if [ -z "$ERROR" ]; then
                                echo "Removed User '$LDAP_USER' from Group '$group'"
                        fi
                done
                ldapdelete -x -w  "$SERVICE_LDAP_BIND_PASS" -D "cn=Manager,$SERVICE_LDAP_BASEDN" "cn=$LDAP_USER,did=$SAKA_DID,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,$SERVICE_LDAP_BASEDN" 2> /tmp/Error 1> /dev/null
                ERROR=$(</tmp/Error)
                rm /tmp/Error
                if [ -z "$ERROR" ]; then
                        echo "Deleted User: '$LDAP_USER'"
                fi
                exit 0
                ;;

        * )
                echo "This script should not have reached this point. Please check your inputs and try again."
                ;;
esac
