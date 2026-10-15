package main

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

func domainLines(text string) ([]string, error) {
	if len(text) > 262144 {
		return nil, errors.New("список доменов больше 256 КБ")
	}
	var result []string
	seen := map[string]bool{}
	for i, line := range strings.Split(strings.TrimPrefix(text, "\ufeff"), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		d, err := domain(line)
		if err != nil {
			return nil, fmt.Errorf("строка %d: %w", i+1, err)
		}
		if !seen[d] {
			result = append(result, d)
			seen[d] = true
		}
	}
	if len(result) > 10000 {
		return nil, errors.New("не больше 10000 доменов")
	}
	return result, nil
}

type profile struct{ Server, Password, Hash, Device string }

var hostLabel = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$`)
var tokenPart = regexp.MustCompile(`^[A-Za-z0-9_-]{1,256}$`)

func domain(s string) (string, error) {
	s = strings.ToLower(strings.TrimSuffix(strings.TrimSpace(s), "."))
	s = strings.TrimPrefix(s, "*.")
	if len(s) > 253 || !strings.Contains(s, ".") || net.ParseIP(s) != nil {
		return "", errors.New("укажите домен, например example.org")
	}
	for _, p := range strings.Split(s, ".") {
		if !hostLabel.MatchString(p) {
			return "", errors.New("домен содержит недопустимые символы; для кириллицы используйте punycode")
		}
	}
	return s, nil
}

func parseLink(raw string) (profile, error) {
	var p profile
	bad := errors.New("нужна полная ссылка csqtt://connect?v=2&host=…&peer=…&password=…&hashes=…")
	raw = strings.ReplaceAll(strings.TrimSpace(raw), "&amp;", "&")
	if len(raw) > 8000 {
		return p, bad
	}
	u, e := url.Parse(raw)
	if e != nil || u.Scheme != "csqtt" || u.Host != "connect" || u.User != nil {
		return p, bad
	}
	q, e := url.ParseQuery(u.RawQuery)
	if e != nil {
		return p, bad
	}
	for _, values := range q {
		if len(values) != 1 {
			return p, bad
		}
	}
	if q.Get("v") != "2" {
		return p, bad
	}
	host := q.Get("host")
	port, e := strconv.Atoi(q.Get("peer"))
	if e != nil || port < 1 || port > 65535 || len(host) > 253 || strings.ContainsAny(host, " /\\\r\n\t") {
		return p, bad
	}
	if net.ParseIP(host) == nil {
		if _, e = domain(host); e != nil {
			return p, bad
		}
	}
	p.Server = net.JoinHostPort(host, strconv.Itoa(port))
	p.Password = q.Get("password")
	if len(p.Password) < 1 || len(p.Password) > 1024 || strings.ContainsAny(p.Password, "\x00\r\n") {
		return profile{}, bad
	}
	hashes := strings.Fields(strings.ReplaceAll(q.Get("hashes"), "+", " "))
	if len(hashes) == 0 || !tokenPart.MatchString(hashes[0]) {
		return profile{}, bad
	}
	p.Hash = hashes[0]
	p.Device = q.Get("device")
	if p.Device != "" && !tokenPart.MatchString(p.Device) {
		return profile{}, bad
	}
	// Account-token links need a separate token flow; never silently ignore one.
	if q.Get("token") != "" {
		return profile{}, errors.New("для роутера нужна ссылка с приглашением VK без персонального токена")
	}
	return p, nil
}
