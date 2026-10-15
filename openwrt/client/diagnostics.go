package main

import (
	"os"
	"regexp"
	"strings"
	"sync"
)

var logURL = regexp.MustCompile(`(?i)(?:https?|csqtt)://[^\s]+`)
var logSecret = regexp.MustCompile(`(?i)(password|token|hashes|secret|session_key|username|device_id)\s*[=:]\s*[^\s,]+`)
var logOpaque = regexp.MustCompile(`[A-Za-z0-9_+/=-]{22,}`)

func cleanLog(s string) string {
	if strings.Contains(s, "vkcalls: identity") || strings.Contains(s, "vkcalls: SUCCESS") || strings.Contains(s, "step1 OK") || strings.Contains(s, "step2 OK") || strings.Contains(s, "step3 OK") || strings.Contains(s, "step4 OK") {
		return ""
	}
	s = logURL.ReplaceAllString(s, "[ссылка скрыта]")
	s = logSecret.ReplaceAllString(s, "$1=[скрыто]")
	return logOpaque.ReplaceAllString(s, "[скрыто]")
}

type diagnosticWriter struct {
	mu   sync.Mutex
	path string
}

func (w *diagnosticWriter) Write(b []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	s := cleanLog(string(b))
	if s == "" {
		return len(b), nil
	}
	if len(s) > 8192 {
		s = s[:8192] + "\n"
	}
	if info, e := os.Stat(w.path); e == nil && info.Size()+int64(len(s)) > 262144 {
		_ = os.Remove(w.path + ".1")
		_ = os.Rename(w.path, w.path+".1")
	}
	f, e := os.OpenFile(w.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if e != nil {
		return len(b), nil
	}
	defer f.Close()
	_, _ = f.WriteString(s)
	return len(b), nil
}
