# docker-silverpeas-apps

Containerized applications required to bootstrap a simulation of a production environment for testing functionally several versions of Silverpeas.

Each application is a multi-container application described by a `docker-compose.yml` descriptor.
All of them are deployed onto the same user-defined Docker network, `silverpeas-net`, and share the
same domain name, `silverpeas.io`, so that they can address each other by name.

## Overview

The environment is made up of several parts:

* **silverpeas-apache**: a reverse-proxy served by the Apache HTTP server. It is the single HTTP(S)
  entry point of the environment and dispatches the incoming requests to the right Silverpeas
  instance according to the virtual host that is targeted.
* **silverpeas-ldap**: a directory service with OpenLDAP, a Kerberos KDC using that directory as
  backend, and phpLDAPadmin to facilitate the LDAP administration. It is shared by all the
  Silverpeas instances.
* **silverpeas-main** and **silverpeas-stable**: two instances of Silverpeas, each of them in a
  different version and each of them coupled with its own PostgreSQL database:
    * `silverpeas-main` for the next major/minor version of Silverpeas in development,
    * `silverpeas-stable` for the next fix version of the current stable version of Silverpeas.

The exploded web archive of each Silverpeas instance is mounted on the `webapp` directory in the instance folder of the host (_silverpeas-main_, _silverpeas-stable_),

Any number of additional Silverpeas applications can be added by following the same layout (see
[Adding a new Silverpeas application](#adding-a-new-silverpeas-application)).

### Network layout

All the applications run in the `silverpeas-net` bridge network, on the subnet `172.18.0.0/24` with
`172.18.0.1` as gateway. Each container gets a fixed IP address so that the reverse-proxy and the
Silverpeas instances can always find each other:

| Application       | Service        | Container           | IP            | Ports published on the host |
|-------------------|----------------|---------------------|---------------|-----------------------------|
| silverpeas-apache | reverse-proxy  | `silverpeas-apache` | `172.18.0.80` | 80, 443                     |
| silverpeas-ldap   | ldap           | `ldap`              | `172.18.0.20` | 389, 636                    |
| silverpeas-ldap   | ldapadmin      | `ldapadmin`         | `172.18.0.21` | 8888 (→ 80)                 |
| silverpeas-ldap   | kerberos       | `kdc`               | `172.18.0.22` | 88, 464, 749                |
| silverpeas-main   | silverpeas-main| `silverpeas-main`   | `172.18.0.4`  | 8080 (→ 8000), 5005         |
| silverpeas-main   | postgresql-main| `postgresql-main`   | `172.18.0.5`  | –                           |
| silverpeas-stable | silverpeas-stable | `silverpeas-stable` | `172.18.0.14` | 8180 (→ 8000), 5105     |
| silverpeas-stable | postgresql-stable | `postgresql-stable` | `172.18.0.15` | –                       |

The network is declared as `external` in every `docker-compose.yml`: it has to exist before starting
any application. The `silverpeas` script creates it for you if required, otherwise create it by
hand:

```
$ docker network create --driver=bridge --ipam-driver=default \
    --subnet=172.18.0.0/24 --gateway=172.18.0.1 silverpeas-net
```

### URLs

The Silverpeas instances are meant to be reached through the reverse-proxy in HTTPS:

| Instance          | URL                                  |
|-------------------|--------------------------------------|
| silverpeas-main   | https://main.silverpeas.io/silverpeas   |
| silverpeas-stable | https://stable.silverpeas.io/silverpeas |
| phpLDAPadmin      | http://localhost:8888                |

Each Silverpeas instance can also be reached directly, bypassing the proxy, at
http://localhost:8080/silverpeas (main) and http://localhost:8180/silverpeas (stable). Some features
requiring HTTPS won't work then.

## Prerequisites

1. **Docker** and the **Docker Compose plugin** (`docker compose`) installed on the host.
2. The Docker images used by the applications and that aren't fetched from the Docker Hub have to be
   built beforehand:
    * `silverapache`, built from the
      [docker-silverpeas-apache](https://github.com/mmoqui/docker-silverpeas-apache) project,
    * `silverpeas-run:latest` and `silverpeas-run:stable` (or any tag referred by the descriptors),
      built from the [silverpeas-run](https://github.com/mmoqui/silverpeas-run) project with its `build.sh` script. One
      image per version of Silverpeas to test has to be built and then tagged accordingly.
    * `kerberos:1.20.1` is built automatically by Docker Compose from the `silverpeas-ldap/krb5`
      directory at the first start of the `silverpeas-ldap` application.
3. The name resolution of the virtual hosts on the host: add the following entries to your
   `/etc/hosts` file so that your web browser can reach the reverse-proxy and the Kerberos service:
   ```
   172.18.0.80  gateway.silverpeas.io main.silverpeas.io stable.silverpeas.io
   172.18.0.22  kerberos.silverpeas.io
   ```
   (In the containers, the resolution is already taken in charge by the `extra_hosts` directive of
   the Silverpeas services and by the Docker network itself.)
4. The fake root CA certificate used to sign the certificates of the virtual hosts (available in the
   `src/ssl/CA` directory of the _docker-silverpeas-apache_ project) has to be imported among the
   root CA certificates of your web browser. Otherwise the browser will refuse the certificates
   served by the reverse-proxy.
5. Because the local Maven repository of the host is mounted into the Silverpeas containers, your
   user and group identifiers on the host must match those of the `silveruser` user in the
   `silverpeas-run` image (see the `-u` and `-g` options of its `build.sh` script).

### Paths to adapt

Some absolute paths of the host are hard-coded in this project and have to be adapted to your own
environment:

* `DOCKER_CPNT_HOME` in the `silverpeas` script: the absolute path of this project,

## Usage with the `silverpeas` script

The `silverpeas` script is a convenient way to bootstrap, start, and stop a whole environment for a
given version of Silverpeas. It takes care of:

* creating the `silverpeas-net` network if it doesn't exist yet,
* starting the reverse-proxy and the LDAP/Kerberos services if they aren't already running,
* starting (or bootstrapping at the very first run) the requested Silverpeas application,
* opening a shell as the `silveruser` user in the container of Silverpeas.

```
$ ./silverpeas CMD VERSION
```

with:

* `CMD`: either `start` or `stop`,
* `VERSION`: the version of Silverpeas to which the command applies; the name of the application is
  figured out from it by applying the format `silverpeas-VERSION`.

For example, to start the environment with the Silverpeas instance in development:

```
$ ./silverpeas start main
```

and to stop it:

```
$ ./silverpeas stop main
```

When stopping, the reverse-proxy and the LDAP/Kerberos services are stopped only if no other
Silverpeas container is still running (the script looks for the containers exposing the port
8000/tcp). This way, several versions of Silverpeas can be run side by side and shut down one after
the other.

Once the shell is opened in the Silverpeas container, you are logged as `silveruser` in the
`bin` directory of `SILVERPEAS_HOME` from which Silverpeas can be installed, configured, and
started as documented in the _silverpeas-run_ project. Detaching from the shell doesn't stop the
container.

For the script to be available from anywhere, copy it (or link it) into a directory of your `PATH`
and update its `DOCKER_CPNT_HOME` variable accordingly.

## Usage with Docker Compose

Each application can also be driven directly with `docker compose`, from within its own directory:

```
$ cd silverpeas-ldap
$ docker compose up -d       # bootstrap and start the application in the background
$ docker compose stop        # stop the containers, keeping them and their data
$ docker compose start       # restart previously stopped containers
$ docker compose down        # stop and delete the containers (the volumes are kept)
$ docker compose logs -f     # follow the logs of the services
```

Beware of the starting order: the `silverpeas-net` network must exist first, and the Silverpeas
applications expect the reverse-proxy and the LDAP service to be up in order to be reachable by
their virtual host name and to authenticate the users of the LDAP domain.

The Silverpeas services are declared with `stdin_open` and `tty` and run `/bin/bash` as command:
they are meant to be driven interactively. To get a shell in a running one:

```
$ docker exec -u silveruser -it silverpeas-main /bin/bash
```

## The applications

### silverpeas-apache

A single service, `reverse-proxy`, spawned from the `silverapache` image with
`gateway.silverpeas.io` as host name. It listens on the ports 80 and 443 of the host: any HTTP
request is redirected to HTTPS, and each HTTPS virtual host (`main.silverpeas.io`,
`stable.silverpeas.io`) proxies the requests (including the WebSocket ones) to the corresponding
Silverpeas container on its port 8000.

The Apache logs are mounted on the `log` directory of the host so that they can be consulted without
entering the container.

Adding a new Silverpeas instance to the environment requires adding a new virtual host into the
Apache configuration of the [docker-silverpeas-apache](https://github.com/mmoqui/docker-silverpeas-apache) project and
rebuilding the `silverapache` image.

### silverpeas-ldap

Three services:

* **ldap**: an OpenLDAP directory (image `osixia/openldap:1.5.0`) for the organization _Silverpeas_
  with `dc=silverpeas,dc=io` as base DN and `admin` as password of the `cn=admin,dc=silverpeas,dc=io`
  administrator. TLS is enabled with the certificates provided in the `certs` directory. The LDIF
  files of the `ldif` directory are loaded at the first start of the container:
    * `icepeas.ldif` declares the organizational unit `ou=icepeas,dc=silverpeas,dc=io` with five
      users (`jsmith1` to `jsmith5`, password `sasa`),
    * `kerberos.openldap.ldif` adds the Kerberos schema required by the KDC.
  The users of this organizational unit are the ones expected by the `IcePeas` user domain that is
  predefined in the `silverpeas-run` image.
* **ldapadmin**: phpLDAPadmin (image `osixia/phpldapadmin`), published on the port 8888 of the host,
  to browse and edit the content of the directory.
* **kerberos**: a KDC (built from the `krb5` directory) for the realm `SILVERPEAS.IO`, using the
  LDAP directory as backend. At its first start it creates the realm within the directory, creates
  the Kerberos administrator, and registers the users listed in the `krbusers/SILVERPEAS.IO` file.
  Each line of such a file describes one principal in the format:
  ```
  PRINCIPAL#LDAP_DN#PASSWORD
  ```

Because the LDAP directory is loaded once and for all at the creation of its container, any change
in the LDIF files requires the container and its data to be recreated (`docker compose down` then
`docker compose up`).

#### Registering a service in the Kerberos realm

To enable SSO (SPNEGO) for a Silverpeas instance, the HTTP service of its virtual host has to be
declared as a principal in the realm and its keytab generated. This is what the `add_service.sh`
script does:

```
$ ./add_service.sh SERVICE SCHEMA
```

with `SERVICE` the FQN of the service and `SCHEMA` the protocol schema in uppercase. For example,
for the Silverpeas instance in development:

```
$ ./add_service.sh main.silverpeas.io HTTP
```

The generated keytab (`HTTP_main.silverpeas.io.keytab`) is copied into the current directory; its
path is printed at the end of the script so that it can be provided to the SSO configuration of
Silverpeas.

### silverpeas-main and silverpeas-stable

Both applications are built on the same model, with two services:

* **silverpeas-_xxx_**: an instance of Silverpeas spawned from a `silverpeas-run` image
  (`silverpeas-run:latest` for _main_, `silverpeas-run:stable` for _stable_). The container is
  linked to its database container under the alias `database`, and the FQN of its virtual host is
  resolved to the IP address of the reverse-proxy. It publishes the HTTP port of Silverpeas (8000)
  and the JVM debugging port (5005) on the host.
* **postgresql-_xxx_**: the PostgreSQL 14 database of that instance, initialized at the creation of
  the container with the `silverpeas.sql` dump. This dump creates the `silverpeas` database and its
  `silverpeas` user (password `silverpeas`), and restores a ready-to-use dataset matching the
  initial contributions that are provided in the `silverpeas-run` image. The `init.sql` file is a
  minimalist alternative that just creates an empty database and its user.

Each application declares two named volumes so that the state survives the recreation of the
containers:

* `silverpeas-data-xxx`: the data of Silverpeas (`/home/silveruser/silverpeas/data`),
* `postgresql-data-xxx`: the data of the PostgreSQL RDBMS.

Two directories of the host are also mounted into the Silverpeas container:

* the directory in which the web archive of Silverpeas is exploded
  (`/home/silveruser/webapp`), so that web resources like JSPs or JavaScript files can be updated by hand from the host;
* the local Maven repository (`/home/silveruser/.m2/repository`), so that the artifacts built on the
  host can be fetched by the Silverpeas installer running in the container. This is the way
  Silverpeas is updated in the container with the code being developed.

To restart from a fresh state (empty data and freshly restored database), delete the containers and
their volumes:

```
$ docker compose down -v
```

## Adding a new Silverpeas application

1. Build (and tag) a `silverpeas-run` image for the version of Silverpeas to test.
2. Add a virtual host for it in the [docker-silverpeas-apache](https://github.com/mmoqui/docker-silverpeas-apache) project
   and rebuild the `silverapache` image. As an alternative way, you can edit by hand the file `/etc/apache/sites-available/silverpeas.conf` in the running `silverpeas-apache` container.
3. Create a `silverpeas-VERSION` directory in this project, by copying for example the content of
   `silverpeas-main`, and update in its `docker-compose.yml`:
    * the name of the services, of the containers, and of the volumes,
    * the tag of the `silverpeas-run` image,
    * the IP addresses in the `silverpeas-net` network (they must be free in `172.18.0.0/24`),
    * the ports published on the host (they must be free on the host),
    * the FQN of the virtual host in the `extra_hosts` directive,
    * the directories of the host that are mounted into the container.
4. Optionally, register the HTTP service of the new virtual host in the Kerberos realm with the
   `add_service.sh` script of the `silverpeas-ldap` application.

The application can then be driven with `./silverpeas start VERSION`.
