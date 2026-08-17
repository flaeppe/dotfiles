// me -- the mechanical layer of Sam, the personal optimizer.
//
// Zero-token bookkeeping over ME_HOME (Sam's state repository, a git repo)
// and the local Claude Code state directory. Sam's reasoning happens in a
// Claude session opened inside ME_HOME; these verbs only feed and read that
// state.
//
// Reads of ~/.claude (sessions/, history.jsonl, transcript files) are
// undocumented formats observed on Claude Code 2.1.x. Every reader degrades
// to a coarser fallback instead of failing, and hook failures land in
// inbox/hook-errors.log rather than in front of the user.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"syscall"
	"time"
)

// Overridden at build time (-ldflags -X) with the host's multi-repo root.
var defaultMeHome = "~/anyfin/.me"

var (
	homeDir   string
	meHome    string
	claudeDir string
	boardPath string
	inboxDir  string
)

var stampRe = regexp.MustCompile(`^# Board — (\d{4}-\d{2}-\d{2})$`)

const kittyApp = "Applications/Home Manager Apps/kitty.app/Contents/MacOS/kitty"

func helpText() string {
	return strings.Join([]string{
		"me — the mechanical layer of Sam: positions, never thinks",
		"",
		"usage: me <command> [args]",
		"",
		"commands:",
		"  init          create ME_HOME (idempotent): git repo + seed files",
		"  brief         board + inbox + live sessions, one screen",
		"  board         print BOARD.md        (me board edit | me board path)",
		"  note <text>   timestamped line into inbox/notes.md",
		"  sessions      live Claude sessions: title, status, age, dir",
		"  inbox         untriaged inbox lines",
		"  prs           tracked PRs: repo#number, state, title",
		"  prs sweep     mechanical PR sweep (gh + worktree rebase); meant for the launchd timer",
		"  pulse         reconcile ended/idle sessions, commit if dirty; meant for the launchd timer",
		"  day start     roll the board to today (idempotent), commit, print brief",
		"  sam           find the live Sam session or open his kitty window",
		"  hook <event>  Claude Code hook plumbing (session-end); always exits 0",
		"",
		"ME_HOME defaults to " + defaultMeHome + "; override with $ME_HOME.",
	}, "\n")
}

func boardSeed(today string) string {
	return strings.Join([]string{
		"# Board — " + today,
		"",
		"## Focus",
		"<the current big-ticket focus — outranks everything below>",
		"",
		"## Today",
		"",
		"## Waiting",
		"",
		"## System",
		"- [ ] Sam heartbeat: adopt /loop self-pacing in the Sam window? judge by volume",
		"- [ ] PR prep pipeline: `review <pr>` + analyse via `fish -c`, hand a jump-in",
		"- [ ] Slack PR-link scanner feeding the inbox (no slack CLI; MCP-only today)",
		"- [ ] Per-repo .me/ prep notes for targeted sessions (.me/ globally ignored)",
		"- [ ] `me session why <id>`: cheap-agent deep-dive on a session gone sideways",
		"- [ ] Plan/kb verbs for `me` (a plan-status script already exists)",
		"- [ ] Location from connected wifi; workday auto start/end",
		"- [ ] Sam pings outward (notification / statusline) instead of being hunted",
		"- [ ] Fold in prior attempts (the private notes sketch, dev-state/nvim-dojo)",
		"- [ ] Dojo cadence: surface when keystroke-review last ran (review.json date)",
		"",
		"## Yesterday",
		"",
	}, "\n")
}

func meSeed() string {
	return strings.Join([]string{
		"# ME — operating manual",
		"",
		"## Facts (fill in; these stay true)",
		"- <who I am / role>",
		"- <commute / connectivity constraints>",
		"- <working hours pattern>",
		"- The Focus in BOARD.md is where work expects time to go. It outranks",
		"  everything Sam generates.",
		"- A dozen parallel Claude sessions is normal. Sessions opened outside Sam's",
		"  orchestration are observed and folded in, never fought.",
		"",
		"## What Sam is",
		"- Sam positions; he never does the engineering thinking. He preps structure,",
		"  tracks sessions, and says what's next.",
		"- Propose → sign-off. Sam preps ideas and puts them on the board; nothing",
		"  outward-facing happens unprompted.",
		"- Transparent mechanics: every automation Sam relies on is named on the board.",
		"",
		"## Token ladder",
		"1. Mechanical first: `me` verbs, grep, file reads — zero tokens.",
		"2. Cheap agent second, only to summarize something already on disk. Agents",
		"   Sam spawns run model haiku unless they must judge priorities.",
		"3. Sam's own reasoning last, and only for triage, priority, sequencing.",
		"- Catch-up and deep-dives read session titles, plan frontmatter, and ask —",
		"  never whole transcripts.",
		"",
		"## Board rules",
		"- BOARD.md ≤ 100 lines, ME.md ≤ 60, System ≤ 10 items. Delete freely; git",
		"  history is the archive.",
		"- Sam is the curator. Humans may edit, but while a Sam session is live,",
		"  changes go through `me note`.",
		"",
		"## Triage (top of every Sam session)",
		"1. The SessionStart brief is the context: board + inbox + live sessions.",
		"2. Fold each inbox line into Today/Waiting/System or delete it as noise.",
		"   Folding = deleting the inbox line (git keeps it). Inbox trends to empty.",
		"3. Propose the next action for the user; never queue work for Sam.",
		"",
		"## Iteration",
		"- Every observed pain becomes one System line, the same day, no essay.",
		"",
	}, "\n")
}

const claudeSeed = `You are Sam. Read ME.md, then BOARD.md. Follow the triage procedure in ME.md
before anything else.
`

func kittySeed() string {
	return strings.Join([]string{
		"# kitty session for Sam, the optimizer",
		"os_window_name sam",
		"focus_os_window",
		"",
		"new_tab sam",
		"layout fat",
		"launch --cwd " + meHome + " fish -i -c claude",
		"focus",
		"",
	}, "\n")
}

func settingsSeed() string {
	briefHook := map[string]string{"type": "command", "command": "~/.local/bin/me brief"}
	sessionStart := make([]map[string]any, 0, 3)
	for _, source := range []string{"startup", "resume", "clear"} {
		sessionStart = append(sessionStart, map[string]any{
			"matcher": source,
			"hooks":   []map[string]string{briefHook},
		})
	}
	seed := map[string]any{
		// Sam triages and sequences; he never needs the flagship model. Agents
		// he spawns for mechanical summaries go one rung lower still (haiku).
		"model": "claude-sonnet-5",
		"permissions": map[string]any{
			"defaultMode": "acceptEdits",
			"allow":       []string{"Bash(me *)"},
		},
		"hooks": map[string]any{"SessionStart": sessionStart},
	}
	rendered, err := json.MarshalIndent(seed, "", "  ")
	if err != nil {
		return "{}\n"
	}
	return string(rendered) + "\n"
}

type session struct {
	SessionID  string `json:"sessionId"`
	Cwd        string `json:"cwd"`
	Name       string `json:"name"`
	Status     string `json:"status"`
	WaitingFor string `json:"waitingFor"`
	Pid        int    `json:"pid"`
	StartedAt  int64  `json:"startedAt"`
	UpdatedAt  int64  `json:"updatedAt"`
}

func expandHome(path string) string {
	if path == "~" || strings.HasPrefix(path, "~/") {
		return filepath.Join(homeDir, strings.TrimPrefix(strings.TrimPrefix(path, "~"), "/"))
	}
	return path
}

func pidAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || err == syscall.EPERM
}

func slug(cwd string) string {
	return regexp.MustCompile(`[^A-Za-z0-9]`).ReplaceAllString(cwd, "-")
}

func transcriptPath(cwd, sessionID string) string {
	return filepath.Join(claudeDir, "projects", slug(cwd), sessionID+".jsonl")
}

// Tail read only: titles repeat every turn, so the last 256 KiB nearly always
// holds one; a miss falls back to the derived session name.
func lastAiTitle(transcript string) string {
	handle, err := os.Open(transcript)
	if err != nil {
		return ""
	}
	defer handle.Close()
	info, err := handle.Stat()
	if err != nil {
		return ""
	}
	offset := info.Size() - 256*1024
	if offset < 0 {
		offset = 0
	}
	if _, err := handle.Seek(offset, io.SeekStart); err != nil {
		return ""
	}
	tail, err := io.ReadAll(handle)
	if err != nil {
		return ""
	}
	lines := strings.Split(string(tail), "\n")
	for index := len(lines) - 1; index >= 0; index-- {
		if !strings.Contains(lines[index], `"ai-title"`) {
			continue
		}
		var record struct {
			AiTitle string `json:"aiTitle"`
		}
		if json.Unmarshal([]byte(lines[index]), &record) == nil && record.AiTitle != "" {
			return record.AiTitle
		}
	}
	return ""
}

func shortDir(cwd string) string {
	for _, root := range []string{filepath.Dir(meHome), homeDir} {
		rel, err := filepath.Rel(root, cwd)
		if err == nil && !strings.HasPrefix(rel, "..") {
			return rel
		}
	}
	return cwd
}

func fmtSpan(seconds int64) string {
	if seconds < 0 {
		seconds = 0
	}
	minutes := seconds / 60
	if minutes < 1 {
		return "<1m"
	}
	hours, minutes := minutes/60, minutes%60
	if hours == 0 {
		return fmt.Sprintf("%dm", minutes)
	}
	if hours < 24 {
		return fmt.Sprintf("%dh%02dm", hours, minutes)
	}
	return fmt.Sprintf("%dd%dh", hours/24, hours%24)
}

func appendLocked(path, line string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	handle, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer handle.Close()
	if err := syscall.Flock(int(handle.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	_, err = handle.WriteString(line + "\n")
	return err
}

// Read-modify-write under flock: two sessions can end in the same instant.
func upsertLocked(path, key, line string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	handle, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return err
	}
	defer handle.Close()
	if err := syscall.Flock(int(handle.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	content, err := io.ReadAll(handle)
	if err != nil {
		return err
	}
	lines := strings.Split(strings.TrimRight(string(content), "\n"), "\n")
	if len(lines) == 1 && lines[0] == "" {
		lines = nil
	}
	replaced := false
	for index, existing := range lines {
		if strings.Contains(existing, key) {
			lines[index] = line
			replaced = true
			break
		}
	}
	if !replaced {
		lines = append(lines, line)
	}
	if _, err := handle.Seek(0, io.SeekStart); err != nil {
		return err
	}
	if err := handle.Truncate(0); err != nil {
		return err
	}
	_, err = handle.WriteString(strings.Join(lines, "\n") + "\n")
	return err
}

func requireHome() bool {
	info, err := os.Stat(meHome)
	if err == nil && info.IsDir() {
		return true
	}
	fmt.Fprintf(os.Stderr, "me: %s missing — run `me init`\n", meHome)
	return false
}

// Bookkeeping commits skip GPG: both machines sign by default, and a locked
// agent would wedge the morning roll on a pinentry prompt.
func gitCommit(message string) {
	add := exec.Command("git", "-C", meHome, "add", "-A")
	_ = add.Run()
	commit := exec.Command(
		"git", "-C", meHome, "-c", "commit.gpgsign=false",
		"commit", "-q", "-m", message,
	)
	_ = commit.Run()
}

func liveSessions() []session {
	entries, err := os.ReadDir(filepath.Join(claudeDir, "sessions"))
	if err != nil {
		return nil
	}
	sessions := make([]session, 0, len(entries))
	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		// Per-file parse: the directory holds stale and half-written records.
		content, err := os.ReadFile(filepath.Join(claudeDir, "sessions", entry.Name()))
		if err != nil {
			continue
		}
		var record session
		if json.Unmarshal(content, &record) != nil {
			continue
		}
		if !pidAlive(record.Pid) {
			continue
		}
		sessions = append(sessions, record)
	}
	return sessions
}

// historyFor returns prompt count, first-prompt epoch ms, and first prompt
// text for a session, from the flat prompt index Claude Code maintains.
func historyFor(sessionID string) (int, int64, string) {
	content, err := os.ReadFile(filepath.Join(claudeDir, "history.jsonl"))
	if err != nil {
		return 0, 0, ""
	}
	prompts := 0
	var firstMs int64
	firstDisplay := ""
	for _, raw := range strings.Split(string(content), "\n") {
		if !strings.Contains(raw, sessionID) {
			continue
		}
		prompts++
		if firstMs != 0 {
			continue
		}
		var record struct {
			Display   string `json:"display"`
			Timestamp int64  `json:"timestamp"`
		}
		if json.Unmarshal([]byte(raw), &record) != nil {
			continue
		}
		firstMs = record.Timestamp
		firstDisplay = strings.Join(strings.Fields(record.Display), " ")
	}
	return prompts, firstMs, firstDisplay
}

// transcriptPrompts is historyFor's fallback: it scans the transcript itself
// for typed human turns instead of the prompt index. SDK-invoked sessions
// (promptSource "sdk") carry no interactive-input-box entry in history.jsonl
// at all, which historyFor reads as "no human prompt" -- true for those, but
// also the shape of a session whose interactive turns simply never made it
// into that index. Only "typed" turns count as one of Sam's own.
func transcriptPrompts(transcript string) (int, int64, string) {
	content, err := os.ReadFile(transcript)
	if err != nil {
		return 0, 0, ""
	}
	prompts := 0
	var firstMs int64
	firstDisplay := ""
	for _, raw := range strings.Split(string(content), "\n") {
		if !strings.Contains(raw, `"promptSource":"typed"`) {
			continue
		}
		var record struct {
			Type    string `json:"type"`
			Message struct {
				Content json.RawMessage `json:"content"`
			} `json:"message"`
			Timestamp string `json:"timestamp"`
		}
		if json.Unmarshal([]byte(raw), &record) != nil || record.Type != "user" {
			continue
		}
		prompts++
		if firstMs != 0 {
			continue
		}
		parsed, err := time.Parse(time.RFC3339, record.Timestamp)
		if err != nil {
			continue
		}
		firstMs = parsed.UnixMilli()
		var text string
		if json.Unmarshal(record.Message.Content, &text) == nil {
			firstDisplay = strings.Join(strings.Fields(text), " ")
		}
	}
	return prompts, firstMs, firstDisplay
}

func cmdInit() int {
	for _, dir := range []string{meHome, inboxDir, filepath.Join(meHome, ".claude")} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			fmt.Fprintf(os.Stderr, "me: %v\n", err)
			return 1
		}
	}
	today := time.Now().Format("2006-01-02")
	seeds := map[string]string{
		boardPath:                                         boardSeed(today),
		filepath.Join(meHome, "ME.md"):                    meSeed(),
		filepath.Join(meHome, "CLAUDE.md"):                claudeSeed,
		filepath.Join(meHome, ".claude", "settings.json"): settingsSeed(),
		filepath.Join(meHome, "sam.kitty-session"):        kittySeed(),
	}
	for path, content := range seeds {
		if _, err := os.Stat(path); err == nil {
			continue
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "me: %v\n", err)
			return 1
		}
	}
	if info, err := os.Stat(filepath.Join(meHome, ".git")); err != nil || !info.IsDir() {
		_ = exec.Command("git", "init", "-q", meHome).Run()
	}
	gitCommit("sam: init")
	fmt.Printf("ME_HOME ready at %s\n", meHome)
	return 0
}

func cmdBoard(rest []string) int {
	if !requireHome() {
		return 1
	}
	if len(rest) == 1 && rest[0] == "path" {
		fmt.Println(boardPath)
		return 0
	}
	if len(rest) == 1 && rest[0] == "edit" {
		editor := os.Getenv("EDITOR")
		if editor == "" {
			editor = "nvim"
		}
		edit := exec.Command(editor, boardPath)
		edit.Stdin, edit.Stdout, edit.Stderr = os.Stdin, os.Stdout, os.Stderr
		if err := edit.Run(); err != nil {
			return 1
		}
		return 0
	}
	if len(rest) > 0 {
		fmt.Fprintln(os.Stderr, "usage: me board [edit|path]")
		return 2
	}
	content, err := os.ReadFile(boardPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "me: %v\n", err)
		return 1
	}
	fmt.Println(strings.TrimRight(string(content), "\n"))
	return 0
}

func cmdNote(words []string) int {
	if len(words) == 0 {
		fmt.Fprintln(os.Stderr, "usage: me note <text>")
		return 2
	}
	if !requireHome() {
		return 1
	}
	now := time.Now().Format("2006-01-02 15:04")
	line := fmt.Sprintf("- %s %s", now, strings.Join(words, " "))
	if err := appendLocked(filepath.Join(inboxDir, "notes.md"), line); err != nil {
		fmt.Fprintf(os.Stderr, "me: %v\n", err)
		return 1
	}
	return 0
}

func cmdSessions() int {
	sessions := liveSessions()
	if len(sessions) == 0 {
		fmt.Println("no live sessions")
		return 0
	}
	sort.Slice(sessions, func(a, b int) bool {
		return sessions[a].UpdatedAt > sessions[b].UpdatedAt
	})
	nowMs := time.Now().UnixMilli()
	// STARTED and IDLE read different things: a session running 5 hours but typed in
	// 2 minutes ago is fresh, not stale -- IDLE (from UpdatedAt) is the number that
	// answers that, and used to not exist here at all.
	table := [][5]string{{"SESSION", "STATUS", "STARTED", "IDLE", "DIR"}}
	for _, live := range sessions {
		title := lastAiTitle(transcriptPath(live.Cwd, live.SessionID))
		if title == "" {
			title = live.Name
		}
		if title == "" {
			title = filepath.Base(live.Cwd)
		}
		if len([]rune(title)) > 44 {
			title = string([]rune(title)[:44])
		}
		status := live.Status
		if live.WaitingFor != "" {
			status += " (" + live.WaitingFor + ")"
		}
		started := "?"
		if live.StartedAt != 0 {
			started = fmtSpan((nowMs - live.StartedAt) / 1000)
		}
		idle := "?"
		if live.UpdatedAt != 0 {
			idle = fmtSpan((nowMs - live.UpdatedAt) / 1000)
		}
		table = append(table, [5]string{title, status, started, idle, shortDir(live.Cwd)})
	}
	var widths [5]int
	for _, row := range table {
		for column, cell := range row {
			if len([]rune(cell)) > widths[column] {
				widths[column] = len([]rune(cell))
			}
		}
	}
	for _, row := range table {
		var cells []string
		for column, cell := range row {
			padded := cell + strings.Repeat(" ", widths[column]-len([]rune(cell)))
			cells = append(cells, padded)
		}
		fmt.Println(strings.TrimRight(strings.Join(cells, "  "), " "))
	}
	return 0
}

func cmdInbox() int {
	if !requireHome() {
		return 1
	}
	empty := true
	for _, name := range []string{"notes.md", "sessions.md", "prs.md", "hook-errors.log"} {
		content, err := os.ReadFile(filepath.Join(inboxDir, name))
		if err != nil {
			continue
		}
		trimmed := strings.TrimSpace(string(content))
		if trimmed == "" {
			continue
		}
		empty = false
		fmt.Println("── inbox/" + name)
		fmt.Println(trimmed)
	}
	if empty {
		fmt.Println("inbox empty")
	}
	return 0
}

func cmdBrief() int {
	if !requireHome() {
		return 1
	}
	func() {
		defer func() {
			if recovered := recover(); recovered != nil {
				hookError(fmt.Sprintf("brief: reconcile panic: %v", recovered))
			}
		}()
		reconcileMe()
	}()
	content, err := os.ReadFile(boardPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "me: %v\n", err)
		return 1
	}
	fmt.Println(strings.TrimRight(string(content), "\n"))
	fmt.Println()
	cmdInbox()
	fmt.Println()
	fmt.Println("── live sessions")
	cmdSessions()
	return 0
}

// roll advances the board one day: checked Today items move to Yesterday as
// plain lines, unchecked ones stay marked (carried), the stamp becomes today.
// Other sections pass through.
func roll(lines []string, today string) []string {
	type section struct {
		name string
		body []string
	}
	sections := []section{{name: ""}}
	for _, line := range lines[1:] {
		if strings.HasPrefix(line, "## ") {
			sections = append(sections, section{name: strings.TrimPrefix(line, "## ")})
			continue
		}
		sections[len(sections)-1].body = append(sections[len(sections)-1].body, line)
	}

	var checked []string
	for _, current := range sections {
		if current.name != "Today" {
			continue
		}
		for _, line := range current.body {
			if strings.HasPrefix(line, "- [x]") {
				checked = append(checked, line)
			}
		}
	}

	out := []string{"# Board — " + today}
	for _, current := range sections {
		if current.name == "" {
			continue
		}
		var items []string
		for _, line := range current.body {
			if strings.TrimSpace(line) != "" {
				items = append(items, line)
			}
		}
		switch current.name {
		case "Today":
			var remaining []string
			for _, line := range items {
				if strings.HasPrefix(line, "- [x]") {
					continue
				}
				if strings.HasPrefix(line, "- [ ]") && !strings.HasSuffix(line, "(carried)") {
					line += " (carried)"
				}
				remaining = append(remaining, line)
			}
			items = remaining
		case "Yesterday":
			items = nil
			for _, line := range checked {
				items = append(items, "- "+strings.TrimPrefix(line, "- [x] "))
			}
		}
		out = append(out, "", "## "+current.name)
		out = append(out, items...)
	}
	return out
}

func cmdDay(rest []string) int {
	if len(rest) != 1 || rest[0] != "start" {
		fmt.Fprintln(os.Stderr, "usage: me day start")
		return 2
	}
	if !requireHome() {
		return 1
	}
	content, err := os.ReadFile(boardPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "me: %v\n", err)
		return 1
	}
	lines := strings.Split(strings.TrimRight(string(content), "\n"), "\n")
	match := stampRe.FindStringSubmatch(lines[0])
	if match == nil {
		fmt.Fprintln(os.Stderr, "me: BOARD.md must start with '# Board — YYYY-MM-DD'")
		return 1
	}
	today := time.Now().Format("2006-01-02")
	if match[1] == today {
		return cmdBrief()
	}
	gitCommit("eod " + match[1])
	rolled := strings.Join(roll(lines, today), "\n") + "\n"
	if err := os.WriteFile(boardPath, []byte(rolled), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "me: %v\n", err)
		return 1
	}
	gitCommit("day " + today)
	return cmdBrief()
}

func cmdSam() int {
	if !requireHome() {
		return 1
	}
	for _, live := range liveSessions() {
		if live.Cwd != meHome {
			continue
		}
		status := live.Status
		if live.WaitingFor != "" {
			status += " (" + live.WaitingFor + ")"
		}
		fmt.Printf("Sam is alive: %s [%s] — window 'sam'\n", live.Name, status)
		return 0
	}
	sessionFile := filepath.Join(meHome, "sam.kitty-session")
	kitty := filepath.Join(homeDir, kittyApp)
	_, kittyErr := os.Stat(kitty)
	_, fileErr := os.Stat(sessionFile)
	if kittyErr == nil && fileErr == nil {
		open := exec.Command("open", "-a", kitty, "-n", "--args", "--session", sessionFile)
		if open.Run() == nil {
			fmt.Println("Sam window opening.")
			return 0
		}
	}
	fmt.Printf("start Sam manually: cd %s && claude\n", meHome)
	return 0
}

func hookError(message string) {
	now := time.Now().Format("2006-01-02 15:04")
	_ = appendLocked(filepath.Join(inboxDir, "hook-errors.log"), "- "+now+" "+message)
}

// sessionLine renders one sessions.md entry for a session that has ended, or
// ("", 0) if it never carried a real prompt (subagent, -p, or an SDK-invoked
// probe -- see transcriptPrompts). historyFor is tried first since it also
// carries prompts made before the session's own transcript existed; its
// fallback covers the sessions it misses entirely.
func sessionLine(sessionID, cwd string, endTime time.Time) (string, int) {
	transcript := transcriptPath(cwd, sessionID)
	prompts, firstMs, firstDisplay := historyFor(sessionID)
	if prompts == 0 {
		prompts, firstMs, firstDisplay = transcriptPrompts(transcript)
	}
	if prompts == 0 {
		return "", 0
	}
	tags := "[end]"
	if cwd == meHome {
		tags += "[me]"
	}
	if strings.Contains(cwd, "/.worktrees/") {
		tags += "[review]"
	}
	title := lastAiTitle(transcript)
	if title == "" {
		title = firstDisplay
		if len([]rune(title)) > 60 {
			title = string([]rune(title)[:60])
		}
	}
	if title == "" && cwd != "" {
		title = filepath.Base(cwd)
	}
	span := "?"
	if firstMs != 0 {
		span = fmtSpan(endTime.Unix() - firstMs/1000)
	}
	line := fmt.Sprintf(
		"- %s %s %q dir=%s span=%s prompts=%d id=%s",
		endTime.Format("2006-01-02 15:04"), tags, title,
		shortDir(cwd), span, prompts, sessionID[:8],
	)
	return line, prompts
}

func hookSessionEnd() error {
	var payload map[string]any
	if err := json.NewDecoder(os.Stdin).Decode(&payload); err != nil {
		return err
	}
	asString := func(key string) string {
		value, _ := payload[key].(string)
		return value
	}
	sessionID := asString("session_id")
	if sessionID == "" {
		sessionID = asString("sessionId")
	}
	cwd := asString("cwd")
	// Real ids are 36-char UUIDs; anything shorter would panic the id slice
	// and make the substring scan over history.jsonl match everything.
	if len(sessionID) < 8 {
		return nil
	}
	if info, err := os.Stat(meHome); err != nil || !info.IsDir() {
		return nil
	}
	if strings.HasPrefix(cwd, "/private/tmp/claude") || strings.HasPrefix(cwd, claudeDir) {
		return nil
	}
	line, prompts := sessionLine(sessionID, cwd, time.Now())
	if prompts == 0 {
		return nil
	}
	return upsertLocked(filepath.Join(inboxDir, "sessions.md"), "id="+sessionID[:8], line)
}

// reconcileMe backfills any Sam session (cwd == meHome) whose SessionEnd hook
// never landed a line -- upstream, Ctrl-C can cancel the hook before it runs
// (anthropics/claude-code#32712), and SessionEnd has no documented reason for
// that exit path at all. Runs from `me brief` instead, which fires on every
// SessionStart, using each transcript file as the durable record rather than
// a one-shot event.
func reconcileMe() {
	live := map[string]bool{}
	for _, s := range liveSessions() {
		live[s.SessionID] = true
	}
	matches, err := filepath.Glob(filepath.Join(claudeDir, "projects", slug(meHome), "*.jsonl"))
	if err != nil {
		return
	}
	for _, transcript := range matches {
		sessionID := strings.TrimSuffix(filepath.Base(transcript), ".jsonl")
		if len(sessionID) < 8 || live[sessionID] {
			continue
		}
		info, err := os.Stat(transcript)
		if err != nil {
			continue
		}
		line, prompts := sessionLine(sessionID, meHome, info.ModTime())
		if prompts == 0 {
			continue
		}
		_ = upsertLocked(filepath.Join(inboxDir, "sessions.md"), "id="+sessionID[:8], line)
	}
}

// dueOnCadence answers a background timer's own throttling question: given when it
// last actually did real work, should this tick? Awake hours are 07:00-21:00;
// 07:00-17:00 tracks the timer's own firing interval (so effectively every tick),
// 17:00-21:00 loosens to hourly, and outside that window it's always no. Shared by
// every launchd-fed verb (prs sweep, pulse) so the hours policy lives in one place.
func dueOnCadence(lastRun, now time.Time) bool {
	hour := now.Hour()
	switch {
	case hour < 7 || hour >= 21:
		return false
	case hour < 17:
		return now.Sub(lastRun) >= 15*time.Minute
	default:
		return now.Sub(lastRun) >= 60*time.Minute
	}
}

// Hook plumbing must never wedge a session: every path exits 0, and failures
// surface in inbox/hook-errors.log for Sam's triage instead.
func cmdHook(rest []string) int {
	if len(rest) != 1 || rest[0] != "session-end" {
		return 0
	}
	defer func() {
		if recovered := recover(); recovered != nil {
			hookError(fmt.Sprintf("session-end: panic: %v", recovered))
		}
	}()
	if err := hookSessionEnd(); err != nil {
		hookError("session-end: " + err.Error())
	}
	return 0
}

func run(argv []string) int {
	if len(argv) == 0 || argv[0] == "help" || argv[0] == "-h" || argv[0] == "--help" {
		fmt.Println(helpText())
		return 0
	}
	command, rest := argv[0], argv[1:]
	switch command {
	case "init":
		return cmdInit()
	case "brief":
		return cmdBrief()
	case "board":
		return cmdBoard(rest)
	case "note":
		return cmdNote(rest)
	case "sessions":
		return cmdSessions()
	case "inbox":
		return cmdInbox()
	case "prs":
		return cmdPRs(rest)
	case "pulse":
		return cmdPulse()
	case "day":
		return cmdDay(rest)
	case "sam":
		return cmdSam()
	case "hook":
		return cmdHook(rest)
	}
	fmt.Fprintln(os.Stderr, helpText())
	return 2
}

func main() {
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "me: %v\n", err)
		os.Exit(1)
	}
	homeDir = home
	meHome = os.Getenv("ME_HOME")
	if meHome == "" {
		meHome = defaultMeHome
	}
	meHome = expandHome(meHome)
	claudeDir = filepath.Join(homeDir, ".claude")
	boardPath = filepath.Join(meHome, "BOARD.md")
	inboxDir = filepath.Join(meHome, "inbox")
	os.Exit(run(os.Args[1:]))
}
