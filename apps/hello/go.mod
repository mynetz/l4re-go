module l4re-go-prj/apps/hello

go 1.26.2

require github.com/usbarmory/tamago v1.26.2

// Use the in-tree fork (third_party/tamago, branch l4re-native) so any
// changes we land in user/l4re/ are picked up automatically. The required
// version above is the upstream tag the submodule HEAD currently matches;
// it is consumed by cmd/tamago to select the matching tamago-go toolchain.
replace github.com/usbarmory/tamago => ../../third_party/tamago

// Pin the cmd/tamago helper as a Go tool so 'go tool tamago' resolves to
// our forked submodule.
tool github.com/usbarmory/tamago/cmd/tamago
