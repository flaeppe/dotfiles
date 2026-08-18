package main

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	logging "google.golang.org/api/logging/v2"
	"google.golang.org/api/option"
)

// authSource names which credential path a service was built from, purely
// for the caller to report to the user -- it plays no role in the request.
type authSource string

const (
	authADC         authSource = "application-default-credentials"
	authGcloudToken authSource = "gcloud auth print-access-token"
)

// newLoggingService builds a Cloud Logging client from whichever credential
// source resolved -- see newClientOptions for the order.
func newLoggingService(ctx context.Context) (*logging.Service, authSource, error) {
	opts, source, err := newClientOptions(ctx)
	if err != nil {
		return nil, "", err
	}
	svc, err := logging.NewService(ctx, opts...)
	if err != nil {
		return nil, "", fmt.Errorf("building Cloud Logging client: %w", err)
	}
	return svc, source, nil
}

// newClientOptions resolves credentials in order: Application Default
// Credentials first, then a token source that shells out to `gcloud auth
// print-access-token`, piggybacking whatever login the user already has.
// Every request this binary ever makes is a read, so the ADC lookup is
// scoped to logging.read; a service account or JWT-based ADC will honor
// that restriction even though a user credential's own grant can't be
// narrowed after the fact.
func newClientOptions(ctx context.Context) ([]option.ClientOption, authSource, error) {
	const readScope = "https://www.googleapis.com/auth/logging.read"
	if creds, err := google.FindDefaultCredentials(ctx, readScope); err == nil {
		return []option.ClientOption{option.WithCredentials(creds)}, authADC, nil
	}

	if _, err := exec.LookPath("gcloud"); err != nil {
		return nil, "", fmt.Errorf("no Application Default Credentials and no `gcloud` on PATH: run `gcloud auth application-default login`")
	}
	if _, err := gcloudAccessToken(); err != nil {
		return nil, "", fmt.Errorf("no Application Default Credentials, and %w", err)
	}
	return []option.ClientOption{option.WithTokenSource(gcloudTokenSource{})}, authGcloudToken, nil
}

// gcloudTokenSource re-execs `gcloud auth print-access-token` on every call.
// Callers wrap it in oauth2.ReuseTokenSource (google.golang.org/api's
// transport does this internally), so within one process it shells out at
// most once per token lifetime, not once per request.
type gcloudTokenSource struct{}

func (gcloudTokenSource) Token() (*oauth2.Token, error) {
	accessToken, err := gcloudAccessToken()
	if err != nil {
		return nil, err
	}
	return &oauth2.Token{
		AccessToken: accessToken,
		TokenType:   "Bearer",
		// gcloud-issued access tokens are short-lived (~1h); expiring this
		// early forces a refresh well before the real token does, never after.
		Expiry: time.Now().Add(45 * time.Minute),
	}, nil
}

func gcloudAccessToken() (string, error) {
	out, err := exec.Command("gcloud", "auth", "print-access-token").CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("`gcloud auth print-access-token` failed: %s (run `gcloud auth login` to fix)", strings.TrimSpace(string(out)))
	}
	token := strings.TrimSpace(string(out))
	if token == "" {
		return "", fmt.Errorf("`gcloud auth print-access-token` returned no token (run `gcloud auth login` to fix)")
	}
	return token, nil
}
