package main

import (
	"context"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type fakeTransport func(*http.Request) (*http.Response, error)

func (f fakeTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestShortLinkImportAndOfflineCache(t *testing.T) {
	calls := 0
	dir := t.TempDir()
	url := "https://openfluxvpn.ru/s/abcdefghijklmnopqrstuv"
	transport := fakeTransport(func(r *http.Request) (*http.Response, error) {
		calls++
		if r.Header.Get("Accept") != "application/vnd.openflux.connection" {
			t.Fatal("missing accept")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("csqtt://connect?v=2&host=vpn.example.org&peer=46000&password=private&hashes=first")), Header: make(http.Header)}, nil
	})
	for i := 0; i < 2; i++ {
		p, e := resolveLink(context.Background(), url, dir, transport)
		if e != nil || p.Hash != "first" {
			t.Fatal(p, e)
		}
	}
	if calls != 1 {
		t.Fatal("cache not reused", calls)
	}
	for _, bad := range []string{"http://openfluxvpn.ru/s/abcdefghijklmnopqrstuv", "https://evil.example/s/abcdefghijklmnopqrstuv", "https://openfluxvpn.ru/s/abcdefghijklmnopqrstuv?x=1"} {
		if _, e := resolveLink(context.Background(), bad, dir, transport); e == nil {
			t.Fatal("accepted", bad)
		}
	}
	if calls != 1 {
		t.Fatal("unsafe request")
	}
}
func TestShortLinkRejectsResponse(t *testing.T) {
	for _, body := range []string{"<html>login</html>", strings.Repeat("x", 8193)} {
		tr := fakeTransport(func(r *http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header)}, nil
		})
		if _, e := resolveLink(context.Background(), "https://openfluxvpn.ru/s/abcdefghijklmnopqrstuv", t.TempDir(), tr); e == nil {
			t.Fatal("accepted invalid response")
		}
	}
	tr := fakeTransport(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 302, Body: io.NopCloser(strings.NewReader("")), Header: http.Header{"Location": []string{"https://evil.example"}}}, nil
	})
	if _, e := resolveLink(context.Background(), "https://openfluxvpn.ru/s/abcdefghijklmnopqrstuv", t.TempDir(), tr); e == nil {
		t.Fatal("accepted redirect")
	}
}
func TestLogPrivacyAndBound(t *testing.T) {
	raw := "password=private token=private https://openfluxvpn.ru/s/abcdefghijklmnopqrstuv csqtt://connect?password=private abcdefghijklmnopqrstuvwxyz012345"
	s := cleanLog(raw)
	for _, value := range []string{"private", "abcdefghijklmnopqrstuv", "csqtt://", "abcdefghijklmnopqrstuvwxyz012345"} {
		if strings.Contains(s, value) {
			t.Fatal("secret leaked")
		}
	}
	p := filepath.Join(t.TempDir(), "log")
	w := &diagnosticWriter{path: p}
	for i := 0; i < 100; i++ {
		_, _ = w.Write([]byte(strings.Repeat("test ", 1000) + "\n"))
	}
	for _, name := range []string{p, p + ".1"} {
		st, e := os.Stat(name)
		if e != nil || st.Size() > 262144 {
			t.Fatal("unbounded log", e)
		}
	}
}
