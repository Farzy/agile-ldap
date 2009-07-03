#!/bin/bash
# vim:et:ft=sh:sts=2:sw=2:

# LDAP directory test suite
# Author: Farzad FARID <ffarid@pragmatic-source.com>
# Copyright (c) 2009 Mediatech, Pragmatic Source
# License: GPLv3
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This test suite controls the conformity of the OpenLDAP setup with
# the customer's needs.
#
# Check http://code.google.com/p/shunit2/ for more information on
# shUnit2 - xUnit based unit testing for Unix shell scripts


# Consider unset variables as errors
set -u

TEST_DIR=$(dirname $0)
export TEST_DIR

# Note that we use a pre-generated LDIF file as the LDAP DIT during
# tests, it is called "ldap-test.ldif".
# Any important DIT modification must be reproduced in this file
# during the OpenLDAP integration.
oneTimeSetUp() {
  source ${TEST_DIR}/ldap-test.conf

  # XXX We need access to the shunit temporary directory with a
  # non-root user. This is kind of hacky.
  chmod 755 ${__shunit_tmpDir}

  # Run our own copy of slapd
  LDAP_CONFDIR="${shunit_tmpDir}/etc-ldap"
  LDAP_RUNDIR="${shunit_tmpDir}/var-run-slapd"
  LDAP_DBDIR="${shunit_tmpDir}/var-lib-ldap"
  mkdir -p $LDAP_CONFDIR $LDAP_RUNDIR $LDAP_DBDIR
  cp -a /etc/ldap/* $LDAP_CONFDIR
  # Copy the local schemas and config files over the production files, just in case
  # the development versions are newer
  cp ${TEST_DIR}/../schema/*.schema ${LDAP_CONFDIR}/schema
  cp ${TEST_DIR}/../config/*.conf ${LDAP_CONFDIR}/
  sed -i -e "s#/etc/ldap#${LDAP_CONFDIR}#g" \
    -e "s#/var/run/slapd#${LDAP_RUNDIR}#g" \
    -e "s#636#${LDAP_PORT}#g" \
    -e "s#/var/lib/ldap#${LDAP_DBDIR}#g" ${LDAP_CONFDIR}/slapd.conf
  chown openldap:openldap $LDAP_RUNDIR $LDAP_DBDIR
  chmod 755 $LDAP_RUNDIR $LDAP_DBDIR
  # The test LDAP server will be started by the first test,
  # just kill an eventually forgotten test server
  fuser -k 10389/tcp
  fuser -k 10636/tcp

  # Some temporary filenames
  TMPFILE=${shunit_tmpDir}/tmpfile
}

oneTimeTearDown() {
  # Stop our slapd test server
  kill $(cat ${LDAP_RUNDIR}/slapd.pid)
  # The LDAP directories we set up previously are automatically destroyed by shunit2
}

# Clean temp files between tests
tearDown() {
  rm -f ${TMPFILE}
}

# --------------------------------
# Helper functions
# --------------------------------


ldapsearch_anon() { ${LDAPSEARCH} -LLL -x -H "${LDAP_URI}" -b "${LDAP_BASE}" "$@" ; }
ldapsearch_admin() { ${LDAPSEARCH} -LLL -x -H "${LDAP_URI}" -b "${LDAP_BASE}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PW}" "$@" ; }
ldapmodify_admin() { ${LDAPMODIFY} -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PW}" "$@" ; }

# Extract a given attribute's value from a file or stdin (must be in LDIF format)
# Argument #1: attribute name
# Argument #2: filename. Optionnal, stdin will be used if not filename is given
get_attr_value() {
  local ATTR_NAME FILENAME

  if [[ $# -lt 1 || $# -gt 2 ]]; then
    fail "Missing attribute name in call to 'getAttributeValue' in unit test"
    return
  fi
  ATTR_NAME=$1
  if [ $# -eq 2 ]; then
    FILENAME=$2
  else
    FILENAME=-
  fi

  # - The perl command joins splitted long lines back together. See
  #   http://www.openldap.org/lists/openldap-software/200504/msg00212.html
  # The 'sed' line extracts lines starting with 'attribute_name:'
  cat ${FILENAME} | perl -p -00 -e 's/\r\n //g; s/\n //g' | sed -n -e "s/^${ATTR_NAME}://p" | while read raw_value; do
    # See if the line starts with ": ", in which case the attribute's value is base64 encoded,
    # otherwise it is in plain text and will begin with ' '.
    value="${raw_value#: }"
    if [ "${value}" = "${raw_value}" ]; then
      # No encoding, but don't forget to get rid of the first space at the beginning of the line
      echo ${value# }
    else
      # Base64 encoding, must also add a newline, because openssl does not add one.
      echo ${value} | openssl base64 -d ; echo
    fi
  done
}


# ---------------------------------
# Tests
# ---------------------------------


# We really load and start the slapd server in the first test
test_Load_and_Start_slapd() {
  local RC

  sudo -u openldap ${SLAPADD} -f ${LDAP_CONFDIR}/slapd.conf -l ldap-test.ldif 
  RC=$?
  assertTrue "Loading of test LDIF file failed" "$RC" || startSkipping
  ${SLAPD} -n "ldap-test" -h "${LDAPN_URI} ${LDAPS_URI} ldapi:///" -g openldap -u openldap -f ${LDAP_CONFDIR}/slapd.conf
  RC=$?
  assertTrue "Failed to start slapd server" "$RC" || startSkipping
  sleep 0.5
  assertTrue "Failed to start slapd server" "[ -f ${LDAP_RUNDIR}/slapd.pid ]"
}

test_SSL_Connection() {
  local RC

  echo "" | openssl s_client -CApath /etc/ssl/certs -connect ${LDAPS_HOST}:${LDAPS_PORT} > ${TMPFILE} 2>/dev/null
  grep -q "Verify return code: 0 (ok)" ${TMPFILE}
  RC=$?
  assertTrue "Cannot connect to LDAP/SSL or certificate chain invalid" "$RC"
}

test_read_write_access() {
  local RC

  # cn=admin can write
  cat <<EOT > ${TMPFILE}
dn: ou=test-ou,${LDAP_BASE}
changetype: add
objectClass: organizationalUnit
objectClass: top
ou: test-ou
EOT
  ldapmodify_admin -f ${TMPFILE} > /dev/null
  RC=$?
  assertTrue "Account cn=admin cannot write to LDAP" "$RC"

  # cn=reader can only read
  ${LDAPSEARCH} -LLL -x -H "${LDAP_URI}" -b "${LDAP_BASE}" -D "${LDAP_READER_DN}" -w "${LDAP_READER_PW}" "(&(objectClass=organizationalUnit)(ou=test-ou))" ou > ${TMPFILE}
  RC=$?
  assertTrue "Account cn=reader cannot read LDAP" "$RC"
  cat <<EOT > ${TMPFILE}
dn: ou=test-ou2,${LDAP_BASE}
changetype: add
objectClass: organizationalUnit
objectClass: top
ou: test-ou2
EOT
  ${LDAPMODIFY} -x -H "${LDAP_URI}" -D "${LDAP_READER_DN}" -w "${LDAP_READER_PW}" -f ${TMPFILE} > /dev/null 2>&1
  RC=$?
  assertFalse "Account cn=reader can write to LDAP!" "$RC"
}

test_No_Anonymous_Access() {
  ldapsearch_anon >/dev/null 2>&1
  RC=$?
  assertFalse "Anonymous LDAP access should be denied" "$RC"
}

test_Find_All_Customer_Options() {
  local COUNT

  ldapsearch_admin -b "ou=Internal,${LDAP_BASE}" '(&(objectClass=mtCustomerOptionList)(cn=All Customer Options))' mtOption | \
    get_attr_value 'mtOption' | sort > ${TMPFILE}
  # Count lines
  COUNT=$(cat ${TMPFILE} | wc -l)
  assertEquals "Wrong number of customer options found" 8 "${COUNT}" || return
  # Compare to expected list
  cmp ${TMPFILE} <<EOT >/dev/null 2>&1
Classement
Encodage HQ
Filtrage Geoloc
Geo Blocking
Gestion du nombre de connexions
Reporting Géolocalisation
Webinar
WebTV
EOT
  RC=$?
  assertTrue "Global option list is incorrect" "$RC"
}

test_Find_All_and_Online_Customers() {
  local COUNT

  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(objectClass=mtOrganization)' o > ${TMPFILE}
  COUNT=$(get_attr_value 'dn' ${TMPFILE} | wc -l)
  assertEquals "Wrong number of total customers found" 5 "${COUNT}" || return

  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(mtStatus=online))' o > ${TMPFILE}
  COUNT=$(get_attr_value 'dn' ${TMPFILE} | wc -l)
  assertEquals "Wrong number of online customers found" 4 "${COUNT}"
}

test_Find_Customer() {
  local RC
  
  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=XBWA))' > ${TMPFILE}

  grep -qE '^dn: o=XBWA,ou=Customers,dc=customer,dc=com$' ${TMPFILE}
  RC=$?
  assertTrue "Cannot find XBWA customer" "$RC" || return

  grep -qE '^mtStatus: online$' ${TMPFILE}
  RC=$?
  assertTrue "Cannot find customer attribute 'mtStatus'" "$RC"
}

test_Find_Company_Options() {
  local RC COMPANY_DN OPTIONS

  # Find the customer "XBWA"
  COMPANY_DN=$(ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=XBWA))' | get_attr_value 'dn')
  # Find the customer's options
  ldapsearch_admin -b "cn=options,${COMPANY_DN}" -s base '(objectClass=mtCustomerOptionList)' mtOption | \
    get_attr_value 'mtOption' | sort > ${TMPFILE}
  # Compare to expected list
  cmp ${TMPFILE} <<EOT >/dev/null 2>&1
Classement
Webinar
WebTV
EOT
  RC=$?
  assertTrue "Customer's option list is incorrect" "$RC"
}

test_Find_Customer() {
  local COUNT VALUE RC

  ldapsearch_admin -b "ou=Internal,$LDAP_BASE" '(objectClass=mtOrganization)' > ${TMPFILE}

  COUNT=$(grep -E '^dn:' ${TMPFILE} | wc -l)
  assertEquals "There should be only one company under ou=Internal" 1 "${COUNT}" || return

  VALUE=$(cat ${TMPFILE} | get_attr_value 'o')
  assertEquals "Cannot find Customer object" "Customer" "${VALUE}" 
}

test_Modify_Company() {
  local COUNT RC

  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=XBWA)(mtStatus=online))' > ${TMPFILE}

  COUNT=$(grep -E '^dn:' ${TMPFILE} | wc -l)
  assertEquals "Cannot find XBWA customer with online status" 1 "${COUNT}" || return

  cat <<EOT > ${TMPFILE}
dn: o=XBWA,ou=Customers,dc=customer,dc=com
changetype: modify
replace: mtStatus
mtStatus: offline
EOT
  ldapmodify_admin -f ${TMPFILE} >/dev/null
  RC=$?
  assertTrue "LDAP modification failed" "$RC" || return

  ldapsearch_admin '(&(objectClass=mtOrganization)(o=XBWA)(mtStatus=offline))' > ${TMPFILE}

  COUNT=$(grep -E '^dn:' ${TMPFILE} | wc -l)
  assertEquals "Cannot find XBWA customer with offline status" 1 "${COUNT}"
}

test_Find_Multiple_Companies() {
  local RC ROOT_COMPANY_DN

  # Find the root company "Autoworld"
  ROOT_COMPANY_DN=$(ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=Autoworld))' | get_attr_value 'dn')
  RC=$?
  assertTrue "Cannot find root company's DN" "$RC" || return
  assertEquals "o=Autoworld returned a wrong company" "o=Autoworld,ou=Customers,dc=customer,dc=com" "${ROOT_COMPANY_DN}" || return

  # Now find the root company's sub-companies
  ldapsearch_admin -b "${ROOT_COMPANY_DN}" -s one '(objectClass=mtOrganization)' o | get_attr_value 'o' | sort > ${TMPFILE}
  assertEquals "Wrong number of subcompanies" 2 $(cat ${TMPFILE} | wc -l) || return
  assertEquals "Subcompany one is not the expected name" "Autoworld France" "$(head -n 1 ${TMPFILE})" || return
  assertEquals "Subcompany two is not the expected name" "Autoworld Italy" "$(tail -n 1 ${TMPFILE})" || return
}

test_Find_Regular_User_by_Uid() {
  local VALUE RC

  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(uid=wsmith))' uid > ${TMPFILE}
  RC=$?
  assertTrue "Cannot find Regular user" "$RC" || return
  VALUE=$(cat ${TMPFILE} | get_attr_value 'dn')
  assertEquals "Cannot find regular user" \
    "cn=Will Smith,o=Autoworld France,o=Autoworld,ou=Customers,${LDAP_BASE}" "${VALUE}"
}

test_Find_Regular_User_by_Uid_or_Alias() {
  local OUTPUT RC

  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=johnny)(mtAlias=johnny)))' uid > ${TMPFILE}
  RC=$?
  assertTrue "Cannot find Regular user by alias" "$RC" || return
  OUTPUT=$(cat ${TMPFILE} | get_attr_value 'dn')
  assertEquals "Search for user by alias returned wrong entry" \
    "cn=John Doe,o=Autoworld France,o=Autoworld,ou=Customers,${LDAP_BASE}" "${OUTPUT}"
}

test_Find_Customer_User() {
  local OUTPUT RC

  ldapsearch_admin -b "ou=Internal,$LDAP_BASE" '(&(objectClass=mtPerson)(uid=asimmons))' > ${TMPFILE}
  RC=$?
  assertTrue "Cannot find Customer user" "$RC" || return
  OUTPUT=$(cat ${TMPFILE} | get_attr_value 'dn')
  assertEquals "Cannot find Customer user" "cn=Anton Simmons,o=Customer,ou=Internal,${LDAP_BASE}" "${OUTPUT}"
}

test_Normal_User_Can_Only_Bind() {
  local OUTPUT RC USERDN

  # First find user by "uid" (or "mtAlias") in the "Customers" ou
  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=wsmith)(mtAlias=wsmith)))' > ${TMPFILE}
  USERDN=$(cat ${TMPFILE} | get_attr_value 'dn')

  # Should accept good password
  OUTPUT=$(${LDAPWHOAMI} -x -H ${LDAP_URI} -D "${USERDN}" -w pipo)
  RC=$?
  assertTrue "User cannot authenticate correctly" "$RC" || return
  assertEquals "ldapwhoami returned wrong user DN" "dn:${USERDN}" "${OUTPUT}" || return

  # Should reject wrong password
  OUTPUT=$(${LDAPWHOAMI} -x -H ${LDAP_URI} -D "${USERDN}" -w XXXX 2>/dev/null)
  RC=$?
  assertFalse "User should not be able to authenticate with wrong password" "$RC"
}

test_Change_User_Password_as_Admin() {
  local OUTPUT RC USERDN

  # First find user by "uid" (or "mtAlias") in the "Customers" ou
  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=wsmith)(mtAlias=wsmith)))' > ${TMPFILE}
  USERDN=$(cat ${TMPFILE} | get_attr_value 'dn')

  # Change the password
  ${LDAPPASSWD} -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PW}" -a pipo -s goodsecret "$USERDN"
  RC=$?
  assertTrue "Failed to change user password" "$RC" || return
  
  # Should accept new password
  OUTPUT=$(${LDAPWHOAMI} -x -H ${LDAP_URI} -D "${USERDN}" -w goodsecret)
  RC=$?
  assertTrue "User cannot authenticate correctly" "$RC"
}

test_Customer_User_Can_Only_Bind() {
  local OUTPUT RC USERDN

  # First find user by "uid" (or "mtAlias") in the "Internal" ou
  ldapsearch_admin -b "ou=Internal,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=anton)(mtAlias=anton)))' > ${TMPFILE}
  USERDN=$(cat ${TMPFILE} | get_attr_value 'dn')
  OUTPUT=$(${LDAPWHOAMI} -x -H ${LDAP_URI} -D "${USERDN}" -w pipo)
  RC=$?
  assertTrue "Customer user cannot authenticate correctly" "$RC" || return
  assertEquals "ldapwhoami returned wrong user DN" "dn:${USERDN}" "${OUTPUT}"
}

test_Normal_User_Cannot_Spoof_Customer_Authentication() {
  local OUTPUT RC USERDN

  # Try to find a Customer user by "uid" (or "mtAlias") in the "Customers" ou,
  # it should fail.
  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=asimmons)(mtAlias=asimmons)))' > ${TMPFILE}
  USERDN=$(cat ${TMPFILE} | get_attr_value 'dn')
  assertNull "A customer should not be able to authenticate as a privileged user" "${USERDN}"
}

test_Find_All_Admins() {
  local OUTPUT RC ORGDN

  # First find meta-company by name
  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtOrganization)(o=Autoworld))' > ${TMPFILE}
  ORGDN=$(cat ${TMPFILE} | get_attr_value 'dn')
  # Then find all admin in company and sub-companies
  # Only extract sorted "uid: ...." lines
  ldapsearch_admin -b "${ORGDN}" '(&(objectClass=mtperson)(employeeType=admin))' uid | get_attr_value 'uid' | sort > ${TMPFILE}
  cmp ${TMPFILE} <<-EOT >/dev/null 2>&1
autoworldadmin
jdoe
EOT
  RC=$?
  assertTrue "Cannot find both Autoworld admins" "$RC"
}

test_Find_All_and_Used_Servers() {
  local OUTPUT

  # All Servers
  ldapsearch_admin -b "ou=Servers,${LDAP_BASE}" '(objectClass=mtServer)' > ${TMPFILE}
  # Count servers
  OUTPUT=$(grep '^dn:' ${TMPFILE} | wc -l)
  assertEquals "Wrong number of servers found" 3 "${OUTPUT}" || return

  # Used servers
  ldapsearch_admin -b "ou=Servers,${LDAP_BASE}" '(&(objectClass=mtServer)(owner=*))' > ${TMPFILE}
  # Count servers
  OUTPUT=$(grep '^dn:' ${TMPFILE} | wc -l)
  assertEquals "Wrong number of servers found" 2 "${OUTPUT}"
}

test_Find_Customer_Server() {
  local OUTPUT COMPANY_DN

  # Find the customer "XBWA"
  COMPANY_DN=$(ldapsearch_admin '(&(objectClass=mtOrganization)(o=XBWA))' | sed -n -e 's/^dn: //p')
  # Find XBWA's server
  ldapsearch_admin -b "ou=Servers,${LDAP_BASE}" "(&(objectClass=mtServer)(owner=${COMPANY_DN}))" mtServerName > ${TMPFILE}
  OUTPUT=$(cat ${TMPFILE} | sed -n -e 's/^mtServerName: //p')
  assertEquals "Cannot find customer's server" "dedibox1" "${OUTPUT}"
}

test_Find_Unused_Servers() {
 ldapsearch_admin -b "ou=Servers,${LDAP_BASE}" "(&(objectClass=mtServer)(!(owner=*)))" mtServerName > ${TMPFILE}
  OUTPUT=$(cat ${TMPFILE} | sed -n -e 's/^mtServerName: //p')
  assertEquals "Cannot find unused server" "dedibox3" "${OUTPUT}"
}

test_Find_Customer_User_Rights() {
  local OUTPUT RC USERDN

  # First find user by "uid" (or "mtAlias") in the "Internal" ou
  ldapsearch_admin -b "ou=Internal,${LDAP_BASE}" '(&(objectClass=mtPerson)(|(uid=anton)(mtAlias=anton)))' > ${TMPFILE}
  USERDN=$(cat ${TMPFILE} | get_attr_value 'dn')

  # Find the rights list
  ldapsearch_admin -b "${USERDN}" -s one '(objectClass=mtCustomerRight)' mtRightName | get_attr_value 'mtRightName' | sort > ${TMPFILE}
  cmp ${TMPFILE} <<EOT >/dev/null 2>&1
Admin Customer
Annuaire
Bookmarks
ERP
URL simplifiées
EOT
  RC=$?
  assertTrue "Customer user's rights are incorrect" "$RC"

  # Now check a single right's value
  ldapsearch_admin -b "${USERDN}" -s one '(&(objectClass=mtCustomerRight)(mtRightName=ERP))' mtRightValue > ${TMPFILE}
  OUTPUT=$(cat ${TMPFILE} | get_attr_value 'mtRightValue')
  assertEquals "Customer user's right has an incorrect value" "admin" "${OUTPUT}" || return
  ldapsearch_admin -b "${USERDN}" -s one '(&(objectClass=mtCustomerRight)(mtRightName=URL simplifiées))' mtRightValue > ${TMPFILE}
  OUTPUT=$(cat ${TMPFILE} | get_attr_value 'mtRightValue')
  assertEquals "Customer user's right has an incorrect value" "true" "${OUTPUT}"
}

test_Add_Server_Right_to_User() {
  local RC USERDN

  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(uid=mduc))' uid > ${TMPFILE}
  USERDN=$(cat ${TMPFILE} | get_attr_value 'dn')
  assertEquals "Search for user by alias returned wrong entry" \
    "cn=Michel Duc,o=XBWA,ou=Customers,${LDAP_BASE}" "${USERDN}" || return

  # Add a server right to user
  cat <<EOT > ${TMPFILE}
dn: mtServerName=dedibox1,${USERDN}
changetype: add
objectClass: mtServerRight
objectClass: top
mtServerName: dedibox1
mtRightValue: user
EOT
  ldapmodify_admin -f ${TMPFILE} > /dev/null
  RC=$?
  assertTrue "LDAP modification failed" "$RC"
}

test_Cannot_Add_Server_Right_to_User_Twice() {
  local RC USERDN

  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(uid=mduc))' uid > ${TMPFILE}
  USERDN=$(cat ${TMPFILE} | get_attr_value 'dn')
  assertEquals "Search for user by alias returned wrong entry" \
    "cn=Michel Duc,o=XBWA,ou=Customers,${LDAP_BASE}" "${USERDN}" || return

  # Add a server right to user
  cat <<EOT > ${TMPFILE}
dn: mtServerName=dedibox1,${USERDN}
changetype: add
objectClass: mtServerRight
objectClass: top
mtServerName: dedibox1
mtRightValue: user
EOT
  ldapmodify_admin -f ${TMPFILE} > /dev/null
  RC=$?
  assertFalse "LDAP modification should have failed" "$RC"
}

test_Find_Server_Right() {
  local VALUE RC USERDN

  # First find user jdupond
  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(uid=jdupond))' uid > ${TMPFILE}
  USERDN=$(cat ${TMPFILE} | get_attr_value 'dn')
  assertEquals "Search for user returned wrong entry" \
    "cn=Jean Dupond,o=XBWA,ou=Customers,${LDAP_BASE}" "${USERDN}" || return

  # Now find the user's right on a specific server
  ldapsearch_admin -b "${USERDN}" -s one '(&(objectClass=mtServerRight)(mtServerName=dedibox1))' mtRightValue > ${TMPFILE}
  VALUE=$(cat ${TMPFILE} | get_attr_value 'mtRightValue')
  assertEquals "Incorrect Server right" "admin" "${VALUE}"

  # First find user mduc
  ldapsearch_admin -b "ou=Customers,${LDAP_BASE}" '(&(objectClass=mtPerson)(uid=mduc))' uid > ${TMPFILE}
  USERDN=$(cat ${TMPFILE} | get_attr_value 'dn')
  assertEquals "Search for user returned wrong entry" \
    "cn=Michel Duc,o=XBWA,ou=Customers,${LDAP_BASE}" "${USERDN}" || return

  # Now find the user's right on a specific server
  ldapsearch_admin -b "${USERDN}" -s one '(&(objectClass=mtServerRight)(mtServerName=dedibox1))' mtRightValue > ${TMPFILE}
  VALUE=$(cat ${TMPFILE} | get_attr_value 'mtRightValue')
  assertEquals "Incorrect Server right" "user" "${VALUE}"
}

test_unique_ids() {
  local RC

  # Unique UID for customers
  cat <<EOT > ${TMPFILE}
dn: o=NotUnique,ou=Customers,dc=customer,dc=com
changetype: add
objectClass: mtOrganization
objectClass: organization
objectClass: top
mtStatus: online
o: NotUnique
uid: 35343
EOT
  ldapmodify_admin -f ${TMPFILE} > /dev/null
  RC=$?
  assertFalse "Unique organization's uid violation" "$RC"

  # Unique UID for people
  cat <<EOT > ${TMPFILE}
dn: cn=Michel Duc 2,o=XBWA,ou=Customers,dc=customer,dc=com
changetype: add
objectClass: inetOrgPerson
objectClass: mtPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
cn: Michel Duc 2
sn: Dupond
uid: mduc
EOT
  ldapmodify_admin -f ${TMPFILE} > /dev/null
  RC=$?
  assertFalse "Unique person's uid violation" "$RC"

  # Unique mtAlias for people
  cat <<EOT > ${TMPFILE}
dn: cn=Michel Duc 2,o=XBWA,ou=Customers,dc=customer,dc=com
changetype: add
objectClass: inetOrgPerson
objectClass: mtPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
cn: Michel Duc 2
sn: Dupond
uid: mduc2
mtAlias: michel
EOT
  ldapmodify_admin -f ${TMPFILE} > /dev/null
  RC=$?
  assertFalse "Unique person's alias violation" "$RC"

  # Unique mail for people
  cat <<EOT > ${TMPFILE}
dn: cn=Michel Duc 2,o=XBWA,ou=Customers,dc=customer,dc=com
changetype: add
objectClass: inetOrgPerson
objectClass: mtPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
cn: Michel Duc 2
sn: Dupond
uid: mduc2
mail: mduc@tbwa.fr
EOT
  ldapmodify_admin -f ${TMPFILE} > /dev/null
  RC=$?
  assertFalse "Unique person's mail violation" "$RC"

}

test_valid_mail() {
  local RC

  # Valid mail for people
  cat <<EOT > ${TMPFILE}
dn: cn=Michel Duc 2,o=XBWA,ou=Customers,dc=customer,dc=com
changetype: add
objectClass: inetOrgPerson
objectClass: mtPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
cn: Michel Duc 2
sn: Dupond
uid: mduc2
mail: xx@tt
EOT
  ldapmodify_admin -f ${TMPFILE} > /dev/null
  RC=$?
  assertFalse "Email syntax violation" "$RC"
}


# Now launch the test suite
. ${TEST_DIR}/shunit2
