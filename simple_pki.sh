#!/bin/sh

set -e
THISREF="$0"
THISDIR="$(dirname $0)"

NSS_DBDIR="${NSS_DBDIR:-${THISDIR}}"
CAID="${CAID:-CA}"

_hostid() { 
  echo "$1"
}
_subject() {
  # Override this to set subject from ID
  test -z "$1" && fail 4 "_subject: Missing id"
  subject="CN=$1"
  echo $subject
}
_extra() {
  # Override this to set extra request args from ID
  test -z "$1" && fail 5 "_extra: Missing id"
  extra=""
  echo $extra
}
sign() {
  # Override this to sign remotely
  sign_locally "$@"
  #track ssh root@fw1 /etc/pki/slog.home/pki.sh sign
}

_KEY_USAGE="digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment"
_NS_CERT_TYPE="sslClient,objectSigning"
_EXT_KEY_USAGE="serverAuth,clientAuth,ipsecIKE,ipsecIKEEnd,ipsecUser"
_VALID_MONTHS="120"
_VALID_PRE_MONTHS="-1"
_KEY_TYPE="-k rsa"
_SEED=${seedfile:+-z $seedfile}

_CA_TRUST="CT,C,T"
_IMPORT_TRUST="P,P,P"

_KEYUSAGE_ARGS="${_KEY_USAGE:+--keyUsage $_KEY_USAGE}"
_NS_CERT_TYPE_ARGS="${_NS_CERT_TYPE:+--nsCertType $_NS_CERT_TYPE}"
_EXT_KEY_USAGE_ARGS="${_EXT_KEY_USAGE:+--extKeyUsage $_EXT_KEY_USAGE}"
_VALID_ARGS="${VALID_MONTHS:+-v ${_VALID_MONTHS}} ${_VALID_PRE_MONTHS:+-w ${_VALID_PRE_MONTHS}}"

ISSUE_CONSTRAINTS="${_KEYUSAGE_ARGS} ${_NS_CERT_TYPE_ARGS} ${_EXT_KEY_USAGE_ARGS} ${_VALID_ARGS}"
##### Helper functions, for readanble code
say() {
  echo "$@" 1>&2
}

fail() {
  case $1 in
    [0-9][0-9]*) rc="${1}"; shift || : ;;
    *) rc=-1 ;;
  esac
  say "ERROR(${rc}): " "$@"
  exit $rc
}

track() {
  say "# $@"
  "$@"
}

#### Helper functions, for low-level actions
newseed() {
  if test -z "$seedfile"; then
	say "Nice to see some care about security!"
  else
	say "Oh, trading security for convinience? I will help you!"
        dd if=/dev/random of="$seedfile" bs=1024 count=1 >/dev/null 2>&1
  fi
}
certutil() {
  # See man page: https://www.manpagez.com/man/1/certutil/
  track /usr/bin/certutil -d "${NSS_DBDIR}" "$@"
}
pk12util() {
  track /usr/bin/pk12util -d "${NSS_DBDIR}" "$@"
}
named_key_exists() {
  dbid="${1}"; shift || :
  test -z "${dbid}" && fail 10 "named_key_exists: dbid required"
  certutil -L -n ${dbid} >/dev/null 2>&1
}

##### Actions that users can take

init_ca() {
  # Initialize a new CA here (should only occur in a central place)
  newseed
  selfsign="-x"
  certutil -S \
	${_KEY_TYPE} \
	${_SEED} \
	-n ${CAID} \
	-s "$(_subject ${CAID})" \
	${_VALID} \
	-t ${_CA_TRUST} ${selfsign} \
	--keyUsage digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment,keyAgreement,certSigning,crlSigning \
	--nsCertType sslServer,objectSigning,sslCA,objectSigningCA \
	--extKeyUsage ocspResponder,msTrustListSign,x509Any
}
request() {
  newseed
  dbid="${1}"; shift || :
  test -z "${dbid}" && fail 11 "request: user dbid required";
  subject="$(_subject $dbid)"
  extra="$(_extra ${dbid})"
  # Use existing key?
  if named_key_exists "${dbid}"; then
    keyopts="-k ${dbid}"
  else
    keyopts="${_KEY_TYPE} --empty-password"
  fi
  certutil -R ${_SEED} ${keyopts} -a ${req_opts} -s "${subject}" ${extra}
}

sign_locally() {
  # Signs a request from STDIN, or from the file given as $1
  infile="${1:+-i ${1}}"
  certutil -C -a -c ${CAID} ${ISSUE_CONSTRAINTS} ${infile}
}
import() {
  # Imports certificate to name: $1, from STDIN or $2 with $_IMPORT_TRUST or $3 as trust-spec
  dbid="${1}"; shift || :
  test -z "${dbid}" && fail 12 "import: dbid required"
  cf=${1:--}; shift || :
  if test "x${cf}" = "x-"; then
    certarg=""
  else
     certarg="${cf:+-i ${cf}}"
  fi
  trustarg="-t ${1:-${_IMPORT_TRUST}}"; shift || :
  certutil -A -a -n ${dbid} ${certarg} ${trustarg}
}
trust() {
  # Sets trust for $1 to $2 (default: $CA_TRUST)
  dbid="${1}"; shift || :
  test -z "${dbid}" && fail 13 "trust: dbid required"
  trust="${1:-${_CA_TRUST}}"
  certutil -M -n ${dbid} -t ${trust}
}
export_() {
  # Exports certificate for $1
  dbid="${1}"; shift || :
  test -z "${dbid}" && fail 14 "export: dbid required"
  certutil -L -a -n ${dbid}
}
host() {
  dbid="$(_hostid ${1:-${HOSTNAME}})"; shift || :
  test -z "${dbid}" && fail 15 "host: dbid required"
  request "${dbid}" \
	| sign \
	| import "${dbid}"
}

help() {
  case "$1" in 
	OK) OUT="1";;
	*) OUT="2";;
  esac
  cat >&$OUT <<EOF
usage: ${THISREF} ACTION
where ACTION is a high-level operation:
  init_ca        : Initializes or renews CA certificate
  host [HOSTNAME]: Create/resign key for a host

or a "low-level" operations:
  request ID     : Create a new cert-request (CN=ID)
  sign [REQFILE] : Creates or renews certificate
  import ID PEM  : Import a certificate
  trust ID [TRS] : Set trust for ID, (default: CA)
  export ID      : Export cert to PEM
EOF
  if test "x$OUT" = "x1"; then
    return 0
  else
    return 1
  fi
}

main() {
	case "$1" in
		init_ca) init_ca;;
		host) shift; host "$@";;
		request|req) shift; request "$@";;
		sign) shift; sign "$@";;
		import) shift; import "$@";;
		trust) shift; trust "$@";;
		export) shift; export_ "$@";;
		help|-h|-?|--help) help OK; exit $_;;
		*) help; exit $_;;
	esac
}
