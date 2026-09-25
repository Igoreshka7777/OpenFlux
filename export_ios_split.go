//go:build ios

package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"crypto/tls"
	"log"
	"net"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/net/dns/dnsmessage"

	"openflux/iosroute"
	"openflux/utils"
)

const maxSplitRoutes = 512

type routeRequest struct {
	done    chan struct{}
	success bool
}

var splitState = struct {
	mu        sync.Mutex
	policy    *iosroute.Policy
	ready     []string
	waiting   map[string]*routeRequest
	installed map[string]bool
}{
	waiting:   make(map[string]*routeRequest),
	installed: make(map[string]bool),
}

func configureSplit(vpnDomains, directDomains string, automatic bool) {
	splitState.mu.Lock()
	defer splitState.mu.Unlock()
	for _, req := range splitState.waiting {
		close(req.done)
	}
	splitState.policy = iosroute.NewPolicy(vpnDomains, directDomains, automatic)
	splitState.ready = nil
	splitState.waiting = make(map[string]*routeRequest)
	splitState.installed = make(map[string]bool)
}

func stopSplit() {
	splitState.mu.Lock()
	defer splitState.mu.Unlock()
	for _, req := range splitState.waiting {
		close(req.done)
	}
	splitState.policy = nil
	splitState.ready = nil
	splitState.waiting = make(map[string]*routeRequest)
	splitState.installed = make(map[string]bool)
}

//export OpenFluxTunNextRoute
func OpenFluxTunNextRoute(buf *C.char, max C.int) C.int {
	if buf == nil || max < 16 {
		return 0
	}
	splitState.mu.Lock()
	if len(splitState.ready) == 0 {
		splitState.mu.Unlock()
		return 0
	}
	ip := splitState.ready[0]
	splitState.ready = splitState.ready[1:]
	splitState.mu.Unlock()
	out := unsafe.Slice((*byte)(unsafe.Pointer(buf)), int(max))
	n := copy(out, ip)
	out[n] = 0
	return C.int(n)
}

//export OpenFluxTunAckRoute
func OpenFluxTunAckRoute(ip *C.char, success C.int) {
	if ip == nil {
		return
	}
	key := C.GoString(ip)
	splitState.mu.Lock()
	defer splitState.mu.Unlock()
	req := splitState.waiting[key]
	if req == nil {
		return
	}
	req.success = success != 0
	if req.success {
		splitState.installed[key] = true
	}
	delete(splitState.waiting, key)
	close(req.done)
}

func ensureRoute(ip net.IP) bool {
	key := ip.To4().String()
	if key == "<nil>" {
		return false
	}
	splitState.mu.Lock()
	if splitState.installed[key] {
		splitState.mu.Unlock()
		return true
	}
	req := splitState.waiting[key]
	if req == nil {
		if len(splitState.installed) >= maxSplitRoutes {
			splitState.mu.Unlock()
			utils.Debugf("[SPLIT] route limit reached")
			return false
		}
		req = &routeRequest{done: make(chan struct{})}
		splitState.waiting[key] = req
		splitState.ready = append(splitState.ready, key)
	}
	splitState.mu.Unlock()

	select {
	case <-req.done:
		return req.success
	case <-time.After(5 * time.Second):
		splitState.mu.Lock()
		if splitState.waiting[key] == req {
			delete(splitState.waiting, key)
			close(req.done)
		}
		splitState.mu.Unlock()
		return req.success
	}
}

// Direct TLS reachability is a heuristic. Explicit rules override its result.
// All checks share a short deadline so ordinary DNS lookups stay responsive.
func probeDirectTLS(domain string, ips []net.IP) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 1200*time.Millisecond)
	defer cancel()
	count := len(ips)
	if count > 2 {
		count = 2
	}
	results := make(chan bool, count)
	for _, ip := range ips[:count] {
		addr := net.JoinHostPort(ip.String(), "443")
		go func() {
			dialer := &tls.Dialer{
				NetDialer: &net.Dialer{Timeout: 1100 * time.Millisecond},
				Config:    &tls.Config{ServerName: domain, MinVersion: tls.VersionTLS12},
			}
			conn, err := dialer.DialContext(ctx, "tcp", addr)
			if err == nil {
				conn.Close()
			}
			results <- err == nil
		}()
	}
	for i := 0; i < count; i++ {
		select {
		case reachable := <-results:
			if reachable {
				return true
			}
		case <-ctx.Done():
			return false
		}
	}
	return false
}

// routeDNS applies a VPN route before a DNS answer exposes its destination IP.
// A false return means the DNS answer must not be released directly.
func routeDNS(query, answer []byte) ([]byte, bool) {
	splitState.mu.Lock()
	policy := splitState.policy
	splitState.mu.Unlock()
	if policy == nil {
		return answer, true
	}

	question, err := iosroute.ParseQuestion(query)
	if err != nil {
		return answer, true
	}
	switch question.Type {
	case dnsmessage.TypeA:
		ips := iosroute.IPv4Answers(answer)
		if !policy.Decide(question.Domain, ips, probeDirectTLS) {
			return answer, true
		}
		for _, ip := range ips {
			if !ensureRoute(ip) {
				return nil, false
			}
		}
		log.Printf("[VPN] %s: добавлено %d маршрутов", question.Domain, len(ips))
		return answer, true

	case dnsmessage.TypeAAAA:
		// IPv6 packets cannot cross the current TCP-only Mail.ru exit node.
		// Find IPv4 destinations for the same name and suppress AAAA only when
		// the domain is assigned to VPN, preventing an IPv6 direct bypass.
		aQuery, err := iosroute.BuildAQuery(question)
		if err != nil {
			if policy.IsExplicitVPN(question.Domain) {
				return nil, false
			}
			return answer, true
		}
		aAnswer, err := dnsOverTLS(aQuery)
		if err != nil {
			if policy.IsExplicitVPN(question.Domain) {
				return nil, false
			}
			return answer, true
		}
		ips := iosroute.IPv4Answers(aAnswer)
		if !policy.Decide(question.Domain, ips, probeDirectTLS) {
			return answer, true
		}
		for _, ip := range ips {
			if !ensureRoute(ip) {
				return nil, false
			}
		}
		empty, err := iosroute.EmptyAAAA(answer)
		if err != nil {
			return nil, false
		}
		return empty, true
	}
	return answer, true
}
