package handlers

import "testing"

func TestSetOrderRequestStatusRequestValidation(t *testing.T) {
	cases := []struct {
		name    string
		req     setOrderRequestStatusRequest
		wantErr bool
	}{
		{
			name: "confirming needs no decline fields",
			req:  setOrderRequestStatusRequest{Status: "confirmed"},
		},
		{
			name:    "an unrecognized status is rejected",
			req:     setOrderRequestStatusRequest{Status: "cancelled"},
			wantErr: true,
		},
		{
			name:    "declining with no category is rejected",
			req:     setOrderRequestStatusRequest{Status: "declined"},
			wantErr: true,
		},
		{
			name:    "declining with an unrecognized category is rejected",
			req:     setOrderRequestStatusRequest{Status: "declined", DeclineReasonCategory: "too_far"},
			wantErr: true,
		},
		{
			name: "a canned category needs no free-text note",
			req:  setOrderRequestStatusRequest{Status: "declined", DeclineReasonCategory: "out_of_stock"},
		},
		{
			name: "a canned category is still valid with an optional note on top",
			req: setOrderRequestStatusRequest{
				Status:                "declined",
				DeclineReasonCategory: "out_of_stock",
				DeclineReason:         "restocking Thursday",
			},
		},
		{
			name:    "other with no note is rejected — nothing canned to fall back on",
			req:     setOrderRequestStatusRequest{Status: "declined", DeclineReasonCategory: "other"},
			wantErr: true,
		},
		{
			name: "other with a note is valid",
			req: setOrderRequestStatusRequest{
				Status:                "declined",
				DeclineReasonCategory: "other",
				DeclineReason:         "customer asked for an item we no longer carry",
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.req.validate()
			if tc.wantErr && err == nil {
				t.Fatal("expected an error, got nil")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestValidDeclineReasonsMatchesTheSixCategories(t *testing.T) {
	want := []string{
		"out_of_stock", "cant_deliver_there", "not_taking_orders",
		"duplicate", "suspected_spam", "other",
	}
	if len(validDeclineReasons) != len(want) {
		t.Fatalf("validDeclineReasons has %d entries, want %d", len(validDeclineReasons), len(want))
	}
	for _, key := range want {
		if !validDeclineReasons[key] {
			t.Errorf("validDeclineReasons is missing %q", key)
		}
	}
}
