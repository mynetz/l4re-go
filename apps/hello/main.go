// hello is a minimal Go application targeting L4Re via tamago.
//
// During iteration 2a (toolchain smoke test) the application imports the
// upstream user/linux overlay and runs as a normal Linux process compiled
// with GOOS=tamago. Iteration 2b will swap the import for user/l4re once
// that overlay exists in third_party/tamago.

package main

import (
	"fmt"

	_ "github.com/usbarmory/tamago/user/linux"
)

func main() {
	fmt.Println("Hello from Go (tamago user/linux smoke test)")
}
