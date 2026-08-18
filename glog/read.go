package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	logging "google.golang.org/api/logging/v2"
)

// errLimitReached stops Pages() once enough entries have been printed --
// ListLogEntries doesn't accept a total-result cap, only a page size, and a
// page can come back short of a full page while more remain.
var errLimitReached = errors.New("glog: limit reached")

func cmdRead(rest []string) int {
	fs := flag.NewFlagSet("glog read", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	project := fs.String("project", "", "GCP project (default: gcloud config, or $CLOUDSDK_CORE_PROJECT)")
	limit := fs.Int("limit", 50, "maximum entries to return")
	freshness := fs.String("freshness", "", "only entries newer than this, e.g. 1h, 30m, 2d")
	order := fs.String("order", "desc", "sort order: asc or desc")
	format := fs.String("format", "text", "output format: text or json")
	positional, err := parseFlagsAnywhere(fs, rest)
	if err != nil {
		return 2
	}
	filter := strings.Join(positional, " ")

	if *format != "text" && *format != "json" {
		fmt.Fprintf(os.Stderr, "glog read: invalid --format %q: use text or json\n", *format)
		return 2
	}
	if *limit <= 0 {
		fmt.Fprintf(os.Stderr, "glog read: --limit must be positive\n")
		return 2
	}
	orderBy, err := orderByClause(*order)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog read: %v\n", err)
		return 2
	}
	fullFilter, err := buildFilter(filter, *freshness)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog read: %v\n", err)
		return 2
	}
	projectID, err := resolveProject(*project)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog read: %v\n", err)
		return 1
	}

	ctx := context.Background()
	svc, _, err := newLoggingService(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog read: %v\n", err)
		return 1
	}

	pageSize := int64(*limit)
	if pageSize > 1000 {
		pageSize = 1000
	}
	req := &logging.ListLogEntriesRequest{
		ResourceNames: []string{"projects/" + projectID},
		Filter:        fullFilter,
		OrderBy:       orderBy,
		PageSize:      pageSize,
	}

	printed := 0
	err = svc.Entries.List(req).Pages(ctx, func(resp *logging.ListLogEntriesResponse) error {
		for _, entry := range resp.Entries {
			if printed >= *limit {
				return errLimitReached
			}
			printEntry(entry, *format)
			printed++
		}
		if printed >= *limit {
			return errLimitReached
		}
		return nil
	})
	if err != nil && !errors.Is(err, errLimitReached) {
		fmt.Fprintf(os.Stderr, "glog read: %v\n", err)
		return 1
	}
	return 0
}

func orderByClause(order string) (string, error) {
	switch order {
	case "desc", "":
		return "timestamp desc", nil
	case "asc":
		return "timestamp asc", nil
	default:
		return "", fmt.Errorf("invalid --order %q: use asc or desc", order)
	}
}

// buildFilter combines a user-supplied logging-query-language filter with a
// timestamp lower bound derived from --freshness. Either half may be absent.
func buildFilter(userFilter, freshness string) (string, error) {
	var parts []string
	if userFilter != "" {
		parts = append(parts, "("+userFilter+")")
	}
	if freshness != "" {
		age, err := parseFreshness(freshness)
		if err != nil {
			return "", err
		}
		since := time.Now().Add(-age).UTC().Format(time.RFC3339)
		parts = append(parts, fmt.Sprintf(`timestamp>="%s"`, since))
	}
	return strings.Join(parts, " AND "), nil
}

// parseFreshness accepts anything time.ParseDuration does, plus a day
// suffix ("2d") that the standard library has no unit for.
func parseFreshness(s string) (time.Duration, error) {
	if d, err := time.ParseDuration(s); err == nil {
		return d, nil
	}
	if days, ok := strings.CutSuffix(s, "d"); ok {
		if n, err := strconv.Atoi(days); err == nil && n >= 0 {
			return time.Duration(n) * 24 * time.Hour, nil
		}
	}
	return 0, fmt.Errorf("invalid --freshness %q: use a duration like 1h, 30m, or 2d", s)
}

func printEntry(entry *logging.LogEntry, format string) {
	if format == "json" {
		data, err := json.Marshal(entry)
		if err != nil {
			fmt.Fprintf(os.Stderr, "glog read: %v\n", err)
			return
		}
		fmt.Println(string(data))
		return
	}
	fmt.Println(textLine(entry))
}

func textLine(entry *logging.LogEntry) string {
	timestamp := entry.Timestamp
	if timestamp == "" {
		timestamp = entry.ReceiveTimestamp
	}
	severity := entry.Severity
	if severity == "" {
		severity = "DEFAULT"
	}
	return fmt.Sprintf("%s [%s] %s %s", timestamp, severity, resourceLabel(entry.Resource), entryMessage(entry))
}

// resourceLabel picks out whichever label on the monitored resource most
// specifically identifies the thing that logged, falling back to the bare
// resource type when none of the common ones are present.
func resourceLabel(resource *logging.MonitoredResource) string {
	if resource == nil {
		return "-"
	}
	for _, key := range []string{"pod_name", "container_name", "service_name", "function_name", "instance_id"} {
		if value := resource.Labels[key]; value != "" {
			return resource.Type + "/" + value
		}
	}
	return resource.Type
}

func entryMessage(entry *logging.LogEntry) string {
	switch {
	case entry.TextPayload != "":
		return oneLine(entry.TextPayload)
	case len(entry.JsonPayload) > 0:
		return oneLine(string(entry.JsonPayload))
	case len(entry.ProtoPayload) > 0:
		return "<proto payload>"
	default:
		return ""
	}
}

func oneLine(s string) string {
	return strings.Join(strings.Fields(s), " ")
}
