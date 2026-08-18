package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"

	logging "google.golang.org/api/logging/v2"
)

func cmdLogs(rest []string) int {
	fs := flag.NewFlagSet("glog logs", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	project := fs.String("project", "", "GCP project (default: gcloud config, or $CLOUDSDK_CORE_PROJECT)")
	limit := fs.Int("limit", 200, "maximum log names to return")
	positional, err := parseFlagsAnywhere(fs, rest)
	if err != nil {
		return 2
	}
	if len(positional) != 0 {
		fmt.Fprintln(os.Stderr, "usage: glog logs [--project P] [--limit N]")
		return 2
	}

	projectID, svc, err := projectAndService(*project)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog logs: %v\n", err)
		return 1
	}

	printed := 0
	err = svc.Projects.Logs.List("projects/"+projectID).Pages(context.Background(), func(resp *logging.ListLogsResponse) error {
		for _, name := range resp.LogNames {
			if printed >= *limit {
				return errLimitReached
			}
			fmt.Println(name)
			printed++
		}
		if printed >= *limit {
			return errLimitReached
		}
		return nil
	})
	if err != nil && err != errLimitReached {
		fmt.Fprintf(os.Stderr, "glog logs: %v\n", err)
		return 1
	}
	return 0
}

func cmdBuckets(rest []string) int {
	if len(rest) == 0 {
		fmt.Fprintln(os.Stderr, "usage: glog buckets list|describe <name> [--project P] [--location L]")
		return 2
	}
	verb, rest := rest[0], rest[1:]
	fs := flag.NewFlagSet("glog buckets "+verb, flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	project := fs.String("project", "", "GCP project (default: gcloud config, or $CLOUDSDK_CORE_PROJECT)")
	defaultLocation := "global"
	if verb == "list" {
		defaultLocation = "-"
	}
	location := fs.String("location", defaultLocation, "bucket location, or - for all (list only)")
	positional, err := parseFlagsAnywhere(fs, rest)
	if err != nil {
		return 2
	}

	projectID, svc, err := projectAndService(*project)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog buckets: %v\n", err)
		return 1
	}

	switch verb {
	case "list":
		return printJSONPages(func(f func(*logging.ListBucketsResponse) error) error {
			parent := "projects/" + projectID + "/locations/" + *location
			return svc.Projects.Locations.Buckets.List(parent).Pages(context.Background(), f)
		}, func(resp *logging.ListBucketsResponse) []interface{} {
			items := make([]interface{}, len(resp.Buckets))
			for i, b := range resp.Buckets {
				items[i] = b
			}
			return items
		})
	case "describe":
		if len(positional) != 1 {
			fmt.Fprintln(os.Stderr, "usage: glog buckets describe <name> [--project P] [--location L]")
			return 2
		}
		prefix := "projects/" + projectID + "/locations/" + *location + "/buckets/"
		bucket, err := svc.Projects.Locations.Buckets.Get(qualify(positional[0], prefix)).Do()
		if err != nil {
			fmt.Fprintf(os.Stderr, "glog buckets describe: %v\n", err)
			return 1
		}
		return printJSON(bucket)
	default:
		fmt.Fprintf(os.Stderr, "glog buckets: unknown verb %q (want list or describe)\n", verb)
		return 2
	}
}

func cmdViews(rest []string) int {
	if len(rest) == 0 {
		fmt.Fprintln(os.Stderr, "usage: glog views list|describe <name> --bucket B [--project P] [--location L]")
		return 2
	}
	verb, rest := rest[0], rest[1:]
	fs := flag.NewFlagSet("glog views "+verb, flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	project := fs.String("project", "", "GCP project (default: gcloud config, or $CLOUDSDK_CORE_PROJECT)")
	location := fs.String("location", "global", "bucket location")
	bucket := fs.String("bucket", "", "bucket the view(s) belong to (required)")
	positional, err := parseFlagsAnywhere(fs, rest)
	if err != nil {
		return 2
	}
	if *bucket == "" {
		fmt.Fprintln(os.Stderr, "glog views: --bucket is required (a view always belongs to one bucket)")
		return 2
	}

	projectID, svc, err := projectAndService(*project)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog views: %v\n", err)
		return 1
	}
	bucketName := "projects/" + projectID + "/locations/" + *location + "/buckets/" + *bucket

	switch verb {
	case "list":
		return printJSONPages(func(f func(*logging.ListViewsResponse) error) error {
			return svc.Projects.Locations.Buckets.Views.List(bucketName).Pages(context.Background(), f)
		}, func(resp *logging.ListViewsResponse) []interface{} {
			items := make([]interface{}, len(resp.Views))
			for i, v := range resp.Views {
				items[i] = v
			}
			return items
		})
	case "describe":
		if len(positional) != 1 {
			fmt.Fprintln(os.Stderr, "usage: glog views describe <name> --bucket B [--project P] [--location L]")
			return 2
		}
		view, err := svc.Projects.Locations.Buckets.Views.Get(qualify(positional[0], bucketName+"/views/")).Do()
		if err != nil {
			fmt.Fprintf(os.Stderr, "glog views describe: %v\n", err)
			return 1
		}
		return printJSON(view)
	default:
		fmt.Fprintf(os.Stderr, "glog views: unknown verb %q (want list or describe)\n", verb)
		return 2
	}
}

func cmdSinks(rest []string) int {
	if len(rest) == 0 {
		fmt.Fprintln(os.Stderr, "usage: glog sinks list|describe <name> [--project P]")
		return 2
	}
	verb, rest := rest[0], rest[1:]
	fs := flag.NewFlagSet("glog sinks "+verb, flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	project := fs.String("project", "", "GCP project (default: gcloud config, or $CLOUDSDK_CORE_PROJECT)")
	positional, err := parseFlagsAnywhere(fs, rest)
	if err != nil {
		return 2
	}

	projectID, svc, err := projectAndService(*project)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog sinks: %v\n", err)
		return 1
	}

	switch verb {
	case "list":
		return printJSONPages(func(f func(*logging.ListSinksResponse) error) error {
			return svc.Projects.Sinks.List("projects/"+projectID).Pages(context.Background(), f)
		}, func(resp *logging.ListSinksResponse) []interface{} {
			items := make([]interface{}, len(resp.Sinks))
			for i, s := range resp.Sinks {
				items[i] = s
			}
			return items
		})
	case "describe":
		if len(positional) != 1 {
			fmt.Fprintln(os.Stderr, "usage: glog sinks describe <name> [--project P]")
			return 2
		}
		prefix := "projects/" + projectID + "/sinks/"
		sink, err := svc.Projects.Sinks.Get(qualify(positional[0], prefix)).Do()
		if err != nil {
			fmt.Fprintf(os.Stderr, "glog sinks describe: %v\n", err)
			return 1
		}
		return printJSON(sink)
	default:
		fmt.Fprintf(os.Stderr, "glog sinks: unknown verb %q (want list or describe)\n", verb)
		return 2
	}
}

func cmdMetrics(rest []string) int {
	if len(rest) == 0 {
		fmt.Fprintln(os.Stderr, "usage: glog metrics list|describe <name> [--project P]")
		return 2
	}
	verb, rest := rest[0], rest[1:]
	fs := flag.NewFlagSet("glog metrics "+verb, flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	project := fs.String("project", "", "GCP project (default: gcloud config, or $CLOUDSDK_CORE_PROJECT)")
	positional, err := parseFlagsAnywhere(fs, rest)
	if err != nil {
		return 2
	}

	projectID, svc, err := projectAndService(*project)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog metrics: %v\n", err)
		return 1
	}

	switch verb {
	case "list":
		return printJSONPages(func(f func(*logging.ListLogMetricsResponse) error) error {
			return svc.Projects.Metrics.List("projects/"+projectID).Pages(context.Background(), f)
		}, func(resp *logging.ListLogMetricsResponse) []interface{} {
			items := make([]interface{}, len(resp.Metrics))
			for i, m := range resp.Metrics {
				items[i] = m
			}
			return items
		})
	case "describe":
		if len(positional) != 1 {
			fmt.Fprintln(os.Stderr, "usage: glog metrics describe <name> [--project P]")
			return 2
		}
		prefix := "projects/" + projectID + "/metrics/"
		metric, err := svc.Projects.Metrics.Get(qualify(positional[0], prefix)).Do()
		if err != nil {
			fmt.Fprintf(os.Stderr, "glog metrics describe: %v\n", err)
			return 1
		}
		return printJSON(metric)
	default:
		fmt.Fprintf(os.Stderr, "glog metrics: unknown verb %q (want list or describe)\n", verb)
		return 2
	}
}

func projectAndService(projectFlag string) (string, *logging.Service, error) {
	projectID, err := resolveProject(projectFlag)
	if err != nil {
		return "", nil, err
	}
	svc, _, err := newLoggingService(context.Background())
	if err != nil {
		return "", nil, err
	}
	return projectID, svc, nil
}

func printJSON(v interface{}) int {
	data, err := json.Marshal(v)
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog: %v\n", err)
		return 1
	}
	fmt.Println(string(data))
	return 0
}

// printJSONPages drains a paged list call, printing one JSON line per item
// across every page, in the same jsonl shape `glog read --format json` uses.
func printJSONPages[Response any](pages func(func(Response) error) error, items func(Response) []interface{}) int {
	err := pages(func(resp Response) error {
		for _, item := range items(resp) {
			data, err := json.Marshal(item)
			if err != nil {
				return err
			}
			fmt.Println(string(data))
		}
		return nil
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "glog: %v\n", err)
		return 1
	}
	return 0
}
