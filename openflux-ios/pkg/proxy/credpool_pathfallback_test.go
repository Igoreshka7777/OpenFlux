package proxy

import (
	"context"
	"fmt"
	"testing"
	"time"
)

func TestUnreachableRelayFallsBackWithoutLosingLeases(t *testing.T) {
	const a = "192.0.2.1:19302"
	const b = "192.0.2.2:19302"
	calls := 0
	p := NewCredPool(context.Background(), CredPoolConfig{NumConns: 2, Fetch: func(bool, int) (string, *TURNCreds, error) {
		calls++
		return a, &TURNCreds{Username: fmt.Sprintf("%d:test", time.Now().Add(8*time.Hour).Unix()), Password: "p", Address: a, Addresses: []string{a, b}}, nil
	}})
	defer p.Close()
	addr, old, slot, err := p.Acquire(0)
	if err != nil || addr != a {
		t.Fatalf("initial %s %v", addr, err)
	}
	_, second, slot2, err := p.Acquire(1)
	if err != nil {
		t.Fatal(err)
	}
	p.ReportUnreachable(slot, old, a)
	next, fresh, nextSlot, err := p.Acquire(0)
	if err != nil || next != b || calls != 1 {
		t.Fatalf("fallback %s %v calls=%d", next, err, calls)
	}
	if old.Address != a {
		t.Fatal("mutated credential held by running worker")
	}
	p.ReportUnreachable(slot2, second, a)
	if got := p.cp.pool[nextSlot].addr; got != b {
		t.Fatalf("late failure changed fallback to %s", got)
	}
	p.Release(slot, old)
	p.Release(slot2, second)
	p.Release(nextSlot, fresh)
	if got := p.cp.pool[nextSlot].active; got != 0 {
		t.Fatalf("leaked %d leases", got)
	}
	p.ReportUnreachable(nextSlot, fresh, b)
	if alt := p.alternativePath(b, fresh); alt != "" {
		t.Fatal("selected another known failed path")
	}
	p.pathMu.Lock()
	p.failedPaths[a] = time.Now().Add(-time.Second)
	p.pathMu.Unlock()
	if alt := p.alternativePath(b, fresh); alt != a {
		t.Fatalf("recovered path not retried: %s", alt)
	}
}

func TestPrimaryOnlySeedRefetchesFullListOnce(t *testing.T) {
	const a = "192.0.2.1:19302"
	const b = "192.0.2.2:19302"
	calls := 0
	seed := &TURNCreds{Username: fmt.Sprintf("%d:seed", time.Now().Add(8*time.Hour).Unix()), Password: "p", Address: a, Addresses: []string{a}}
	p := NewCredPool(context.Background(), CredPoolConfig{NumConns: 1, SeededTURN: seed, Fetch: func(bool, int) (string, *TURNCreds, error) {
		calls++
		return a, &TURNCreds{Username: fmt.Sprintf("%d:full", time.Now().Add(8*time.Hour).Unix()), Password: "p", Address: a, Addresses: []string{a, b}}, nil
	}})
	defer p.Close()
	addr, c, s, e := p.Acquire(0)
	if e != nil {
		t.Fatal(e)
	}
	p.ReportUnreachable(s, c, addr)
	p.Release(s, c)
	addr, c, s, e = p.Acquire(0)
	if e != nil || addr != b || calls != 1 {
		t.Fatalf("refetch addr=%s calls=%d err=%v", addr, calls, e)
	}
	p.Release(s, c)
}
