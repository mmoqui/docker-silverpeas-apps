Containerized applications required to bootstrap an environment for testing functionnally 
several versions of Silverpeas.

The environment is made up of several parts:
* A reverse-proxy served by the Apache HTTP server
* An LDAP service with OpenLDAP (and with phpLdapAdmin to facilitate the LDAP administration)
* Several Silverpeas instances, each of them in a different versions. By default two versions are provided:
    * silverpeas-main for the next major/minor version of Silverpeas in development
    * silverpeas-stable for the next fix version of the current stable version of Silverpeas

Each of the applications are defined by a docker-compose.yml descriptor.

