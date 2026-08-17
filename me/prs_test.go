package main

import (
	"testing"
	"time"
)

func atHour(hour, minute int) time.Time {
	return time.Date(2026, 8, 17, hour, minute, 0, 0, time.Local)
}

func TestSweepDue(t *testing.T) {
	cases := []struct {
		name    string
		now     time.Time
		lastRun time.Time
		want    bool
	}{
		{"before window", atHour(6, 59), time.Time{}, false},
		{"at window open, never run", atHour(7, 0), time.Time{}, true},
		{"after window close", atHour(21, 0), atHour(20, 0), false},
		{"just inside close", atHour(20, 59), atHour(20, 0), false}, // <60m since last run in loose window
		{"tight window, just under 15m", atHour(10, 10), atHour(10, 0), false},
		{"tight window, exactly 15m", atHour(10, 15), atHour(10, 0), true},
		{"loose window boundary at 17:00, under 60m", atHour(17, 0), atHour(16, 30), false},
		{"loose window at 17:00, tight interval would have fired", atHour(17, 10), atHour(17, 0), false},
		{"loose window, exactly 60m", atHour(18, 0), atHour(17, 0), true},
		{"loose window, just under 60m", atHour(19, 59), atHour(19, 0), false},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			state := prsState{LastRun: testCase.lastRun}
			if got := sweepDue(state, testCase.now); got != testCase.want {
				t.Errorf("sweepDue(lastRun=%s, now=%s) = %v, want %v",
					testCase.lastRun, testCase.now, got, testCase.want)
			}
		})
	}
}

func TestClassifyPRFirstSeen(t *testing.T) {
	now := time.Now()
	// A brand-new PR, never stored before, sitting DIRTY: reported once on first sight.
	curr := prSnapshot{MergeStateStatus: "DIRTY", ReviewDecision: "REVIEW_REQUIRED", FirstSeenAt: now}
	if got := classifyPR(prSnapshot{}, false, curr, now); got != "DIRTY" {
		t.Errorf("first-seen DIRTY: got %q, want DIRTY", got)
	}

	// A brand-new, unremarkable PR: nothing to report.
	quiet := prSnapshot{MergeStateStatus: "CLEAN", ReviewDecision: "REVIEW_REQUIRED", FirstSeenAt: now}
	if got := classifyPR(prSnapshot{}, false, quiet, now); got != "" {
		t.Errorf("first-seen quiet PR: got %q, want \"\"", got)
	}
}

func TestClassifyPRNoChangeIsSilent(t *testing.T) {
	now := time.Now()
	snap := prSnapshot{MergeStateStatus: "DIRTY", ReviewDecision: "REVIEW_REQUIRED", FirstSeenAt: now.Add(-time.Hour)}
	// Same fields as last time: already reported once, must not fire again.
	if got := classifyPR(snap, true, snap, now); got != "" {
		t.Errorf("unchanged DIRTY: got %q, want \"\"", got)
	}
}

func TestClassifyPRTransitions(t *testing.T) {
	now := time.Now()
	prev := prSnapshot{MergeStateStatus: "BEHIND", ReviewDecision: "REVIEW_REQUIRED"}

	clean := prSnapshot{MergeStateStatus: "CLEAN", ReviewDecision: "APPROVED"}
	if got := classifyPR(prev, true, clean, now); got != "MERGEABLE" {
		t.Errorf("BEHIND -> CLEAN+APPROVED: got %q, want MERGEABLE", got)
	}

	red := prSnapshot{MergeStateStatus: "BEHIND", ReviewDecision: "REVIEW_REQUIRED", CheckState: "FAILURE"}
	if got := classifyPR(prev, true, red, now); got != "RED" {
		t.Errorf("BEHIND -> failing check: got %q, want RED (RED outranks BEHIND)", got)
	}
}

func TestClassifyPRReviewOnUnresolvedIncrease(t *testing.T) {
	now := time.Now()
	prev := prSnapshot{MergeStateStatus: "CLEAN", ReviewDecision: "REVIEW_REQUIRED", UnresolvedCount: 1}
	curr := prSnapshot{MergeStateStatus: "CLEAN", ReviewDecision: "REVIEW_REQUIRED", UnresolvedCount: 2}
	if got := classifyPR(prev, true, curr, now); got != "REVIEW" {
		t.Errorf("unresolved count increased: got %q, want REVIEW", got)
	}

	// A thread getting resolved (count decreasing) is not a REVIEW event.
	resolved := prSnapshot{MergeStateStatus: "CLEAN", ReviewDecision: "REVIEW_REQUIRED", UnresolvedCount: 0}
	if got := classifyPR(curr, true, resolved, now); got != "" {
		t.Errorf("unresolved count decreased: got %q, want \"\"", got)
	}
}

func TestClassifyPRStaleReview(t *testing.T) {
	now := time.Now()
	firstSeen := now.Add(-49 * time.Hour)
	prev := prSnapshot{MergeStateStatus: "CLEAN", ReviewDecision: "REVIEW_REQUIRED", UnresolvedCount: 0, FirstSeenAt: firstSeen}
	curr := prev

	if got := classifyPR(prev, true, curr, now); got != "STALE-REVIEW" {
		t.Errorf("48h+ zero engagement: got %q, want STALE-REVIEW", got)
	}

	// Not yet 48h: quiet.
	tooYoung := prSnapshot{MergeStateStatus: "CLEAN", ReviewDecision: "REVIEW_REQUIRED", UnresolvedCount: 0, FirstSeenAt: now.Add(-40 * time.Hour)}
	if got := classifyPR(tooYoung, true, tooYoung, now); got != "" {
		t.Errorf("under 48h: got %q, want \"\"", got)
	}

	// Notified less than 24h ago: must not re-fire yet.
	recentlyNotified := prev
	recentlyNotified.NotifiedAt = now.Add(-1 * time.Hour)
	if got := classifyPR(recentlyNotified, true, curr, now); got != "" {
		t.Errorf("notified <24h ago: got %q, want \"\" (gated)", got)
	}

	// Notified over 24h ago: eligible to re-fire.
	staleNotified := prev
	staleNotified.NotifiedAt = now.Add(-25 * time.Hour)
	if got := classifyPR(staleNotified, true, curr, now); got != "STALE-REVIEW" {
		t.Errorf("notified >24h ago: got %q, want STALE-REVIEW re-fire", got)
	}
}
