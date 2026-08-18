// me friction -- cross-session repetition detector. Claude Code transcripts on disk
// already hold every command a session ran; no single session can see that it
// hand-rolled the same procedure a live session two weeks ago also hand-rolled, but a
// mechanical scan across all of them can. Zero LLM involvement: this only counts and
// writes, the judgment of what's worth scripting stays with Sam's triage.
package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	frictionWindow      = 14 * 24 * time.Hour
	frictionMaxSignals  = 15
	frictionCmdMinSess  = 3 // (a): a single command shape, distinct sessions
	frictionSeqMinSess  = 2 // (b): an n-gram sequence, distinct sessions
	frictionSeqMinLen   = 2
	frictionSeqMaxLen   = 4
)

var (
	// Order matters: quotes and URLs first so their contents don't leak into the path
	// and number passes below; numbers last so path segments already absorbed theirs.
	frictionQuotedRe = regexp.MustCompile(`"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'`)
	frictionURLRe    = regexp.MustCompile(`\w+://\S+`)
	frictionHexRe    = regexp.MustCompile(`\b[0-9a-fA-F]{7,}\b`)
	frictionPathRe   = regexp.MustCompile(`[A-Za-z0-9_.\-~/@%+:]*/[A-Za-z0-9_.\-~/@%+:]*`)
	frictionNumRe    = regexp.MustCompile(`\b\d+(?:ms|min|sec|[smhd])?\b`)
	frictionSpaceRe  = regexp.MustCompile(`\s+`)
)

// normalizeBashCommand maps a raw command to a stable shape: absolute paths, hashes/
// UUIDs, numbers, and quoted strings become placeholders; program names, subcommands,
// flags, and pipeline structure (|, &&, ;, redirects) survive untouched. Same input
// always yields the same signature, and different sessions running the "same"
// procedure with different arguments collapse onto it.
func normalizeBashCommand(command string) string {
	normalized := frictionQuotedRe.ReplaceAllString(strings.TrimSpace(command), "<STR>")
	normalized = frictionURLRe.ReplaceAllString(normalized, "<URL>")
	normalized = frictionHexRe.ReplaceAllStringFunc(normalized, func(match string) string {
		if strings.ContainsAny(match, "abcdefABCDEF") {
			return "<ID>"
		}
		return match // pure digits: let the number pass below handle it
	})
	normalized = frictionPathRe.ReplaceAllString(normalized, "<PATH>")
	normalized = frictionNumRe.ReplaceAllString(normalized, "<NUM>")
	normalized = frictionSpaceRe.ReplaceAllString(normalized, " ")
	return strings.TrimSpace(normalized)
}

// frictionCompoundRe matches anything beyond a single simple invocation -- a pipe,
// chain, or real redirect -- which disqualifies a command from the stoplist below even
// if its head matches: "git status" is noise, "git status | grep X" is a procedure.
var frictionCompoundRe = regexp.MustCompile(`\||&&|\|\||;`)

var frictionStoplistRe = []*regexp.Regexp{
	regexp.MustCompile(`^git (status|diff|log|show|add|commit)\b`),
	regexp.MustCompile(`^ls\b`),
	regexp.MustCompile(`^cd\b`),
	regexp.MustCompile(`^cat\b`),
	regexp.MustCompile(`^echo\b`),
	regexp.MustCompile(`^pwd$`),
	regexp.MustCompile(`^which\b`),
	regexp.MustCompile(`^(grep|rg)\b`),
	regexp.MustCompile(`^mkdir\b`),
	regexp.MustCompile(`^chmod\b`),
	regexp.MustCompile(`^wc\b`),
	regexp.MustCompile(`^true$`),
}

// isStoplistedCommand reports whether a normalized single command is too trivial to
// surface on its own (spec (a)). It can still appear inside an n-gram sequence (b) --
// stoplisting only blocks it from being counted as a signature by itself.
func isStoplistedCommand(normalized string) bool {
	if frictionCompoundRe.MatchString(normalized) {
		return false
	}
	for _, stoplisted := range frictionStoplistRe {
		if stoplisted.MatchString(normalized) {
			return true
		}
	}
	return false
}

// parseAssistantBashCalls extracts every Bash tool_use command from one transcript
// line, in content order, plus the turn's timestamp. Non-assistant lines, lines whose
// content isn't the expected array, and malformed JSON all degrade to (nil, zero) --
// this is an undocumented format observed on disk, never a contract to enforce.
func parseAssistantBashCalls(line []byte) ([]string, time.Time) {
	var record struct {
		Type      string `json:"type"`
		Timestamp string `json:"timestamp"`
		Message   struct {
			Content json.RawMessage `json:"content"`
		} `json:"message"`
	}
	if json.Unmarshal(line, &record) != nil || record.Type != "assistant" {
		return nil, time.Time{}
	}
	var items []json.RawMessage
	if json.Unmarshal(record.Message.Content, &items) != nil {
		return nil, time.Time{}
	}
	timestamp, _ := time.Parse(time.RFC3339Nano, record.Timestamp)
	var commands []string
	for _, raw := range items {
		var item struct {
			Type  string `json:"type"`
			Name  string `json:"name"`
			Input struct {
				Command string `json:"command"`
			} `json:"input"`
		}
		if json.Unmarshal(raw, &item) != nil {
			continue
		}
		if item.Type == "tool_use" && item.Name == "Bash" && item.Input.Command != "" {
			commands = append(commands, normalizeBashCommand(item.Input.Command))
		}
	}
	return commands, timestamp
}

// sessionBashCalls reads one transcript and returns its normalized Bash commands in
// turn order (parallel calls within a turn keep their content-array order), plus the
// latest in-transcript timestamp seen. Reads line-by-line via bufio.Reader rather than
// bufio.Scanner: transcript lines carrying large tool output can exceed Scanner's
// default token limit, and ReadString has none.
func sessionBashCalls(transcript string) ([]string, time.Time) {
	file, err := os.Open(transcript)
	if err != nil {
		return nil, time.Time{}
	}
	defer file.Close()

	reader := bufio.NewReaderSize(file, 64*1024)
	var calls []string
	var lastSeen time.Time
	for {
		line, readErr := reader.ReadBytes('\n')
		if len(line) > 0 {
			commands, timestamp := parseAssistantBashCalls(line)
			calls = append(calls, commands...)
			if timestamp.After(lastSeen) {
				lastSeen = timestamp
			}
		}
		if readErr != nil {
			break
		}
	}
	return calls, lastSeen
}

// frictionAccumulator tallies one signature (a normalized command, or a normalized
// n-gram sequence) across every session scanned.
type frictionAccumulator struct {
	sessions    map[string]bool
	occurrences int
	lastSeen    time.Time
}

func (acc *frictionAccumulator) record(transcript string, seenAt time.Time) {
	acc.sessions[transcript] = true
	acc.occurrences++
	if seenAt.After(acc.lastSeen) {
		acc.lastSeen = seenAt
	}
}

type frictionSignature struct {
	hash         string
	display      string
	sessionCount int
	occurrences  int
	lastSeen     time.Time
}

func newFrictionAccumulator() *frictionAccumulator {
	return &frictionAccumulator{sessions: map[string]bool{}}
}

func toFrictionSignature(display string, acc *frictionAccumulator) frictionSignature {
	sum := sha256.Sum256([]byte(display))
	return frictionSignature{
		hash:         hex.EncodeToString(sum[:])[:8],
		display:      display,
		sessionCount: len(acc.sessions),
		occurrences:  acc.occurrences,
		lastSeen:     acc.lastSeen,
	}
}

// scanFriction is a full rescan every call: at today's transcript volume (roughly a
// hundred files, well under 200MB across the 14-day window) this stays a low-single-
// -digit-seconds walk. If that volume grows enough to matter, switch to an mtime-keyed
// state file under ~/.local/state/me/ that skips transcripts already folded into the
// last scan, rather than reprocessing everything on every pulse tick.
func scanFriction(now time.Time) []frictionSignature {
	transcripts, _ := filepath.Glob(filepath.Join(claudeDir, "projects", "*", "*.jsonl"))

	singleCommands := map[string]*frictionAccumulator{}
	sequences := map[string]*frictionAccumulator{}

	for _, transcript := range transcripts {
		info, err := os.Stat(transcript)
		if err != nil || now.Sub(info.ModTime()) > frictionWindow {
			continue
		}
		calls, lastSeen := sessionBashCalls(transcript)
		if len(calls) == 0 {
			continue
		}
		if lastSeen.IsZero() {
			lastSeen = info.ModTime()
		}

		for _, normalized := range calls {
			if isStoplistedCommand(normalized) {
				continue
			}
			acc, ok := singleCommands[normalized]
			if !ok {
				acc = newFrictionAccumulator()
				singleCommands[normalized] = acc
			}
			acc.record(transcript, lastSeen)
		}

		for length := frictionSeqMinLen; length <= frictionSeqMaxLen; length++ {
			for start := 0; start+length <= len(calls); start++ {
				signature := strings.Join(calls[start:start+length], " -> ")
				acc, ok := sequences[signature]
				if !ok {
					acc = newFrictionAccumulator()
					sequences[signature] = acc
				}
				acc.record(transcript, lastSeen)
			}
		}
	}

	var signatures []frictionSignature
	for display, acc := range singleCommands {
		if len(acc.sessions) < frictionCmdMinSess {
			continue
		}
		signatures = append(signatures, toFrictionSignature(display, acc))
	}
	for display, acc := range sequences {
		if len(acc.sessions) < frictionSeqMinSess {
			continue
		}
		signatures = append(signatures, toFrictionSignature(display, acc))
	}

	sort.Slice(signatures, func(i, j int) bool {
		if signatures[i].sessionCount != signatures[j].sessionCount {
			return signatures[i].sessionCount > signatures[j].sessionCount
		}
		if signatures[i].occurrences != signatures[j].occurrences {
			return signatures[i].occurrences > signatures[j].occurrences
		}
		return signatures[i].display < signatures[j].display // stable order for equal weight
	})
	if len(signatures) > frictionMaxSignals {
		signatures = signatures[:frictionMaxSignals]
	}
	return signatures
}

func frictionLine(sig frictionSignature) string {
	return fmt.Sprintf(
		"- [friction] %s seen=%dx across %d sessions (last %s): %s",
		sig.hash, sig.occurrences, sig.sessionCount, sig.lastSeen.Format("2006-01-02"), sig.display,
	)
}

// writeFrictionFile replaces friction.md's full contents rather than merging line by
// line like upsertLocked: this is a full recompute every run, so the top-N set must be
// able to shrink as signatures age out, not just grow -- append-only upsert can't
// express a signature dropping out of the top 15.
func writeFrictionFile(signatures []frictionSignature) error {
	lines := make([]string, len(signatures))
	for index, sig := range signatures {
		lines[index] = frictionLine(sig)
	}
	return replaceLocked(filepath.Join(inboxDir, "friction.md"), lines)
}

func cmdFriction() int {
	if !requireHome() {
		return 1
	}
	signatures := scanFriction(time.Now())
	if err := writeFrictionFile(signatures); err != nil {
		fmt.Fprintf(os.Stderr, "me: %v\n", err)
		return 1
	}
	fmt.Printf("friction: %d signatures written to %s\n", len(signatures), filepath.Join(inboxDir, "friction.md"))
	return 0
}

// scanFrictionSafely is the pulse-facing entry point: never lets a scan bug (a bad
// transcript shape, a regex panic) take the launchd tick down with it.
func scanFrictionSafely(now time.Time) {
	defer func() {
		if recovered := recover(); recovered != nil {
			hookError(fmt.Sprintf("friction: panic: %v", recovered))
		}
	}()
	if err := writeFrictionFile(scanFriction(now)); err != nil {
		hookError("friction: " + err.Error())
	}
}
