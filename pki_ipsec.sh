#!/bin/sh

#seedfile=${seedfile:-".unholy_random_seed"}

. /root/simple_pki/simple_pki.sh

remote() {
  track ssh root@fw1 /etc/ipsec.d/pki "$@"
}

sign() {
  case $HOSTNAME in
    fw1) sign_locally "$@";;
    *) sign_remote "$@"
  esac
}
sign_remote() {
  # workaround piping with ssh and inputting random seed
  reqfile="cert.request"
  cat >"$reqfile" \
   && remote sign "$@" <"$reqfile" \
   && rm -f "$reqfile"
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
ip:10.160.0.$i
ip:10.160.240.$i
ip:10.172.0.$i
ip:fd0a:a0:0:$i::
ip:fd0a:a0:f0:$i::
ip:fd0a:b0:$i::
dns:$r
dns:$r.slog.home
dns:$r.home.slog.dk
dns:$r.backbone.slog.home
dns:$r.ipsec.slog.home
dns:$r.bb
dns:$r.mgmt.slog.home
EOF
}
_extra() {
  echo "--extSAN" "$(dns "$@" | tr '\n' ',' | sed -e 's/,$//g')"
}

case $1 in
  dns) shift; _extra "fw1";;
  auto) fetch_ca; main host;;
  fetch_ca) fetch_ca;;
  *) main "$@";;
esac

