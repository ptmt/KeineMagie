package main

import (
	"context"
	"errors"
	"net"
)

// Only fixed codes/messages cross the durable job/API boundary. Never include
// provider bodies, model output, credential values or transport URLs.
type podcastFailure struct {
	Code    string
	Message string
}

func (f *podcastFailure) Error() string { return f.Message + "; saved progress retained" }
func podcastFailureCode(code string) *podcastFailure {
	messages := map[string]string{
		"provider_timeout":        "personal translation timed out",
		"provider_refused":        "personal translation refused",
		"provider_incomplete":     "personal translation incomplete",
		"provider_invalid_output": "personal translation returned invalid segment mapping",
		"provider_rejected":       "personal provider rejected translation",
		"provider_unavailable":    "personal provider unavailable",
		"provider_canceled":       "personal translation canceled",
		"provider_failed":         "personal translation failed",
	}
	message, ok := messages[code]
	if !ok {
		code = "provider_failed"
		message = messages[code]
	}
	return &podcastFailure{Code: code, Message: message}
}
func podcastProviderFailure(err error) *podcastFailure {
	var f *podcastFailure
	if errors.As(err, &f) {
		return f
	}
	var timeout net.Error
	if errors.Is(err, context.DeadlineExceeded) || (errors.As(err, &timeout) && timeout.Timeout()) {
		return podcastFailureCode("provider_timeout")
	}
	if errors.Is(err, context.Canceled) {
		return podcastFailureCode("provider_canceled")
	}
	return podcastFailureCode("provider_failed")
}
