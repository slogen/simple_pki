#!/bin/sh

#seedfile=${seedfile:-".unholy_random_seed"}

. /etc/pki/simple_pki.sh

remote() {
  track ssh root@fw1 /etc/ipsec.d/pki.sh "$@"
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
  local r=${id%%.*}
  cat <<EOF
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
  echo "-8" "$(dns "$@" | tr '\n' ',' | sed -e 's/,$//g')"
}

case $1 in
  dns) shift; _extra "foo.slog.home";;
  auto) fetch_ca; main host;;
  fetch_ca) fetch_ca;;
  *) main "$@";;
esac

