package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gofiber/fiber/v2"
)

func TestJSONErrorHandler(t *testing.T) {
	app := fiber.New(fiber.Config{ErrorHandler: jsonErrorHandler})
	app.Get("/boom", func(c *fiber.Ctx) error {
		return fiber.NewError(fiber.StatusUnauthorized, "token has expired")
	})

	resp, err := app.Test(httptest.NewRequest(http.MethodGet, "/boom", nil))
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Errorf("content-type = %q, want application/json", ct)
	}
	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("response body is not JSON: %v", err)
	}
	if body["error"] != "token has expired" {
		t.Errorf(`body["error"] = %q, want "token has expired"`, body["error"])
	}
}

// An unmatched route should also come back as JSON now, not Fiber's
// default plain-text "Cannot GET /nope".
func TestJSONErrorHandlerCoversUnmatchedRoutes(t *testing.T) {
	app := fiber.New(fiber.Config{ErrorHandler: jsonErrorHandler})

	resp, err := app.Test(httptest.NewRequest(http.MethodGet, "/nope", nil))
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("response body is not JSON: %v", err)
	}
	if body["error"] == "" {
		t.Error("expected a non-empty JSON error body for a 404")
	}
}

// A non-fiber.Error bubbling up (a plain error a handler forgot to wrap)
// still gets a 500 and the JSON shape.
func TestJSONErrorHandlerDefaultsPlainErrorsTo500(t *testing.T) {
	app := fiber.New(fiber.Config{ErrorHandler: jsonErrorHandler})
	app.Get("/oops", func(c *fiber.Ctx) error {
		return errPlain
	})

	resp, err := app.Test(httptest.NewRequest(http.MethodGet, "/oops", nil))
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", resp.StatusCode)
	}
	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("response body is not JSON: %v", err)
	}
	if body["error"] != "something broke" {
		t.Errorf(`body["error"] = %q, want "something broke"`, body["error"])
	}
}

var errPlain = fiberTestError("something broke")

type fiberTestError string

func (e fiberTestError) Error() string { return string(e) }
