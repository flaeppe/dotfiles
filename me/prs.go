// me prs -- mechanical tracking of Petter's own open PRs across anyfin, fed by a
// launchd timer (see me.nix) firing `me prs sweep` every 15 minutes. Zero LLM
// involvement: every verb here is plain deterministic code, safe to run unattended.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

// prSnapshot is the last-known state of one PR, keyed "owner/repo#number" in
// prsState.Snapshots. Title and FirstSeenAt are bookkeeping this tool needs beyond the
// fields GitHub reports directly: Title lets a MERGED line name the PR after it has
// dropped out of the query's result set, and FirstSeenAt anchors the 48h STALE-REVIEW
// threshold without a second API call.
type prSnapshot struct {
	MergeStateStatus string    `json:"mergeStateStatus"`
	ReviewDecision   string    `json:"reviewDecision"`
	CheckState       string    `json:"checkState"`      // commits[0].commit.statusCheckRollup.state
	UnresolvedCount  int       `json:"unresolvedCount"` // reviewThreads where isResolved == false
	Title            string    `json:"title,omitempty"`
	FirstSeenAt      time.Time `json:"firstSeenAt,omitempty"`
	NotifiedAt       time.Time `json:"notifiedAt,omitempty"`
}

type prsState struct {
	Snapshots map[string]prSnapshot `json:"snapshots"`
	LastRun   time.Time             `json:"lastRun"`
}

// prSearchResponse mirrors the shape of the single search()-backed GraphQL query this
// tool makes. That call rides GitHub's 30-requests/minute *search* limit (separate from
// and far tighter than the normal 5000/hour ceiling), so this stays one call per sweep,
// spaced minutes apart by sweepDue -- never a second call per tick, never a wider query.
const prsQuery = `
query($q:String!){ search(query:$q, type:ISSUE, first:30){ nodes{ ... on PullRequest {
  number title isDraft updatedAt mergeStateStatus reviewDecision headRefName baseRefName
  repository{nameWithOwner}
  commits(last:1){nodes{commit{oid statusCheckRollup{state}}}}
  reviewThreads(first:50){nodes{isResolved comments(first:1){nodes{createdAt author{login}}}}}
}}}}`

type prNode struct {
	Number           int    `json:"number"`
	Title            string `json:"title"`
	MergeStateStatus string `json:"mergeStateStatus"`
	ReviewDecision   string `json:"reviewDecision"`
	HeadRefName      string `json:"headRefName"`
	BaseRefName      string `json:"baseRefName"`
	Repository       struct {
		NameWithOwner string `json:"nameWithOwner"`
	} `json:"repository"`
	Commits struct {
		Nodes []struct {
			Commit struct {
				StatusCheckRollup *struct {
					State string `json:"state"`
				} `json:"statusCheckRollup"`
			} `json:"commit"`
		} `json:"nodes"`
	} `json:"commits"`
	ReviewThreads struct {
		Nodes []struct {
			IsResolved bool `json:"isResolved"`
		} `json:"nodes"`
	} `json:"reviewThreads"`
}

func prKey(node prNode) string {
	return node.Repository.NameWithOwner + "#" + strconv.Itoa(node.Number)
}

func checkStateOf(node prNode) string {
	if len(node.Commits.Nodes) == 0 {
		return ""
	}
	rollup := node.Commits.Nodes[0].Commit.StatusCheckRollup
	if rollup == nil {
		return ""
	}
	return rollup.State
}

func unresolvedCountOf(node prNode) int {
	count := 0
	for _, thread := range node.ReviewThreads.Nodes {
		if !thread.IsResolved {
			count++
		}
	}
	return count
}

func fetchOpenPRs() ([]prNode, error) {
	cmd := exec.Command("gh", "api", "graphql",
		"-f", "q=is:pr is:open author:@me org:anyfin",
		"-f", "query="+prsQuery,
	)
	output, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("gh api graphql: %s", strings.TrimSpace(string(exitErr.Stderr)))
		}
		return nil, fmt.Errorf("gh api graphql: %w", err)
	}
	return decodeSearchResponse(output)
}

func decodeSearchResponse(output []byte) ([]prNode, error) {
	var response struct {
		Data struct {
			Search struct {
				Nodes []prNode `json:"nodes"`
			} `json:"search"`
		} `json:"data"`
	}
	if err := json.Unmarshal(output, &response); err != nil {
		return nil, fmt.Errorf("decode gh response: %w", err)
	}
	return response.Data.Search.Nodes, nil
}

func prsStatePath() string {
	return filepath.Join(meHome, "state", "prs.json")
}

func loadPRState() (prsState, error) {
	state := prsState{Snapshots: map[string]prSnapshot{}}
	content, err := os.ReadFile(prsStatePath())
	if err != nil {
		if os.IsNotExist(err) {
			return state, nil
		}
		return state, err
	}
	if err := json.Unmarshal(content, &state); err != nil {
		return state, err
	}
	if state.Snapshots == nil {
		state.Snapshots = map[string]prSnapshot{}
	}
	return state, nil
}

// savePRState writes via a temp file and rename so `me prs` never reads a half-written
// file -- the sweep and the printer are separate processes with no other coordination.
func savePRState(state prsState) error {
	dir := filepath.Dir(prsStatePath())
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	rendered, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	tmp := prsStatePath() + ".tmp"
	if err := os.WriteFile(tmp, rendered, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, prsStatePath())
}

// sweepDue decides whether an unattended tick should actually spend the one search
// request sweep costs, per the shared awake-hours cadence (dueOnCadence, main.go).
// LastRun is the only state this reads, which is what keeps a failed gh call from being
// retried every 15 minutes (main.go still bumps LastRun on error).
func sweepDue(state prsState, now time.Time) bool {
	return dueOnCadence(state.LastRun, now)
}

// pickLabel is the pure, delta-free half of classification: which class a snapshot's own
// fields put it in, ignoring history. unresolvedIncreased and staleEligible are already
// history-aware booleans computed by the caller, folded in here only to keep the
// priority order (RED beats DIRTY beats BEHIND beats MERGEABLE beats REVIEW beats
// STALE-REVIEW) in one place.
func pickLabel(checkState, mergeStateStatus, reviewDecision string, unresolvedIncreased, staleEligible bool) string {
	switch {
	case checkState == "FAILURE" || checkState == "ERROR":
		return "RED"
	case mergeStateStatus == "DIRTY":
		return "DIRTY"
	case mergeStateStatus == "BEHIND":
		return "BEHIND"
	case mergeStateStatus == "CLEAN" && reviewDecision == "APPROVED":
		return "MERGEABLE"
	case unresolvedIncreased:
		return "REVIEW"
	case staleEligible:
		return "STALE-REVIEW"
	default:
		return ""
	}
}

// classifyPR compares curr against prev (the last stored snapshot; prev is the zero
// value when hasPrev is false, which correctly never classifies) and returns the class to
// report, or "" when nothing changed. REVIEW and STALE-REVIEW are event-based -- a fresh
// unresolved thread, or a 24h-gapped stale re-fire -- so once eligible they always report;
// the other four classes only report on an actual transition, computed by re-running
// pickLabel over prev's own fields and comparing labels.
func classifyPR(prev prSnapshot, hasPrev bool, curr prSnapshot, now time.Time) string {
	unresolvedIncreased := hasPrev && curr.UnresolvedCount > prev.UnresolvedCount
	staleEligible := curr.ReviewDecision == "REVIEW_REQUIRED" &&
		curr.UnresolvedCount == 0 &&
		!curr.FirstSeenAt.IsZero() &&
		now.Sub(curr.FirstSeenAt) > 48*time.Hour &&
		(prev.NotifiedAt.IsZero() || now.Sub(prev.NotifiedAt) >= 24*time.Hour)

	currentLabel := pickLabel(curr.CheckState, curr.MergeStateStatus, curr.ReviewDecision, unresolvedIncreased, staleEligible)
	if currentLabel == "" || currentLabel == "REVIEW" || currentLabel == "STALE-REVIEW" {
		return currentLabel
	}
	prevLabel := pickLabel(prev.CheckState, prev.MergeStateStatus, prev.ReviewDecision, false, false)
	if currentLabel == prevLabel {
		return ""
	}
	return currentLabel
}

func repoBaseName(nameWithOwner string) string {
	if index := strings.LastIndex(nameWithOwner, "/"); index >= 0 {
		return nameWithOwner[index+1:]
	}
	return nameWithOwner
}

func prsLine(now time.Time, tag, key, title, detail string) string {
	line := fmt.Sprintf("- %s [prs][%s] %s %q", now.Format("2006-01-02 15:04"), tag, key, title)
	if detail != "" {
		line += " — " + detail
	}
	return line
}

func appendPRLine(line string) {
	if err := appendLocked(filepath.Join(inboxDir, "prs.md"), line); err != nil {
		hookError("prs sweep: " + err.Error())
	}
}

// refreshWorktree does the BEHIND/DIRTY class's real work: refresh (or create) a scratch
// worktree for the PR's branch under its repository's sibling clone, using the fish `wt`
// tooling this machine already has (see ~/.dotfiles/fish/functions/_wt_new.fish -- `wt new
// <name> [<branch>]`, landing in `.worktrees/<name>`), then attempt a rebase onto the PR's
// base. Never pushes anything, ever; a conflicted rebase is aborted and left for a human.
func refreshWorktree(now time.Time, key string, node prNode) {
	repoDir := filepath.Join(filepath.Dir(meHome), repoBaseName(node.Repository.NameWithOwner))
	if info, err := os.Stat(repoDir); err != nil || !info.IsDir() {
		hookError(fmt.Sprintf("prs sweep: no local clone for %s at %s", key, repoDir))
		return
	}
	worktreePath := filepath.Join(repoDir, ".worktrees", node.HeadRefName)
	if _, err := os.Stat(worktreePath); err != nil {
		// $argv rather than string-interpolating the branch into the -c script: a ref name
		// is attacker-shaped input by the time it has come back through a GraphQL response.
		newTree := exec.Command("fish", "-i", "-c", "wt new $argv[1]", node.HeadRefName)
		newTree.Dir = repoDir
		if output, err := newTree.CombinedOutput(); err != nil {
			hookError(fmt.Sprintf("prs sweep: wt new %s: %v: %s", key, err, strings.TrimSpace(string(output))))
			return
		}
	}
	if output, err := exec.Command("git", "-C", worktreePath, "fetch", "origin").CombinedOutput(); err != nil {
		hookError(fmt.Sprintf("prs sweep: fetch %s: %v: %s", key, err, strings.TrimSpace(string(output))))
		return
	}
	if _, err := exec.Command("git", "-C", worktreePath, "rebase", "origin/"+node.BaseRefName).CombinedOutput(); err != nil {
		_ = exec.Command("git", "-C", worktreePath, "rebase", "--abort").Run()
		appendPRLine(prsLine(now, "conflict", key, node.Title, "rebase onto "+node.BaseRefName+" failed, resolve manually"))
		return
	}
	appendPRLine(fmt.Sprintf("- %s [prs] rebased %s onto %s, clean", now.Format("2006-01-02 15:04"), key, node.BaseRefName))
}

const osascriptPath = "/usr/bin/osascript"

// notifyBatch fires exactly one macOS notification per sweep tick for however many
// MERGEABLE/REVIEW/STALE-REVIEW PRs just reported, rather than one per PR, and stamps
// NotifiedAt on each so STALE-REVIEW's 24h re-fire gate has something to read.
func notifyBatch(state *prsState, keys []string, now time.Time) {
	if len(keys) == 0 {
		return
	}
	if _, err := os.Stat(osascriptPath); err == nil {
		message := fmt.Sprintf("%d item(s) need you — see me prs", len(keys))
		script := fmt.Sprintf(`display notification %q with title "Sam"`, message)
		_ = exec.Command(osascriptPath, "-e", script).Run()
	}
	for _, key := range keys {
		snap := state.Snapshots[key]
		snap.NotifiedAt = now
		state.Snapshots[key] = snap
	}
}

// runSweep classifies every PR the query returned against state.Snapshots, does the
// BEHIND/DIRTY worktree work, writes one inbox/prs.md line per reported PR, and detects
// PRs that vanished from the result set since the last sweep (folded into class MERGED --
// distinguishing an actual merge from a close would need a second API call this tool
// deliberately never makes, so MERGED covers both).
func runSweep(state *prsState, nodes []prNode, now time.Time) {
	seen := make(map[string]bool, len(nodes))
	var notifyKeys []string
	for _, node := range nodes {
		key := prKey(node)
		seen[key] = true
		prev, hasPrev := state.Snapshots[key]
		curr := prSnapshot{
			MergeStateStatus: node.MergeStateStatus,
			ReviewDecision:   node.ReviewDecision,
			CheckState:       checkStateOf(node),
			UnresolvedCount:  unresolvedCountOf(node),
			Title:            node.Title,
			FirstSeenAt:      prev.FirstSeenAt,
			NotifiedAt:       prev.NotifiedAt,
		}
		if curr.FirstSeenAt.IsZero() {
			curr.FirstSeenAt = now
		}
		label := classifyPR(prev, hasPrev, curr, now)
		state.Snapshots[key] = curr

		switch label {
		case "":
			continue
		case "DIRTY", "BEHIND":
			refreshWorktree(now, key, node)
		case "RED":
			appendPRLine(prsLine(now, "red", key, node.Title, "check failed"))
		case "MERGEABLE":
			appendPRLine(prsLine(now, "mergeable", key, node.Title, ""))
			notifyKeys = append(notifyKeys, key)
		case "REVIEW":
			appendPRLine(prsLine(now, "review", key, node.Title, "new unresolved thread"))
			notifyKeys = append(notifyKeys, key)
		case "STALE-REVIEW":
			ageDays := int(now.Sub(curr.FirstSeenAt).Hours() / 24)
			appendPRLine(prsLine(now, "stale-review", key, node.Title, fmt.Sprintf("REVIEW_REQUIRED, zero reviews, %dd", ageDays)))
			notifyKeys = append(notifyKeys, key)
		}
	}

	for key, snap := range state.Snapshots {
		if seen[key] {
			continue
		}
		appendPRLine(prsLine(now, "merged", key, snap.Title, ""))
		delete(state.Snapshots, key)
	}

	notifyBatch(state, notifyKeys, now)
}

func cmdPRsSweep() int {
	if !requireHome() {
		return 1
	}
	state, err := loadPRState()
	if err != nil {
		hookError("prs sweep: load state: " + err.Error())
		return 0
	}
	now := time.Now()
	if !sweepDue(state, now) {
		return 0
	}
	state.LastRun = now // bumped even on failure below, so a broken `gh` isn't retried every 15m.

	nodes, err := fetchOpenPRs()
	if err != nil {
		hookError("prs sweep: " + err.Error())
		_ = savePRState(state)
		return 0
	}
	runSweep(&state, nodes, now)
	if err := savePRState(state); err != nil {
		hookError("prs sweep: save state: " + err.Error())
	}
	return 0
}

// snapshotState renders one stored snapshot back to a class label for `me prs`, the same
// priority order runSweep uses, but without the event-based REVIEW/STALE-REVIEW bumps --
// those describe a transition, not a resting state, so a plain read falls back to the raw
// review decision.
func snapshotState(snap prSnapshot) string {
	if label := pickLabel(snap.CheckState, snap.MergeStateStatus, snap.ReviewDecision, false, false); label != "" {
		return label
	}
	if snap.ReviewDecision != "" {
		return snap.ReviewDecision
	}
	return snap.MergeStateStatus
}

func cmdPRsPrint() int {
	if !requireHome() {
		return 1
	}
	state, err := loadPRState()
	if err != nil {
		fmt.Fprintf(os.Stderr, "me: %v\n", err)
		return 1
	}
	if len(state.Snapshots) == 0 {
		fmt.Println("no tracked PRs yet (run `me prs sweep`, or wait for the timer)")
		return 0
	}
	keys := make([]string, 0, len(state.Snapshots))
	for key := range state.Snapshots {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	table := [][3]string{{"PR", "STATE", "TITLE"}}
	for _, key := range keys {
		snap := state.Snapshots[key]
		table = append(table, [3]string{key, snapshotState(snap), snap.Title})
	}
	var widths [3]int
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
	if !state.LastRun.IsZero() {
		fmt.Println()
		fmt.Printf("last sweep: %s\n", state.LastRun.Format("2006-01-02 15:04"))
	}
	return 0
}

func cmdPRs(rest []string) int {
	if len(rest) == 1 && rest[0] == "sweep" {
		return cmdPRsSweep()
	}
	if len(rest) > 0 {
		fmt.Fprintln(os.Stderr, "usage: me prs [sweep]")
		return 2
	}
	return cmdPRsPrint()
}
