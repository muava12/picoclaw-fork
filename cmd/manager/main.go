package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"
)

var (
	version            = "0.0.1"
	defaultPort        = 8321
	defaultRepo        = "muava12/picoclaw-fork"
	defaultPicoClawBin = filepath.Join(getHomeDir(), ".local", "bin", "picoclaw")
	defaultConfigPath  = filepath.Join(getHomeDir(), ".picoclaw", "config.json")
)

func getHomeDir() string {
	dir, _ := os.UserHomeDir()
	return dir
}

type Manager struct {
	PicoClawBin string
	ConfigPath  string
	Repo        string

	mu          sync.Mutex
	cmd         *exec.Cmd
	startedAt   time.Time
	logTail     []string
	maxLogLines int
}

func NewManager(bin, config, repo string) *Manager {
	return &Manager{
		PicoClawBin: bin,
		ConfigPath:  config,
		Repo:        repo,
		maxLogLines: 100,
		logTail:     make([]string, 0),
	}
}

func (m *Manager) IsRunning() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.cmd != nil && m.cmd.Process != nil && m.cmd.ProcessState == nil
}

func (m *Manager) Status() map[string]interface{} {
	running := m.IsRunning()
	
	m.mu.Lock()
	defer m.mu.Unlock()

	var pid *int
	var uptime *int
	var startedAt *string

	if running && m.cmd != nil && m.cmd.Process != nil {
		p := m.cmd.Process.Pid
		pid = &p
		u := int(time.Since(m.startedAt).Seconds())
		uptime = &u
		s := m.startedAt.Format(time.RFC3339)
		startedAt = &s
	}

	tail := m.logTail
	if len(tail) > 20 {
		tail = tail[len(tail)-20:]
	}

	return map[string]interface{}{
		"running":        running,
		"pid":            pid,
		"started_at":     startedAt,
		"uptime_seconds": uptime,
		"binary":         m.PicoClawBin,
		"recent_logs":    tail,
	}
}

func (m *Manager) Start() map[string]interface{} {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.cmd != nil && m.cmd.Process != nil && m.cmd.ProcessState == nil {
		return map[string]interface{}{
			"success": false,
			"message": "PicoClaw gateway sudah berjalan",
			"pid":     m.cmd.Process.Pid,
		}
	}

	return m.startProcess()
}

func (m *Manager) Stop() map[string]interface{} {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.cmd == nil || m.cmd.Process == nil || m.cmd.ProcessState != nil {
		return map[string]interface{}{
			"success": true,
			"message": "PicoClaw gateway tidak sedang berjalan",
		}
	}

	return m.stopProcess()
}

func (m *Manager) Restart() map[string]interface{} {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.cmd != nil && m.cmd.Process != nil && m.cmd.ProcessState == nil {
		m.stopProcess()
		time.Sleep(1 * time.Second)
	}

	return m.startProcess()
}

func (m *Manager) startProcess() map[string]interface{} {
	if _, err := os.Stat(m.PicoClawBin); os.IsNotExist(err) {
		return map[string]interface{}{
			"success": false,
			"message": fmt.Sprintf("Binary tidak ditemukan: %s", m.PicoClawBin),
		}
	}

	m.cmd = exec.Command(m.PicoClawBin, "gateway")
	
	// Create new process group
	m.cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	env := os.Environ()
	// Extremely simple .env loading
	envFile := filepath.Join(filepath.Dir(m.PicoClawBin), ".env")
	if _, err := os.Stat(envFile); err == nil {
		if content, err := os.ReadFile(envFile); err == nil {
			lines := strings.Split(string(content), "\n")
			for _, line := range lines {
				line = strings.TrimSpace(line)
				if line != "" && !strings.HasPrefix(line, "#") {
					parts := strings.SplitN(line, "=", 2)
					if len(parts) == 2 {
						env = append(env, fmt.Sprintf("%s=%s", strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1])))
					}
				}
			}
		}
	}
	m.cmd.Env = env

	stdout, err := m.cmd.StdoutPipe()
	if err != nil {
		return map[string]interface{}{
			"success": false,
			"message": fmt.Sprintf("Gagal menyiapkan pipe: %v", err),
		}
	}
	m.cmd.Stderr = m.cmd.Stdout // merge stderr to stdout

	m.logTail = make([]string, 0)

	if err := m.cmd.Start(); err != nil {
		log.Printf("✗ Gagal menjalankan PicoClaw: %v", err)
		return map[string]interface{}{
			"success": false,
			"message": fmt.Sprintf("Gagal menjalankan PicoClaw: %v", err),
		}
	}

	m.startedAt = time.Now()

	go func() {
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			line := scanner.Text()
			log.Printf("[picoclaw] %s", line)
			
			m.mu.Lock()
			m.logTail = append(m.logTail, line)
			if len(m.logTail) > m.maxLogLines {
				m.logTail = m.logTail[1:]
			}
			m.mu.Unlock()
		}
		// Process exited
		m.cmd.Wait()
	}()

	log.Printf("✓ PicoClaw gateway started (PID: %d)", m.cmd.Process.Pid)
	return map[string]interface{}{
		"success": true,
		"message": "PicoClaw gateway berhasil dijalankan",
		"pid":     m.cmd.Process.Pid,
	}
}

func (m *Manager) stopProcess() map[string]interface{} {
	pid := m.cmd.Process.Pid
	
	// Send SIGTERM to process group
	pgid, err := syscall.Getpgid(pid)
	if err == nil {
		syscall.Kill(-pgid, syscall.SIGTERM)
	} else {
		m.cmd.Process.Signal(syscall.SIGTERM)
	}

	// Wait graceful shutdown
	done := make(chan error, 1)
	go func() {
		done <- m.cmd.Wait()
	}()

	select {
	case <-time.After(5 * time.Second):
		log.Printf("Force killing PID: %d", pid)
		if pgid > 0 {
			syscall.Kill(-pgid, syscall.SIGKILL)
		} else {
			m.cmd.Process.Kill()
		}
		<-done // Let it finish
	case <-done:
	}

	log.Printf("✓ PicoClaw gateway stopped (PID: %d)", pid)
	m.cmd = nil

	return map[string]interface{}{
		"success": true,
		"message": fmt.Sprintf("PicoClaw gateway berhasil dihentikan (PID: %d)", pid),
	}
}

func (m *Manager) getInstalledVersion() string {
	cmd := exec.Command(m.PicoClawBin, "--version")
	out, err := cmd.Output()
	if err != nil {
		return "unknown"
	}
	
	re := regexp.MustCompile(`v?[0-9]+\.[0-9]+\.[0-9]+[^ )*]*`)
	match := re.FindString(string(out))
	if match != "" {
		return strings.TrimPrefix(match, "v")
	}
	return "unknown"
}

func (m *Manager) CheckUpdate() map[string]interface{} {
	installed := m.getInstalledVersion()
	
	resp, err := http.Get(fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", m.Repo))
	if err != nil {
		return map[string]interface{}{
			"installed_version": installed,
			"latest_version":    nil,
			"update_available":  false,
			"error":             err.Error(),
		}
	}
	defer resp.Body.Close()

	var releaseData struct {
		TagName string `json:"tag_name"`
		HtmlUrl string `json:"html_url"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&releaseData); err != nil {
		return map[string]interface{}{
			"installed_version": installed,
			"latest_version":    nil,
			"update_available":  false,
			"error":             err.Error(),
		}
	}

	latest := strings.TrimPrefix(releaseData.TagName, "v")
	updateAvailable := installed != latest && latest != ""

	return map[string]interface{}{
		"installed_version": installed,
		"latest_version":    latest,
		"update_available":  updateAvailable,
		"release_url":       releaseData.HtmlUrl,
	}
}

func (m *Manager) Update() map[string]interface{} {
	// Implementasi update yang simpel.
	wasRunning := m.IsRunning()
	if wasRunning {
		m.Stop()
		time.Sleep(1 * time.Second)
	}

	// Buat sementara ini, update bisa didelegasikan ke script shell atau download langsung.
	// Kita delegate ke install_picoclaw.sh
	scriptURL := fmt.Sprintf("https://raw.githubusercontent.com/%s/main/install_picoclaw.sh", m.Repo)
	cmdStr := fmt.Sprintf("curl -fsSL %s | bash", scriptURL)
	
	cmd := exec.Command("bash", "-c", cmdStr)
	out, err := cmd.CombinedOutput()
	
	success := err == nil
	
	restarted := false
	if wasRunning {
		m.Start()
		restarted = true
	}

	return map[string]interface{}{
		"success": success,
		"message": string(out),
		"updated": success,
		"was_running": wasRunning,
		"restarted": restarted,
	}
}

// ── HTTP API Server ──────────────────────────────────

func startServer(args Config) {
	manager := NewManager(args.PicoclawBin, args.ConfigPath, defaultRepo)

	if args.AutoStart {
		manager.Start()
	}

	mux := http.NewServeMux()
	
	jsonResponse := func(w http.ResponseWriter, code int, data interface{}) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.WriteHeader(code)
		json.NewEncoder(w).Encode(data)
	}

	authMiddleware := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if args.Token != "" {
				authHeader := r.Header.Get("Authorization")
				if authHeader != "Bearer "+args.Token {
					jsonResponse(w, http.StatusUnauthorized, map[string]string{"error": "Unauthorized"})
					return
				}
			}
			next(w, r)
		}
	}

	mux.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, http.StatusOK, map[string]interface{}{
			"status": "ok",
			"service": "picoclaw-manager",
			"timestamp": time.Now().Format(time.RFC3339),
		})
	})

	mux.HandleFunc("/api/picoclaw/status", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, http.StatusOK, manager.Status())
	}))

	mux.HandleFunc("/api/picoclaw/check-update", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, http.StatusOK, manager.CheckUpdate())
	}))

	handlePost := func(handler func() map[string]interface{}) http.HandlerFunc {
		return authMiddleware(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodPost {
				jsonResponse(w, http.StatusMethodNotAllowed, map[string]string{"error": "Method not allowed"})
				return
			}
			result := handler()
			code := http.StatusOK
			if success, ok := result["success"].(bool); ok && !success {
				code = http.StatusInternalServerError
			}
			jsonResponse(w, code, result)
		})
	}

	mux.HandleFunc("/api/picoclaw/start", handlePost(manager.Start))
	mux.HandleFunc("/api/picoclaw/stop", handlePost(manager.Stop))
	mux.HandleFunc("/api/picoclaw/restart", handlePost(manager.Restart))
	mux.HandleFunc("/api/picoclaw/update", handlePost(manager.Update))

	addr := fmt.Sprintf("%s:%d", args.Host, args.Port)
	fmt.Println("\n  ┌─────────────────────────────────────────┐")
	fmt.Println("  │       🦀 PicoClaw Manager (Go)          │")
	fmt.Println("  └─────────────────────────────────────────┘\n")
	fmt.Printf("  Listening   → http://%s\n", addr)
	fmt.Printf("  Binary      → %s\n", args.PicoclawBin)
	fmt.Println("\n  Endpoints:")
	fmt.Println("    GET  /api/health               → Health check")
	fmt.Println("    GET  /api/picoclaw/status       → Status PicoClaw")
	fmt.Println("    POST /api/picoclaw/start        → Start gateway")
	fmt.Println("    POST /api/picoclaw/stop         → Stop gateway")
	fmt.Println("    POST /api/picoclaw/restart      → Restart gateway")
	fmt.Println("    POST /api/picoclaw/update       → Update firmware\n")

	log.Fatal(http.ListenAndServe(addr, mux))
}

// ── CLI Handler ──────────────────────────────────────

func runCLI(cmd string, args Config) {
	if cmd == "version" || cmd == "--version" || cmd == "-v" {
		fmt.Printf("PicoClaw Manager (piman) v%s\n", version)
		return
	}

	urlMap := map[string]string{
		"start":   "/api/picoclaw/start",
		"stop":    "/api/picoclaw/stop",
		"restart": "/api/picoclaw/restart",
		"update":  "/api/picoclaw/update",
		"status":  "/api/picoclaw/status",
		"logs":    "/api/picoclaw/status", // Special handling
	}

	endpoint, ok := urlMap[cmd]
	if !ok {
		fmt.Printf("Error: Perintah tidak dikenali: %s\n", cmd)
		fmt.Println("Commands: start | stop | restart | status | logs | update | version")
		os.Exit(1)
	}

	apiURL := fmt.Sprintf("http://127.0.0.1:%d%s", args.Port, endpoint)
	method := "POST"
	if cmd == "status" || cmd == "logs" {
		method = "GET"
	}

	req, err := http.NewRequest(method, apiURL, nil)
	if err != nil {
		log.Fatalf("Kesalahan membuat request: %v", err)
	}
	if args.Token != "" {
		req.Header.Add("Authorization", "Bearer "+args.Token)
	}

	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("Error menghubungi manager: %v\n", err)
		fmt.Println("Pastikan service picoclaw-manager berjalan (systemctl status picoclaw-manager)")
		os.Exit(1)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	
	if cmd == "logs" {
		var data struct{ RecentLogs []string `json:"recent_logs"` }
		if err := json.Unmarshal(body, &data); err == nil {
			for _, logLine := range data.RecentLogs {
				fmt.Println(logLine)
			}
		}
		return
	}

	// Pretty print
	var prettyJSON bytes.Buffer
	if err := json.Indent(&prettyJSON, body, "", "  "); err == nil {
		fmt.Println(prettyJSON.String())
	} else {
		fmt.Println(string(body))
	}
}

// ── Main ─────────────────────────────────────────────

type Config struct {
	Port        int
	Host        string
	Token       string
	PicoclawBin string
	ConfigPath  string
	AutoStart   bool
}

func main() {
	// Parse subcommand
	if len(os.Args) > 1 {
		cmd := os.Args[1]
		if cmd != "server" && !strings.HasPrefix(cmd, "-") {
			// This is a CLI command
			cfg := Config{
				Port:  defaultPort,
				Token: os.Getenv("PICOCLAW_MANAGER_TOKEN"),
			}
			runCLI(cmd, cfg)
			return
		}
	}

	fs := flag.NewFlagSet("manager", flag.ExitOnError)
	port := fs.Int("port", defaultPort, "Port untuk API server")
	host := fs.String("host", "0.0.0.0", "Bind address")
	token := fs.String("token", os.Getenv("PICOCLAW_MANAGER_TOKEN"), "Bearer token")
	binPath := fs.String("picoclaw-bin", defaultPicoClawBin, "Path ke binary picoclaw")
	configPath := fs.String("config", defaultConfigPath, "Path ke config.json")
	autoStart := fs.Bool("auto-start", false, "Otomatis start PicoClaw gateway saat server dimulai")

	// remove "server" from args if present
	args := os.Args[1:]
	if len(args) > 0 && args[0] == "server" {
		args = args[1:]
	}
	fs.Parse(args)

	cfg := Config{
		Port:        *port,
		Host:        *host,
		Token:       *token,
		PicoclawBin: *binPath,
		ConfigPath:  *configPath,
		AutoStart:   *autoStart,
	}

	startServer(cfg)
}
