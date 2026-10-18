package csqtt

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"
)

func TestSilentHandshakeReportsPathFailureBeforeRetry(t *testing.T) {
	srv := newFakeServer(t)
	loopbackRelay(t, nil)
	schedule := getconfSchedule
	getconfSchedule = []time.Duration{10 * time.Millisecond, 20 * time.Millisecond}
	defer func() { getconfSchedule = schedule }()
	srv.withholdTUNCONF("1", len(getconfSchedule))
	var failures, releases atomic.Int32
	get := func(context.Context, int) (Credential, error) {
		return Credential{TURNCredentials: TURNCredentials{Username: "u", Password: "p", Address: "127.0.0.1:19302"},
			Failed: func(err error) {
				if !errors.Is(err, ErrHandshakeTimeout) {
					t.Errorf("unexpected failure %v", err)
				}
				if releases.Load() != 0 {
					t.Error("failure reported after release")
				}
				failures.Add(1)
			},
			Release: func() { releases.Add(1) }}, nil
	}
	c := dialReady(t, testConfig(srv, 1, get))
	defer c.Close()
	if failures.Load() != 1 {
		t.Fatalf("failures=%d", failures.Load())
	}
}
