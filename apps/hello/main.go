// hello is a minimal Go application targeting L4Re via tamago.
//
// Iteration 2b: imports the in-tree user/l4re overlay (added in the
// third_party/tamago submodule on the l4re-native branch). The resulting
// ELF is loaded as a native L4Re task by ned/moe. printk reaches the
// L4Re log capability via a hand-written L4 IPC trampoline; see
// docs/tamago.md for the design.

package main

import (
	"fmt"

	_ "github.com/usbarmory/tamago/user/l4re"
)

func main() {
	fmt.Println("Hello from Go on L4Re")

	// Park forever; L4Re tasks are not expected to return.
	select {}
}
