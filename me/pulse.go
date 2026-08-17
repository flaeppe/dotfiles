// me pulse -- background reconciliation of Sam's own state, fed by a launchd timer
// (see me.nix) firing `me pulse` every 15 minutes, same as `me prs sweep`. Zero LLM
// involvement.
//
// Scope is narrower than first sketched: a background timer has nobody live to alert
// mid-tick, so two ideas from that sketch didn't survive -- raw inbox-byte-delta
// reporting and a board-stamp check both only make sense in front of a live session,
// and `me brief` already shows both, in full, the instant one starts. What's left is
// state a live session can't reconstruct on its own just by starting: committing
// before uncommitted data is lost, and noticing an ended or gone-idle session
// regardless of which of the ~30 project directories it ran in.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type pulseState struct {
	// sessionID -> cwd, as of the previous tick's liveSessions(). A session present
	// here but absent from the current tick has ended; diffing two ticks is what lets
	// this reach every project directory cheaply, unlike reconcileMe's transcript
	// glob, which is only affordable because it's scoped to meHome alone.
	LiveLastTick map[string]string `json:"liveLastTick"`
	IdleFlagged  map[string]bool   `json:"idleFlagged"` // sessionID -> already reported idle
	LastRun      time.Time         `json:"lastRun"`
}

func pulseStatePath() string {
	return filepath.Join(meHome, "state", "pulse.json")
}

func loadPulseState() (pulseState, error) {
	state := pulseState{LiveLastTick: map[string]string{}, IdleFlagged: map[string]bool{}}
	content, err := os.ReadFile(pulseStatePath())
	if err != nil {
		if os.IsNotExist(err) {
			return state, nil
		}
		return state, err
	}
	if err := json.Unmarshal(content, &state); err != nil {
		return state, err
	}
	if state.LiveLastTick == nil {
		state.LiveLastTick = map[string]string{}
	}
	if state.IdleFlagged == nil {
		state.IdleFlagged = map[string]bool{}
	}
	return state, nil
}

// savePulseState writes via a temp file and rename, same as savePRState -- the timer
// and `me brief`/`me sessions` are separate processes with no other coordination.
func savePulseState(state pulseState) error {
	dir := filepath.Dir(pulseStatePath())
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	rendered, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	tmp := pulseStatePath() + ".tmp"
	if err := os.WriteFile(tmp, rendered, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, pulseStatePath())
}

// commitIfDirty is the safety net notes.md was missing: a fold that happens between
// ticks with nothing committed in between is still exposed, but the gap shrinks from
// "until the next `me day start`" to "at most 15 minutes," independent of whether a
// live session remembers to commit first.
func commitIfDirty(now time.Time) {
	output, err := exec.Command("git", "-C", meHome, "status", "--porcelain").Output()
	if err != nil || len(strings.TrimSpace(string(output))) == 0 {
		return
	}
	gitCommit("pulse " + now.Format("2006-01-02 15:04"))
}

// backfillEndedSessions generalizes reconcileMe to every project directory, not just
// meHome, by diffing this tick's liveSessions() against the set remembered from the
// previous tick rather than globbing transcripts -- the previous-tick set is exactly
// the sessions worth checking, so there's no directory sweep to pay for.
func backfillEndedSessions(state *pulseState, now time.Time) {
	current := map[string]string{}
	for _, s := range liveSessions() {
		current[s.SessionID] = s.Cwd
	}
	for sessionID, cwd := range state.LiveLastTick {
		if _, stillLive := current[sessionID]; stillLive {
			continue
		}
		endTime := now
		if info, err := os.Stat(transcriptPath(cwd, sessionID)); err == nil {
			endTime = info.ModTime()
		}
		line, prompts := sessionLine(sessionID, cwd, endTime)
		if prompts == 0 {
			continue
		}
		_ = upsertLocked(filepath.Join(inboxDir, "sessions.md"), "id="+sessionID[:8], line)
	}
	state.LiveLastTick = current
}

const idleThreshold = 24 * time.Hour

// flagIdleSessions writes one line per session the first tick it crosses 24h since its
// own last activity (session.UpdatedAt, not StartedAt -- see the IDLE column `me
// sessions` now has). upsertLocked's key-based dedup, keyed the same as every other
// session line here, is what keeps this from repeating every tick: once a session is
// flagged idle it stays flagged until it goes live again, not until it ends.
func flagIdleSessions(state *pulseState, now time.Time) {
	live := liveSessions()
	stillLive := map[string]bool{}
	for _, s := range live {
		stillLive[s.SessionID] = true
		if s.UpdatedAt == 0 || state.IdleFlagged[s.SessionID] {
			continue
		}
		idleFor := now.Sub(time.UnixMilli(s.UpdatedAt))
		if idleFor < idleThreshold {
			continue
		}
		title := lastAiTitle(transcriptPath(s.Cwd, s.SessionID))
		if title == "" {
			title = filepath.Base(s.Cwd)
		}
		line := fmt.Sprintf(
			"- %s [idle] %q dir=%s idle=%s",
			now.Format("2006-01-02 15:04"), title, shortDir(s.Cwd), fmtSpan(int64(idleFor.Seconds())),
		)
		_ = upsertLocked(filepath.Join(inboxDir, "sessions.md"), "idle="+s.SessionID[:8], line)
		state.IdleFlagged[s.SessionID] = true
	}
	for sessionID := range state.IdleFlagged {
		if !stillLive[sessionID] {
			delete(state.IdleFlagged, sessionID)
		}
	}
}

func cmdPulse() int {
	if !requireHome() {
		return 1
	}
	state, err := loadPulseState()
	if err != nil {
		hookError("pulse: load state: " + err.Error())
		return 0
	}
	now := time.Now()
	if !dueOnCadence(state.LastRun, now) {
		return 0
	}
	state.LastRun = now

	commitIfDirty(now)
	backfillEndedSessions(&state, now)
	flagIdleSessions(&state, now)

	if err := savePulseState(state); err != nil {
		hookError("pulse: save state: " + err.Error())
	}
	return 0
}
