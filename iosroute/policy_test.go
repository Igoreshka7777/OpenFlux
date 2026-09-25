package iosroute

import (
	"net"
	"testing"
)

func TestPolicy(t *testing.T) {
	p := NewPolicy("example.com\n*.blocked.test", "direct.example.com\nhttps://safe.test/path", true)
	ip := []net.IP{net.ParseIP("203.0.113.3")}
	probes := 0
	unreachable := func(string, []net.IP) bool { probes++; return false }
	if !p.Decide("www.example.com", ip, unreachable) {
		t.Fatal("explicit VPN")
	}
	if p.Decide("direct.example.com", ip, unreachable) {
		t.Fatal("direct override")
	}
	if p.Decide("safe.test", ip, unreachable) {
		t.Fatal("URL normalization")
	}
	if p.Decide("docs.datacloudmail.ru", ip, unreachable) {
		t.Fatal("transport must stay direct")
	}
	if !p.Decide("new.test", ip, unreachable) {
		t.Fatal("automatic detection")
	}
	if !p.Decide("new.test", ip, unreachable) {
		t.Fatal("cached automatic detection")
	}
	if probes != 1 {
		t.Fatalf("probe count: %d", probes)
	}
	if p.Decide("notexample.com", nil, unreachable) {
		t.Fatal("suffix boundary")
	}
}

func TestDisabledAutomatic(t *testing.T) {
	p := NewPolicy("blocked.test", "", false)
	if p.Decide("other.test", []net.IP{net.ParseIP("1.1.1.1")}, func(string, []net.IP) bool {
		t.Fatal("unexpected probe")
		return false
	}) {
		t.Fatal("default must be direct")
	}
	if !p.Decide("blocked.test", nil, nil) {
		t.Fatal("manual VPN must work without A answer")
	}
}
