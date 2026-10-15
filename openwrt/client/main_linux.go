// OpenFlux OpenWrt client: Linux TUN integration and router health control.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/cacggghp/vk-turn-proxy/pkg/csqtt"
	"github.com/cacggghp/vk-turn-proxy/pkg/proxy"
	"golang.org/x/sys/unix"
)

const version = "0.1.2"
const helper = "/usr/libexec/openflux-network"
const runtimeDir = "/var/run/openflux"

func command(name string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	c := exec.CommandContext(ctx, name, args...)
	if c.Run() != nil {
		return fmt.Errorf("не выполнен %s", filepath.Base(name))
	}
	return nil
}
func uci(key string) string {
	b, _ := exec.Command("uci", "-q", "get", "openflux.main."+key).Output()
	return strings.TrimSpace(string(b))
}

var started = time.Now()

func status(state string, tx, rx int64, detail ...csqtt.Stats) {
	v := map[string]any{"state": state, "tx": tx, "rx": rx, "updated": time.Now().Unix(), "version": version, "elapsed": int64(time.Since(started).Seconds())}
	var info unix.Sysinfo_t
	if unix.Sysinfo(&info) == nil {
		v["uptime"] = info.Uptime
	}
	if len(detail) > 0 {
		s := detail[0]
		v["ready"] = s.Ready
		v["workers"] = s.Total
		v["restarts"] = s.Restarts
		v["stalls"] = s.WriteStalls
		v["dropped"] = s.Dropped
	}
	b, _ := json.Marshal(v)
	_ = os.WriteFile(runtimeDir+"/status.tmp", b, 0644)
	_ = os.Rename(runtimeDir+"/status.tmp", runtimeDir+"/status.json")
}
func stableDevice(p profile) (string, error) {
	if p.Device != "" {
		return p.Device, nil
	}
	const f = "/etc/openflux/device-id"
	if b, e := os.ReadFile(f); e == nil {
		s := strings.TrimSpace(string(b))
		if tokenPart.MatchString(s) {
			return s, nil
		}
		return "", errors.New("повреждён идентификатор роутера")
	}
	b := make([]byte, 16)
	if _, e := rand.Read(b); e != nil {
		return "", e
	}
	if e := os.MkdirAll(filepath.Dir(f), 0700); e != nil {
		return "", e
	}
	id := hex.EncodeToString(b)
	return id, os.WriteFile(f, []byte(id), 0600)
}

func main() {
	check := flag.Bool("check", false, "проверить настройки без подключения")
	domains := flag.Bool("domains", false, "проверить и вывести домены напрямую")
	diagnose := flag.Bool("diagnose", false, "проверка туннеля без изменения маршрутов")
	ver := flag.Bool("version", false, "номер версии")
	flag.Parse()
	if *ver {
		fmt.Println(version)
		return
	}
	_ = os.MkdirAll(runtimeDir, 0755)
	log.SetOutput(&diagnosticWriter{path: runtimeDir + "/client.log"})
	domainText, fileErr := os.ReadFile("/etc/openflux/direct-domains.txt")
	if os.IsNotExist(fileErr) {
		domainText = []byte(strings.Join(strings.Fields(uci("direct_domain")), "\n"))
	} else if fileErr != nil {
		log.Fatal("не удалось прочитать файл доменов")
	}
	domainList, domainErr := domainLines(string(domainText))
	if domainErr != nil {
		log.Fatal(domainErr)
	}
	for _, d := range domainList {
		if *domains {
			fmt.Println(d)
		}
	}
	if *domains {
		return
	}
	p, e := resolveLink(context.Background(), uci("link"), "/etc/openflux", nil)
	if e != nil {
		log.Print(e)
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
	if *check {
		fmt.Println("Настройки проверены")
		return
	}
	_ = os.MkdirAll(runtimeDir, 0755)
	lock, e := os.OpenFile(runtimeDir+"/client.lock", os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		log.Fatal("Не удалось создать блокировку")
	}
	defer lock.Close()
	if unix.Flock(int(lock.Fd()), unix.LOCK_EX|unix.LOCK_NB) != nil {
		log.Fatal("OpenFlux уже запущен")
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	if *diagnose {
		ctx, cancel := context.WithTimeout(ctx, 40*time.Second)
		defer cancel()
		if e := run(ctx, p, true); e != nil {
			fmt.Fprintln(os.Stderr, cleanLog(e.Error()))
			os.Exit(1)
		}
		return
	}
	status("connecting", 0, 0)
	log.Printf("OpenFlux %s: запуск подключения", version)
	e = run(ctx, p, false)
	_ = command(helper, "direct")
	if e != nil && ctx.Err() == nil {
		status("reconnecting", 0, 0)
		log.Printf("Причина: %v. Интернет идёт напрямую; повтор через 15 секунд", e)
		os.Exit(1)
	}
	status("stopped", 0, 0)
	log.Print("OpenFlux остановлен")
}

func run(ctx context.Context, p profile, diagnose bool) error {
	id, e := stableDevice(p)
	if e != nil {
		return e
	}
	peer, e := net.ResolveUDPAddr("udp4", p.Server)
	if e != nil {
		return e
	}
	var mu sync.Mutex
	var creds *proxy.TURNCreds
	used := 0
	getCreds := func(ctx context.Context, worker int) (csqtt.Credential, error) {
		mu.Lock()
		defer mu.Unlock()
		if ctx.Err() != nil {
			return csqtt.Credential{}, ctx.Err()
		}
		if creds == nil || used >= 4 {
			log.Printf("Канал %d: получение доступа к реле VK", worker)
			var err error
			creds, err = proxy.GetVKCreds(p.Hash, nil, "", "", 0, 0, "", "")
			if err != nil {
				return csqtt.Credential{}, errors.New("не удалось получить подключение")
			}
			used = 0
		}
		used++
		return csqtt.Credential{TURNCredentials: csqtt.TURNCredentials{Username: creds.Username, Password: creds.Password, Address: creds.Address}}, nil
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	timer := time.AfterFunc(60*time.Second, cancel)
	gen, salt := csqtt.NewIdentity(0)
	workers, _ := strconv.Atoi(uci("workers"))
	if workers < 2 || workers > 18 {
		workers = 8
	}
	log.Printf("Сервер %s; параллельных каналов: %d", peer, workers)
	client, e := csqtt.Dial(ctx, csqtt.Config{Server: peer, Password: p.Password, DeviceID: id, Generation: gen, Salt: salt, Workers: workers, Creds: getCreds, TURNTransport: "tcp", WriteStall: 4 * time.Second, StartPacing: 200 * time.Millisecond, Logf: log.Printf})
	timer.Stop()
	if e != nil {
		return e
	}
	defer client.Close()
	log.Print("Ответ VPN-сервера получен; проверяем передачу данных")
	ip := net.ParseIP(client.Config().TunnelIP).To4()
	if ip == nil {
		return errors.New("не получен адрес VPN")
	}
	if diagnose {
		nonce := make([]byte, 16)
		_, _ = rand.Read(nonce)
		for seq := uint16(0); seq < 3; seq++ {
			sent := time.Now()
			if err := client.WritePacket(probePacket(ip, seq, nonce)); err != nil {
				return err
			}
			for {
				b, err := client.ReadPacket(ctx)
				if err != nil {
					return err
				}
				if isProbeReply(b, nonce) {
					fmt.Printf("Ответ через OpenFlux: %d мс; каналы %d/%d\n", time.Since(sent).Milliseconds(), client.Stats().Ready, client.Stats().Total)
					break
				}
			}
		}
		return nil
	}
	fd, e := unix.Open("/dev/net/tun", unix.O_RDWR|unix.O_CLOEXEC, 0)
	if e != nil {
		return e
	}
	req, _ := unix.NewIfreq("oflux0")
	req.SetUint16(unix.IFF_TUN | unix.IFF_NO_PI)
	if e = unix.IoctlIfreq(fd, unix.TUNSETIFF, req); e != nil {
		unix.Close(fd)
		return e
	}
	dev := os.NewFile(uintptr(fd), "oflux0")
	defer dev.Close()
	if e = command("ip", "addr", "replace", ip.String()+"/32", "dev", "oflux0"); e != nil {
		return e
	}
	if e = command("ip", "link", "set", "dev", "oflux0", "mtu", "1300", "up"); e != nil {
		return e
	}
	if e = command(helper, "tunnel"); e != nil {
		return e
	}
	defer command(helper, "direct")
	nonce := make([]byte, 16)
	_, _ = rand.Read(nonce)
	var lastReply atomic.Int64
	faults := make(chan error, 2)
	go func() {
		b := make([]byte, 65536)
		for {
			n, e := dev.Read(b)
			if e != nil {
				faults <- e
				return
			}
			if e = client.WritePacket(b[:n]); e != nil && client.Err() != nil {
				faults <- e
				return
			}
		}
	}()
	go func() {
		for {
			b, e := client.ReadPacket(ctx)
			if e != nil {
				faults <- e
				return
			}
			if isProbeReply(b, nonce) {
				lastReply.Store(time.Now().UnixNano())
				continue
			}
			if _, e = dev.Write(b); e != nil {
				faults <- e
				return
			}
		}
	}()
	tick := time.NewTicker(5 * time.Second)
	defer tick.Stop()
	seq := uint16(0)
	active := false
	lastProbeReply := int64(0)
	good := 0
	ticks := 0
	_ = client.WritePacket(probePacket(ip, seq, nonce))
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-client.Done():
			return client.Err()
		case e := <-faults:
			return e
		case <-tick.C:
			reply := lastReply.Load()
			healthy := reply > 0 && time.Since(time.Unix(0, reply)) < 15*time.Second
			if reply != lastProbeReply {
				good++
				lastProbeReply = reply
			} else if !healthy {
				good = 0
			}
			target := healthy && (active || good >= 2)
			if target || target != active {
				mode := "direct"
				if target {
					mode = "vpn"
				}
				if e = command(helper, mode); e != nil {
					return e
				}
				if target != active {
					log.Printf("Маршрутизация: %s; проверка туннеля: %t", mode, healthy)
				}
				active = target
			}
			stats := client.Stats()
			state := "direct"
			if active {
				state = "connected"
			}
			status(state, stats.TxBytes, stats.RxBytes, stats)
			ticks++
			if ticks%6 == 0 {
				log.Printf("Статистика: каналы %d/%d; принято %d; отправлено %d; перезапуски %d; зависшие записи %d; потери %d", stats.Ready, stats.Total, stats.RxBytes, stats.TxBytes, stats.Restarts, stats.WriteStalls, stats.Dropped)
			}
			seq++
			_ = client.WritePacket(probePacket(ip, seq, nonce))
		}
	}
}
