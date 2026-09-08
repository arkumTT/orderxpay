package handlers

import (
	"testing"

	"github.com/orderxpay/api/internal/hubtel"
)

func TestHubtelChannelForNetwork(t *testing.T) {
	cases := map[string]string{
		"mtn":        hubtel.ChannelMTN,
		"telecel":    hubtel.ChannelTelecel,
		"airteltigo": hubtel.ChannelAirtelTigo,
	}
	for network, want := range cases {
		got, err := hubtelChannelForNetwork(network)
		if err != nil {
			t.Fatalf("%s: unexpected error: %v", network, err)
		}
		if got != want {
			t.Errorf("%s: got %q, want %q", network, got, want)
		}
	}

	for _, bad := range []string{"", "vodafone", "MTN", "airtel", "tigo"} {
		if _, err := hubtelChannelForNetwork(bad); err == nil {
			t.Errorf("%q should be rejected — it must be one of the three recognized network keys, lowercase", bad)
		}
	}
}
