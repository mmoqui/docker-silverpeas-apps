#/usr/bin/env bash

REALM=SILVERPEAS.IO

if [ $# -eq 2 ]; then
    service="$2/$1@${REALM}"

    set -e

    docker exec -it kdc kadmin.local -q "addprinc -randkey ${service}"
    docker exec -it kdc kadmin.local -q "ktadd -k /${2}_${1}.keytab ${service}"
    docker cp kdc:/${2}_${1}.keytab ${2}_${1}.keytab

    echo '--------------keytab--------------'
    realpath ${2}_${1}.keytab
    echo '----------------------------------'
else
    echo "Usage: add_service.sh SERVICE SCHEMA"
    echo
    echo "Add the specified service into the Kerberos realm $REALM"
    echo
    echo "With: SERVICE  the FQN of the service (main.silverpeas.io for example)"
    echo "      SCHEMA   protocol schema in uppercase (HTTP for example)"
fi
