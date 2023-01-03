alias tf="terraform"
function tfia() {
  tf init
  tf apply $@
}

function tfip() {
  tf init
  tf plan $@
}

function tfpl() {
  tf providers lock -platform darwin_amd64 -platform linux_amd64 -platform darwin_arm64
}

function tfaa() {
  tf apply -auto-approve
}
