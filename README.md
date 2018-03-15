# luzifer-docker / openldap

The image is using alpine linux as its base image. The Dockerfile is based on the work on [dinkel/docker-openldap](https://github.com/dinkel/docker-openldap) and [danielguerra69/docker-openldap](https://github.com/danielguerra69/docker-openldap)

NOTE: On purpose, there is no secured channel (TLS/SSL), because I believe that this service should never be exposed to the internet, but only be used directly by other Docker containers using the `--link` option.

## Usage

The most simple form would be to start the application like so (however this is not the recommended way - see below):

    docker run -d -p 389:389 -e SLAPD_PASSWORD=mysecretpassword -e SLAPD_DOMAIN=ldap.example.org luzifer/openldap

To get the full potential this image offers, one should first create a data-only container (see "Data persistence" below), start the OpenLDAP daemon as follows:

    docker run -d --name openldap --volumes-from your-data-container luzifer/openldap

An application talking to OpenLDAP should then `--link` the container:

    docker run -d --link openldap:openldap [image-using-openldap]

The name after the colon in the `--link` section is the hostname where the OpenLDAP daemon is listening to (the port is the default port `389`).

## Configuration (environment variables)

For the first run, one has to set at least the first two environment variables. After the first start of the image (and the initial configuration), these envirnonment variables are not evaluated again.

* `SLAPD_PASSWORD` (required) - sets the password for the `admin` user.
* `SLAPD_DOMAIN` (required) - sets the DC (Domain component) parts. E.g. if one sets it to `ldap.example.org`, the generated base DC parts would be `...,dc=ldap,dc=example,dc=org`.
* `SLAPD_ADMIN_USER` - sets the RootDN admin username (defaults to `admin`)
* `SLAPD_ORGANIZATION` (defaults to `Example Inc.`) - represents the human readable company name (e.g. `Example Inc.`).
* `SLAPD_ADDITIONAL_SCHEMAS` - loads additional schemas provided in the `slapd` package that are not installed using the environment variable with comma-separated enties. As of writing these instructions, there are the following additional schemas available: `collective`, `corba`, `cosine`, `duaconf`, `dyngroup`, `inetorgperson`, `java`, `misc`, `nis`, `openldap`, `pmi` and `ppolicy`.
* `SLAPD_ADDITIONAL_MODULES` - comma-separated list of modules to load. It will try to run `.ldif` files with a corresponsing name from the `module` directory. Currently only `memberof` and `ppolicy` are avaliable.
* `SLAPD_CONFIG_PASSWORD` - If set the root password for `cn=config` is set (Connect using username and base-dn `cn=config`)


### Setting up ppolicy

The ppolicy module provides enhanced password management capabilities that are applied to non-rootdn bind attempts in OpenLDAP. In order to it, one has to load both the schema `ppolicy` and the module `ppolicy`:

```
-e SLAPD_DOMAIN=ldap.example.org -e SLAPD_ADDITIONAL_SCHEMAS=ppolicy -e SLAPD_ADDITIONAL_MODULES=ppolicy`
```

There is one additional environment variable available:

* `SLAPD_PPOLICY_DN_PREFIX` - (defaults to `cn=default,ou=policies`) sets the dn prefix used in `modules/ppolicy.ldif` for the `olcPPolicyDefault` attribute. The value used for `olcPPolicyDefault` is derived from `$SLAPD_PPOLICY_DN_PREFIX,(dc component parts from $SLAPD_DOMAIN)`.

After loading the module, you have to load a default password policy, assuming you are on a host that has the client side tools installed (maybe you have to change the hostname as well):

```
ldapadd -h localhost -x -c -D 'cn=admin,dc=ldap,dc=example,dc=org' -w [$SLAPD_PASSWORD] -f default-policy.ldif
```

The contents of `default-policy.ldif` should look something like this:

```ldif
# Define password policy
dn: ou=policies,dc=ldap,dc=example,dc=org
objectClass: organizationalUnit
ou: policies

dn: cn=default,ou=policies,dc=ldap,dc=example,dc=org
objectClass: applicationProcess
objectClass: pwdPolicy
cn: default
pwdAllowUserChange: TRUE
pwdAttribute: userPassword
pwdCheckQuality: 1
# 7 days
pwdExpireWarning: 604800
pwdFailureCountInterval: 0
pwdGraceAuthNLimit: 0
pwdInHistory: 5
pwdLockout: TRUE
# 30 minutes
pwdLockoutDuration: 1800
# 180 days
pwdMaxAge: 15552000
pwdMaxFailure: 5
pwdMinAge: 0
pwdMinLength: 6
pwdMustChange: TRUE
pwdSafeModify: FALSE
```

See the [docs](http://www.zytrax.com/books/ldap/ch6/ppolicy.html) for descriptions on the available attributes and what they mean.

## Data persistence

The image exposes two directories (`VOLUME ["/etc/openldap/slapd.d", "/var/lib/openldap/openldap-data"]`). The first holds the "static" configuration while the second holds the actual database. Please make sure that these two directories are saved (in a data-only container or alike) in order to make sure that everything is restored after a restart of the container.
