#!/usr/bin/env bash
#
# Need a single RUN command in docker in order to start p4d and interact with it
# during the build process (i.e. docker build does not leave processes running
# between each of the steps).
#
set -e

# would be nice to get the P4PORT passed to this script
export P4PORT=0.0.0.0:1666
export P4USER=super
P4PASSWD=Rebar123

# start the server so we can populate it with data
p4dctl start -o '-p 0.0.0.0:1666' despot
echo ${P4PASSWD} | p4 login

# disable the signed extensions requirement for testing
# p4 configure set server.extensions.allow.unsigned=1

# create a group with long lived tickets, log in again
p4 group -i <<EOT
Group:	no_timeout
Timeout:	unlimited
Users:
	super
EOT
p4 logout
echo ${P4PASSWD} | p4 login

# run the configure script and set up OIDC
echo 'configuring extension for OIDC...'
./helix-auth-ext/bin/configure-login-hook.sh -n \
    --p4port localhost:1666 \
    --super super \
    --superpassword Rebar123 \
    --service-url https://has.example.com \
    --default-protocol oidc \
    --enable-logging \
    --non-sso-users super \
    --name-identifier email \
    --user-identifier email \
    --yes

echo 'waiting for p4d to restart...'
sleep 5

p4 -ztag extension --configure Auth::loginhook -o | tr '\n' ' ' > output
grep -Eq 'Auth-Protocol:.+oidc' output
grep -Eq 'Service-URL:.+https://has.example.com' output

p4 extension --configure Auth::loginhook --name loginhook-a1 -o | tr '\n' ' ' > output
grep -Eq 'enable-logging:.+true' output
grep -Eq 'name-identifier:.+email' output
grep -Eq 'non-sso-users:.+super' output
grep -Eq 'user-identifier:.+email' output

# run the configure script and set up SAML
echo 'configuring extension for SAML...'
./helix-auth-ext/bin/configure-login-hook.sh -n \
    --p4port localhost:1666 \
    --super super \
    --superpassword Rebar123 \
    --service-url https://localhost:3000 \
    --default-protocol saml \
    --non-sso-users duper \
    --name-identifier nameID \
    --user-identifier fullname \
    --yes

echo 'waiting for p4d to restart...'
sleep 5

p4 -ztag extension --configure Auth::loginhook -o | tr '\n' ' ' > output
grep -Eq 'Auth-Protocol:.+saml' output
grep -Eq 'Service-URL:.+https://localhost:3000' output

p4 extension --configure Auth::loginhook --name loginhook-a1 -o | tr '\n' ' ' > output
grep -Eq 'enable-logging:.+... off' output
grep -Eq 'name-identifier:.+nameID' output
grep -Eq 'non-sso-users:.+duper' output
grep -Eq 'user-identifier:.+fullname' output

# stop the server so that the run script can start it again,
# and the authentication changes will take effect
p4dctl stop despot