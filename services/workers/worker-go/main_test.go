package main

import "testing"

func TestRequiredString(t *testing.T) {
	tests := []struct {
		name    string
		data    map[string]interface{}
		want    string
		wantErr bool
	}{
		{name: "string", data: map[string]interface{}{"ad_id": "42"}, want: "42"},
		{name: "number", data: map[string]interface{}{"ad_id": float64(42)}, want: "42"},
		{name: "missing", data: map[string]interface{}{}, wantErr: true},
		{name: "wrong type", data: map[string]interface{}{"ad_id": true}, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := requiredString(tt.data, "ad_id")
			if (err != nil) != tt.wantErr {
				t.Fatalf("requiredString() error = %v, wantErr %v", err, tt.wantErr)
			}
			if got != tt.want {
				t.Fatalf("requiredString() = %q, want %q", got, tt.want)
			}
		})
	}
}
