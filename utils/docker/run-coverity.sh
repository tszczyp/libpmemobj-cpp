#!/usr/bin/env bash
#
# Copyright 2018-2020, Intel Corporation
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in
#       the documentation and/or other materials provided with the
#       distribution.
#
#     * Neither the name of the copyright holder nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#
# run-coverity.sh - runs the Coverity scan build
#

set -e

if [[ "$CI_REPO_SLUG" != "$GITHUB_REPO" \
   && ( "$COVERITY_SCAN_NOTIFICATION_EMAIL" == "" \
     || "$COVERITY_SCAN_TOKEN" == "" ) ]]; then
	echo
	echo "Skipping Coverity build:"\
		"COVERITY_SCAN_TOKEN=\"$COVERITY_SCAN_TOKEN\" or"\
		"COVERITY_SCAN_NOTIFICATION_EMAIL="\
		"\"$COVERITY_SCAN_NOTIFICATION_EMAIL\" is not set"
	exit 0
fi

# Prepare build environment
source `dirname $0`/prepare-for-build.sh

CERT_FILE=/etc/ssl/certs/ca-certificates.crt
TEMP_CF=$(mktemp)
cp $CERT_FILE $TEMP_CF

# Download Coverity certificate
echo -n | openssl s_client -connect scan.coverity.com:443 | \
	sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' | \
	tee -a $TEMP_CF

sudo_password mv $TEMP_CF $CERT_FILE

cd $WORKDIR
mkdir build
cd build
PKG_CONFIG_PATH=/opt/pmdk/lib/pkgconfig/ cmake .. -DCMAKE_BUILD_TYPE=Debug

export COVERITY_SCAN_PROJECT_NAME="$CI_REPO_SLUG"
[[ "$CI_EVENT_TYPE" == "cron" ]] \
	&& export COVERITY_SCAN_BRANCH_PATTERN="master" \
	|| export COVERITY_SCAN_BRANCH_PATTERN="coverity_scan"
export COVERITY_SCAN_BUILD_COMMAND="make -j$(nproc)"

#
# Run the Coverity scan
#

# The 'travisci_build_coverity_scan.sh' script requires the following
# environment variables to be set:
# - TRAVIS_BRANCH - has to contain the name of the current branch
# - TRAVIS_PULL_REQUEST - has to be set to 'true' in case of pull requests
#
export TRAVIS_BRANCH=${CI_BRANCH}
[ "${CI_EVENT_TYPE}" == "pull_request" ] && export TRAVIS_PULL_REQUEST="true"

# XXX: Patch the Coverity script.
# Recently, this script regularly exits with an error, even though
# the build is successfully submitted.  Probably because the status code
# is missing in response, or it's not 201.
# Changes:
# 1) change the expected status code to 200 and
# 2) print the full response string.
#
# This change should be reverted when the Coverity script is fixed.
#
# The previous version was:
# curl -s https://scan.coverity.com/scripts/travisci_build_coverity_scan.sh | bash

wget https://scan.coverity.com/scripts/travisci_build_coverity_scan.sh
patch < ../utils/docker/0001-travis-fix-travisci_build_coverity_scan.sh.patch
bash ./travisci_build_coverity_scan.sh
