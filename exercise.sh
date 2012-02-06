#!/bin/bash

source ./openrc

SKIPPED=0
FAILED=0
PASSED=0

SKIP_MSG=""

# FIXME: make command-line option override ENV
PACKAGESET=${PACKAGESET-"diablo-final"}
BASEDIR=$(dirname $(readlink -f ${0}))

set -u

###
# set up some globals
###

black='\033[0m'
boldblack='\033[1;0m'
red='\033[31m'
boldred='\033[1;31m'
green='\033[32m'
boldgreen='\033[1;32m'
yellow='\033[33m'
boldyellow='\033[1;33m'
blue='\033[34m'
boldblue='\033[1;34m'
magenta='\033[35m'
boldmagenta='\033[1;35m'
cyan='\033[36m'
boldcyan='\033[1;36m'
white='\033[37m'
boldwhite='\033[1;37m'

TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT


COLSIZE=40

function should_run() {
    # $1 - file (nova_api)
    # $2 - test (list)

    local file=${1}
    local test=${2}
    local result=0
    local expr=""
    local condition=""
    local conditions=()
    local conditions_string=""

    [ -z "${PACKAGESET-}" ] && return 0
    [ -z "${test_config[${file}]-}" ] || conditions_string=${test_config[${file}]-}
    [ -z "${test_config[${file-}:${test-}]-}" ] || conditions_string=${test_config[${file-}:${test-}]-}
    [ -z "${conditions_string-}" ] && return 0

    # side effects rule
    SKIP_MSG=${conditions_string##*:}
    conditions_string=${conditions_string%%:*}

    local oldifs="${IFS}"
    IFS=,
    conditions=( $conditions_string )
    IFS="${oldifs}"

    for condition in "${conditions[@]}"; do
	expr="if [[ ${PACKAGESET} ${condition} ]]; then echo \"yes\"; else echo \"no\"; fi"
	if [ $(eval ${expr}) == "no" ]; then
	    result=$(( result + 1 ))
	fi
    done

    if [ ${result} -gt 0 ]; then
	return 1
    fi

    return 0
}

function colourise() {
    # $1: colour
    # $2+ message

    local colour=${1}
    shift
    local message="$@"

    if [ -t 1 ] && [ "${TERM}" != "" ]; then
	eval "printf \"\$${colour}\""
    fi

    echo ${message}

    if [ -t 1 ] && [ "${TERM}" != "" ]; then
	tput sgr0
    fi
}


declare -A test_config
source testmap.conf

set | grep ' ()' | cut -d' ' -f1 |sort > ${TMPDIR}/fn_pre.txt

echo "Running test suite for packageset \"${PACKAGESET}\""

for d in ${BASEDIR}/exercises/*.sh; do
    testname=$(basename ${d} .sh)

    source ${d}
    if $(set | grep -q 'setup ()'); then
	# not in a subshell, so globals can be modified
	setup
    fi

    # find all the functions defined in the newly sourced file.
    set | grep ' ()' | cut -d' ' -f1 | sort > ${TMPDIR}/fn_post.txt
    fnlist=$(comm -23 ${TMPDIR}/fn_post.txt ${TMPDIR}/fn_pre.txt)
    echo -e "\n=== ${testname} ===\n"

    # run each test
    for test in ${fnlist}; do
	[[ ${test} =~ "setup" ]] && continue
	[[ ${test} =~ "teardown" ]] && continue

    	printf " %-${COLSIZE}s" "${test}"
	SKIP_MSG=""

	if should_run ${testname} ${test}; then
	    resultcolour="green"  # for you, darren :p
	    start=$(date +%s.%N)

	    echo "=== TEST: ${testname}/${test} ===" > ${TMPDIR}/test.txt

	    eval "(set -e; set -x; ${test}; set +x; set +e); status=\$?" >> ${TMPDIR}/test.txt 2>&1

	    end=$(date +%s.%N)

	    elapsed=$(echo "${end}-${start}*100/100" | bc -q 2> /dev/null)
	    result="OK"
	    if [ ${status} -ne 0 ]; then
		resultcolour="red"
		result="FAIL"
		cat ${TMPDIR}/test.txt >> ${TMPDIR}/notice.txt
		echo >> ${TMPDIR}/notice.txt

		FAILED=$(( ${FAILED} + 1 ))
	    else
		result=$(printf "%0.3fs" "${elapsed}")
		PASSED=$(( ${PASSED} + 1 ))
	    fi

	    colourise ${resultcolour} " ${result}"
	else
	    colourise boldyellow -n " SKIP"
	    if [ ! -z "${SKIP_MSG-}" ]; then
		echo ": ${SKIP_MSG}"
	    else
		echo
	    fi

	    SKIPPED=$(( ${SKIPPED} + 1 ))
	fi
    done

    if $(set | grep -q 'teardown ()'); then
	teardown
    fi

    # undefine the tests
    for test in ${fnlist}; do
	unset -f ${test}
    done
done

echo
echo "RESULTS:"

echo -n "Passed:  "
colourise green ${PASSED}
echo -n "Failed:  "
colourise red ${FAILED}
echo -n "Skipped: "
colourise boldyellow ${SKIPPED}

echo
if [ "$FAILED" -ne "0" ]; then
    colourise red ERROR TEST OUTPUT
    cat ${TMPDIR}/notice.txt
    exit 1
fi

