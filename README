Agile LDAP - Test Driven Administration example
===============================================


About this projet
-----------------

This project is a Test Driven Integration and Administration of an OpenLDAP directory, including the
creation of a custom schema, the configuration of the OpenLDAP server and corresponding unit tests.

Goal & Philosophy
-----------------

The primary goal of this project was to create a high availability OpenLDAP server with a custom
schema.

The secondary goal was to show that it is possible to apply agile techniques and principles to an
integration (i.e. non-developement) projet.

Documentation
-------------

The project integration was driven with a test suite called *shunit2*. Shunit2 provides unit tests
for shell scripts, it works with Bash and Zsh and maybe some other shells too.

**TODO**: There is not much documentation for the moment, have a look at `Makefile` and 
`tests/ldap-test.sh` which contain the core of the test framework.

### Project layout

-  Makefile: Helps launch all action (tests, deployment, etc.)
-  config/: OpenLDAP and Monit configuration. The `slapd.conf` configuration file is
   dynamically created by the Makefile.
-  schema/: The project's custom schema.
-  tests/: Unit tests and sample LDAP data.

### Configuration

#### Test & production

-  Create a TLS/SSL certfiticate for the OpenLDAP server. **WARNING**: The certificate's CN must correspond
   exactly to the LDAP server's DNS name.
-  The key pair must be named "customer-ldap.crt" and "customer-ldap.key" and put in `/etc/ldap`. Check `config/slapd.conf.template`
   if you need to change this name.
-  **TODO**

#### Production only

-  Install config/openldap-backup.cron as a cron script. It handles automatic LDAP database backup and
   keep a number of copies (40 by default).
-  Install Monit and copy the `config/monit` and `config/monitrc` to the right place.


Author & copyright
------------------

Author: Farzad FARID <ffarid@pragmatic-source.com>, <http://www.pragmatic-source.com>

Copyright (c) 2009 Pragmatic Source & Mediatech

A big thank you to Antony Simonneau from Mediatech (http://www.mediatech.fr)
who let me publish this project under an open source license.

License
-------

GPLv3

Links
-----

-  shunit2, a Test::Unit for shell (Bash & Zsh): http://code.google.com/p/shunit2/
-  Monit, a monitoring tool: http://mmonit.com/monit/

