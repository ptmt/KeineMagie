package main

import (
	"bytes"
	"encoding/json"
	"io"
	"reflect"
	"strings"
)

// An older writer must reject unfamiliar schema rather than silently discard
// billing proof. Known legacy entries retain their original typed encoding,
// including the canonical encoding covered by operator recovery digests.
func (v *dictationMonthlyEntry) UnmarshalJSON(b []byte) error {
	type plain dictationMonthlyEntry
	var p plain
	if err := dictationStrictJSON(b, &p); err != nil {
		return err
	}
	*v = dictationMonthlyEntry(p)
	return nil
}
func (v *dictationMonthlyLedger) UnmarshalJSON(b []byte) error {
	type plain dictationMonthlyLedger
	var p plain
	if err := dictationStrictJSON(b, &p); err != nil {
		return err
	}
	if p.Entries == nil {
		return errDictationBudget
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(b, &raw); err != nil {
		return err
	}
	if policy, ok := raw["attempt_policy"]; ok && string(policy) != "1" {
		return errDictationBudget
	}
	*v = dictationMonthlyLedger(p)
	return nil
}
func dictationStrictJSON(b []byte, v any) error {
	// encoding/json accepts case aliases and duplicate keys, and a nested
	// UnmarshalJSON (notably provider-wire usage) can bypass DisallowUnknownFields.
	// Inspect the entire persisted schema first, without invoking custom decoders.
	shape := json.NewDecoder(bytes.NewReader(b))
	if err := dictationCanonicalJSON(shape, reflect.TypeOf(v)); err != nil {
		return err
	}
	if _, err := shape.Token(); err != io.EOF {
		return errDictationBudget
	}
	d := json.NewDecoder(bytes.NewReader(b))
	d.DisallowUnknownFields()
	return d.Decode(v)
}

func dictationCanonicalJSON(d *json.Decoder, typ reflect.Type) error {
	for typ.Kind() == reflect.Pointer {
		typ = typ.Elem()
	}
	token, err := d.Token()
	if err != nil {
		return err
	}
	if token == nil {
		return nil // Required values and ledger shapes are checked by accounting.
	}
	switch token {
	case json.Delim('{'):
		if typ.Kind() != reflect.Struct {
			return errDictationBudget
		}
		fields := map[string]reflect.Type{}
		for i := 0; i < typ.NumField(); i++ {
			f := typ.Field(i)
			name := strings.Split(f.Tag.Get("json"), ",")[0]
			if f.IsExported() && name != "" && name != "-" {
				fields[name] = f.Type
			}
		}
		seen := map[string]bool{}
		for d.More() {
			key, err := d.Token()
			if err != nil {
				return err
			}
			name, ok := key.(string)
			field, known := fields[name]
			if !ok || !known || seen[name] {
				return errDictationBudget
			}
			seen[name] = true
			if err := dictationCanonicalJSON(d, field); err != nil {
				return err
			}
		}
		_, err = d.Token()
		return err
	case json.Delim('['):
		if typ.Kind() != reflect.Slice {
			return errDictationBudget
		}
		for d.More() {
			if err := dictationCanonicalJSON(d, typ.Elem()); err != nil {
				return err
			}
		}
		_, err = d.Token()
		return err
	default:
		if typ.Kind() == reflect.Struct || typ.Kind() == reflect.Slice {
			return errDictationBudget
		}
		return nil // The typed decoder validates scalar types and ranges.
	}
}
