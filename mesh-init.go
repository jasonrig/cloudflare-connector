// mesh-init configures only this container's network namespace, then replaces
// itself with Cloudflare's native supervisor. It needs no shell or init system.
package main

import (
	"fmt"
	"os"
	"strings"
	"syscall"
)

func ensureSysctl(path, value string) error {
	current, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(current)) == value {
		return nil
	}
	f, err := os.OpenFile(path, os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	_, err = f.WriteString(value + "\n")
	closeErr := f.Close()
	if err != nil {
		return err
	}
	return closeErr
}

func run() error {
	tun, err := os.Stat("/dev/net/tun")
	if err != nil {
		return fmt.Errorf("TUN device: %w", err)
	}
	if tun.Mode()&os.ModeCharDevice == 0 {
		return fmt.Errorf("/dev/net/tun must be a character device")
	}
	settings := []struct{ path, value string }{
		{"/proc/sys/net/ipv4/ip_forward", "1"},
		{"/proc/sys/net/ipv6/conf/all/forwarding", "1"},
		{"/proc/sys/net/ipv6/conf/default/forwarding", "1"},
		{"/proc/sys/net/ipv6/conf/all/accept_ra", "2"},
		{"/proc/sys/net/ipv6/conf/default/accept_ra", "2"},
		{"/proc/sys/net/ipv6/conf/eth0/accept_ra", "2"},
	}
	for _, setting := range settings {
		if err := ensureSysctl(setting.path, setting.value); err != nil {
			return fmt.Errorf("configure %s: %w", setting.path, err)
		}
	}
	return syscall.Exec("/entrypoint", append([]string{"/entrypoint"}, os.Args[1:]...), os.Environ())
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "mesh-init:", err)
		os.Exit(1)
	}
}
