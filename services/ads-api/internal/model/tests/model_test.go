package model_test

import (
	"encoding/json"
	"reflect"
	"testing"

	"ads-api/internal/model"
)

func TestJSONRoundTrip(t *testing.T) {
	cases := []struct {
		name string
		val  interface{}
	}{
		{"Ad", model.Ad{ID: 1, CampaignID: 2, Title: "title", Status: "active"}},
		{"Campaign", model.Campaign{ID: 10, UserID: 5, Name: "camp", Status: "paused"}},
		{"Creative", model.Creative{ID: 7, AdID: 1, Content: "creative content"}},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			b, err := json.Marshal(c.val)
			if err != nil {
				t.Fatalf("marshal %s: %v", c.name, err)
			}

			ptr := reflect.New(reflect.TypeOf(c.val))
			if err := json.Unmarshal(b, ptr.Interface()); err != nil {
				t.Fatalf("unmarshal %s: %v", c.name, err)
			}

			got := reflect.Indirect(ptr).Interface()
			if !reflect.DeepEqual(got, c.val) {
				t.Fatalf("%s round-trip mismatch: got=%#v want=%#v", c.name, got, c.val)
			}
		})
	}
}

func TestDBAndJSONTagsPresent(t *testing.T) {
	types := []struct {
		name string
		typ  reflect.Type
	}{
		{"Ad", reflect.TypeOf(model.Ad{})},
		{"Campaign", reflect.TypeOf(model.Campaign{})},
		{"Creative", reflect.TypeOf(model.Creative{})},
	}

	for _, tt := range types {
		t.Run(tt.name, func(t *testing.T) {
			for i := 0; i < tt.typ.NumField(); i++ {
				f := tt.typ.Field(i)
				dbTag := f.Tag.Get("db")
				jsonTag := f.Tag.Get("json")
				if dbTag == "" {
					t.Fatalf("%s.%s missing db tag", tt.name, f.Name)
				}
				if jsonTag == "" {
					t.Fatalf("%s.%s missing json tag", tt.name, f.Name)
				}
			}
		})
	}
}
