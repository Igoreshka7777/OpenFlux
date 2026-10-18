package proxy

import "time"

// A successful TURN allocation does not prove that the relay can reach the
// VPN peer. Keep failures local to this pool/session, never in the disk cache.
const relayPathCooldown = 2 * time.Minute

func (p *CredPool) alternativePath(addr string, creds *TURNCreds) string {
	if creds == nil {
		return ""
	}
	p.pathMu.Lock()
	defer p.pathMu.Unlock()
	now := time.Now()
	if !now.Before(p.failedPaths[addr]) {
		return ""
	}
	for _, candidate := range creds.Addresses {
		if candidate != "" && candidate != addr && !now.Before(p.failedPaths[candidate]) {
			return candidate
		}
	}
	return ""
}

// replacePath preserves the credential identity and all outstanding leases.
// Counting seats across both relays is conservative. Copy instead of modifying
// a credential that another worker is reading. A late failure on the previous
// endpoint cannot replace the endpoint already chosen by another worker.
func (p *CredPool) replacePath(slot int, creds *TURNCreds, previous, next string) bool {
	p.cp.mu.Lock()
	defer p.cp.mu.Unlock()
	if !p.cp.holdsLocked(slot, creds) || p.cp.pool[slot].addr != previous {
		return false
	}
	copy := *p.cp.pool[slot].creds
	copy.Address = next
	p.cp.pool[slot].creds = &copy
	p.cp.pool[slot].addr = next
	return true
}

// ReportUnreachable is used only after an allocated relay has exhausted the
// VPN handshake retries. It is not a TURN authentication or quota failure.
// Only endpoints supplied by the credential provider can be selected.
func (p *CredPool) ReportUnreachable(slot int, creds *TURNCreds, addr string) {
	p.pathMu.Lock()
	if p.failedPaths == nil {
		p.failedPaths = make(map[string]time.Time)
	}
	first := !time.Now().Before(p.failedPaths[addr])
	if first {
		p.failedPaths[addr] = time.Now().Add(relayPathCooldown)
	}
	p.pathMu.Unlock()
	if next := p.alternativePath(addr, creds); next != "" {
		p.replacePath(slot, creds, addr, next)
	} else if first && creds != nil && len(creds.Addresses) <= 1 {
		// Older app-side bootstrap seeds contain only the primary address.
		// Fetch the full provider list once, rather than looping on that seed.
		p.cp.invalidateEntry(slot, creds)
	}
}
