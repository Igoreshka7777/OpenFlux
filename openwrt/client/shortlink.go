package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var shortLinkPattern = regexp.MustCompile(`^https://openfluxvpn\.ru/s/[A-Za-z0-9_-]{22}$`)

func resolveLink(ctx context.Context, raw, cacheDir string, transport http.RoundTripper) (profile, error) {
	raw = strings.TrimSpace(raw)
	if !shortLinkPattern.MatchString(raw) {
		return parseLink(raw)
	}
	sum := sha256.Sum256([]byte(raw))
	cache := filepath.Join(cacheDir, "profile-"+hex.EncodeToString(sum[:])+".json")
	// Resolve once, like the mobile apps: reconnect also works when the website is unavailable.
	if b, e := os.ReadFile(cache); e == nil {
		var saved string
		if json.Unmarshal(b, &saved) == nil {
			if p, e := parseLink(saved); e == nil {
				return p, nil
			}
		}
	}
	client := &http.Client{Timeout: 12 * time.Second, Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, e := http.NewRequestWithContext(ctx, http.MethodGet, raw, nil)
	if e != nil {
		return profile{}, errors.New("неверная короткая ссылка")
	}
	req.Header.Set("Accept", "application/vnd.openflux.connection")
	response, e := client.Do(req)
	if e != nil {
		return profile{}, errors.New("не удалось получить короткую ссылку: проверьте интернет и время роутера")
	}
	defer response.Body.Close()
	if response.StatusCode == 404 {
		return profile{}, errors.New("короткая ссылка не найдена")
	}
	if response.StatusCode != 200 {
		return profile{}, errors.New("сервис коротких ссылок временно недоступен")
	}
	b, e := io.ReadAll(io.LimitReader(response.Body, 8193))
	if e != nil || len(b) > 8192 {
		return profile{}, errors.New("неполный или слишком большой ответ сервиса ссылок")
	}
	resolved := strings.TrimSpace(string(b))
	p, e := parseLink(resolved)
	if e != nil {
		return profile{}, e
	}
	if e = os.MkdirAll(cacheDir, 0700); e != nil {
		return profile{}, errors.New("не удалось сохранить настройки ссылки")
	}
	b, _ = json.Marshal(resolved)
	if e = os.WriteFile(cache+".tmp", b, 0600); e != nil {
		return profile{}, errors.New("не удалось сохранить настройки ссылки")
	}
	if e = os.Rename(cache+".tmp", cache); e != nil {
		return profile{}, errors.New("не удалось сохранить настройки ссылки")
	}
	return p, nil
}
