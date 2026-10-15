package main

import (
	"net"
	"testing"
)

func TestDomains(t *testing.T) {
	for _, s := range []string{"Example.org", "*.example.org", "a.b.example.org."} {
		if _, e := domain(s); e != nil {
			t.Fatal(e)
		}
	}
	for _, s := range []string{"x; reboot", "https://example.org", "example.org/path", "1.1.1.1", "foo..org", "-foo.org", "com", "x.org\nflush ruleset"} {
		if _, e := domain(s); e == nil {
			t.Fatalf("accepted %q", s)
		}
	}
}
func TestDomainFile(t *testing.T) {
	list, err := domainLines("\ufeff# comment\r\nExample.org\r\n*.example.org\n\nVK.com\n")
	if err != nil || len(list) != 2 || list[0] != "example.org" || list[1] != "vk.com" {
		t.Fatalf("bad file parsing: %v %v", list, err)
	}
	if _, err = domainLines("example.org\nhttps://bad.org"); err == nil {
		t.Fatal("URL accepted")
	}
	if list, err = domainLines("# Empty list\n"); err != nil || len(list) != 0 {
		t.Fatal("empty list rejected")
	}
}
func TestLink(t *testing.T) {
	s := "csqtt://connect?v=2&host=vpn.example.org&peer=46000&password=secret%2Bvalue&hashes=first+second"
	p, e := parseLink(s)
	if e != nil || p.Password != "secret+value" || p.Hash != "first" {
		t.Fatal("valid link rejected")
	}
	for _, suffix := range []string{"&peer=3", "&token=private", "&device=%0A"} {
		if _, e := parseLink(s + suffix); e == nil {
			t.Fatal("invalid accepted")
		}
	}
	if _, e := parseLink("csqtt://connect?v=2&host=x.org&peer=99999&password=x&hashes=x"); e == nil {
		t.Fatal("bad port")
	}
}
func TestProbe(t *testing.T) {
	nonce := []byte("0123456789012345")
	p := probePacket(net.IPv4(10, 0, 0, 2), 7, nonce)
	if checksum(p[:20]) != 0 || checksum(p[20:]) != 0 {
		t.Fatal("checksum")
	}
	if isProbeReply(p, nonce) {
		t.Fatal("request accepted as reply")
	}
	copy(p[12:16], net.IPv4(1, 1, 1, 1).To4())
	p[20] = 0
	if !isProbeReply(p, nonce) {
		t.Fatal("reply rejected")
	}
	p[len(p)-1] ^= 1
	if isProbeReply(p, nonce) {
		t.Fatal("unrelated packet accepted")
	}
}
