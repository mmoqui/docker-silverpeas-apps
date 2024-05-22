#!/bin/bash

LDAP_ADMIN_DN="cn=${LDAP_ADMIN_USERNAME},${LDAP_BASE_DN}"
LDAP_KADMIN_FQN="kadmin/admin@$KRB_REALM"

function init_ldap_backend() {
    echo "Create Kerberos realm $KRB_REALM in LDAP"
    kdb5_ldap_util -D $LDAP_ADMIN_DN -w $LDAP_ADMIN_PASSWORD \
        create -subtrees $LDAP_BASE_DN -r $KRB_REALM -s -H $LDAP_URL -P ${KRB_MASTER_KEY}
    
    echo "Create the stash of the password used to bind the LDAP server for the Kerberos admin"
    kdb5_ldap_util -D ${LDAP_ADMIN_DN} -w ${LDAP_ADMIN_PASSWORD} -H ${LDAP_SERVER} -r ${REALM} \
        stashsrvpw -f /etc/krb5kdc/service.keyfile ${LDAP_ADMIN_DN} <<EOF
$KRB_ADMIN_PASSWORD
$KRB_ADMIN_PASSWORD
EOF
}

function create_kdc_admin_user() {
    echo "Set the Kerberos admin ACL and change its password"
    echo "$LDAP_KADMIN_FQN *" > /etc/krb5kdc/kadm5.acl

    kadmin.local -q "change_password -pw $KRB_ADMIN_PASSWORD $LDAP_KADMIN_FQN"
}

function start_kdc() {
    krb5kdc -P /var/run/krb5kdc.pid
    kadmind -nofork -P /var/run/kadmind.pid
}

function create_realm_config() {
    echo "Configure the Kerberos realm $KRB_REALM"
    KDC_SERVER=$(hostname -f)

    test "Z$KRB_DOMAIN"="Z" && KRB_DOMAIN="${KRB_REALM,,}"

    tee /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $KRB_REALM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    $KRB_REALM = {
        kdc = $KDC_SERVER
        admin_server = $KDC_SERVER
        default_domain = $KRB_DOMAIN
        database_module = openldap_ldapconf
    }

[domain_realm]
    .$KRB_DOMAIN = $KRB_REALM
    $KRB_DOMAIN = $KRB_REALM

[dbdefaults]
    ldap_kerberos_container_dn = cn=krbContainer,$LDAP_BASE_DN

[dbmodules]
    openldap_ldapconf = {
        db_library = kldap

        # if either of these is false, then the ldap_kdc_dn needs to
        # have write access
        disable_last_success = true
        disable_lockout  = true

        # this object needs to have read rights on
        # the realm container, principal container and realm sub-trees
        ldap_kdc_dn = "$LDAP_ADMIN_DN"

        # this object needs to have read rights on
        # the realm container, principal container and realm sub-trees
        ldap_kadmind_dn = "$LDAP_ADMIN_DN"

        ldap_service_password_file = /etc/krb5kdc/service.keyfile
        ldap_servers = $LDAP_URL
        ldap_conns_per_server = 5
    }
EOF

    tee /etc/krb5kdc/kdc.conf <<EOF
[kdcdefaults]
    kdc_ports = 750,88

[realms]
    $KRB_REALM = {
        max_life = 12h 0m 0s
        acl_file = /etc/krb5kdc/kadm5.acl
        max_renewable_life = 7d 0h 0m 0s
        master_key_type = aes256-cts
        default_principal_flags = +preauth
    }
EOF
}

function register_users() {
    echo "Register LDAP users in Kerberos..."

    service krb5-kdc start
    service krb5-admin-server start

    for file in /etc/krb5/custom/*; do
        for user in $(cat $file); do
            items=($(echo $user | tr '#' '\n'))
            echo "--> register user ${items[0]} in realm ${KRB_REALM}"
            kadmin.local -q "addprinc -pw ${items[2]} -x dn=${items[1]} ${items[0]}@${KRB_REALM}"
        done
    done

    service krb5-kdc stop
    service krb5-admin-server stop
}

if [ ! -f /kerberos_initialized ]; then
    create_realm_config
    init_ldap_backend
    create_kdc_admin_user
    register_users

    touch /kerberos_initialized
fi

start_kdc

