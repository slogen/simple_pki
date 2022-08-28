#!/bin/sh

#seedfile=${seedfile:-".unholy_random_seed"}

. /root/simple_pki/simple_pki.sh

remote() {
  track ssh root@fw1 /etc/ipsec.d/pki "$@"
}

sign() {
  case $HOSTNAME in
    fw1) sign_locally "$@";;
    *) remote sign "$@"
  esac
}
fetch_ca() {
  remote export ${CAID} | { sleep 2; import "${CAID}" - "${_CA_TRUST}"; }
}
dns() {
  id=${1:-${HOSTNAME}}
  # Extract the first name
  local r=${id%%.*}
  # Extract the number from that
  local i=${r##*[^0-9]}
  test -z "$i" && fail 20 "Unable to guess ip formatting from id: $id"
  cat <<EOF
10.160.0.$i
10.160.240.$i
10.172.0.$i
fd0a:a0:0:$i::
fd0a:a0:f0:$i::
fd0a:b0:$i::
$r
$r.slog.home
$r.home.slog.dk
$r.backbone.slog.home
$r.ipsec.slog.home
$r.bb
$r.mgmt.slog.home
EOF
}
_extra() {
  echo "-8" \""$(dns "$@" | tr '\n' ',' | sed -e 's/,$//g')"\"
}

case $1 in
  dns) shift; _extra "fw1";;
  auto) fetch_ca; main host;;
  fetch_ca) fetch_ca;;
  *) main "$@";;
esac

