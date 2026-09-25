package iosroute

import (
	"net"
	"net/url"
	"strings"
	"sync"
	"time"
)

// Policy decides which DNS names should use the packet tunnel. Direct access is
// the default. Explicit direct entries take precedence over explicit VPN entries.
type Policy struct {
	direct    []string
	vpn       []string
	automatic bool
	mu        sync.Mutex
	cache     map[string]cachedDecision
}

type cachedDecision struct {
	tunnel  bool
	expires time.Time
}

func NewPolicy(vpnText, directText string, automatic bool) *Policy {
	direct := parseDomains(directText)
	// The tunnel's own Mail.ru connection must stay on the physical network.
	direct = append(direct, "cloud.mail.ru", "datacloudmail.ru")
	return &Policy{
		direct:    direct,
		vpn:       parseDomains(vpnText),
		automatic: automatic,
		cache:     make(map[string]cachedDecision),
	}
}

func parseDomains(text string) []string {
	var out []string
	seen := map[string]bool{}
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.ToLower(line)
		line = strings.TrimPrefix(line, "*.")
		line = strings.TrimPrefix(line, ".")
		if strings.Contains(line, "://") {
			parsed, err := url.Parse(line)
			if err != nil {
				continue
			}
			line = parsed.Hostname()
		}
		line = strings.TrimSuffix(line, ".")
		if strings.ContainsAny(line, " /@:*?[]") || !strings.Contains(line, ".") || seen[line] {
			continue
		}
		seen[line] = true
		out = append(out, line)
	}
	return out
}

func matches(domain string, entries []string) bool {
	for _, entry := range entries {
		if domain == entry || strings.HasSuffix(domain, "."+entry) {
			return true
		}
	}
	return false
}

// Decide returns true for VPN. probe must return true only when the site is
// reachable directly. It is never called for explicit rules or when automatic
// detection is disabled.
func (p *Policy) Decide(domain string, ips []net.IP, probe func(string, []net.IP) bool) bool {
	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if matches(domain, p.direct) {
		return false
	}
	if matches(domain, p.vpn) {
		return true
	}
	if !p.automatic || len(ips) == 0 || probe == nil {
		return false
	}

	p.mu.Lock()
	cached, ok := p.cache[domain]
	p.mu.Unlock()
	if ok && time.Now().Before(cached.expires) {
		return cached.tunnel
	}

	tunnel := !probe(domain, ips)
	p.mu.Lock()
	if len(p.cache) > 2048 {
		p.cache = make(map[string]cachedDecision)
	}
	p.cache[domain] = cachedDecision{tunnel: tunnel, expires: time.Now().Add(5 * time.Minute)}
	p.mu.Unlock()
	return tunnel
}

func (p *Policy) IsExplicitVPN(domain string) bool {
	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	return !matches(domain, p.direct) && matches(domain, p.vpn)
}
