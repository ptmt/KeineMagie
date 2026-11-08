package main

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const appleJWKSURL = "https://appleid.apple.com/auth/keys"

type appleKeys struct {
	mu          sync.Mutex
	client      *http.Client
	keys        map[string]*rsa.PublicKey
	fetched     time.Time
	lastAttempt time.Time
}

func (k *appleKeys) key(ctx context.Context, kid string, now time.Time) (*rsa.PublicKey, error) {
	k.mu.Lock()
	defer k.mu.Unlock()
	if key := k.keys[kid]; key != nil && now.Sub(k.fetched) < time.Hour {
		return key, nil
	}
	// One refresh per minute across all unknown kids, including failed fetches.
	if !k.lastAttempt.IsZero() && now.Sub(k.lastAttempt) < time.Minute {
		return nil, errors.New("key unavailable")
	}
	k.lastAttempt = now
	req, err := http.NewRequestWithContext(ctx, "GET", appleJWKSURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := k.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, errors.New("key unavailable")
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, (1<<20)+1))
	if err != nil || len(b) > 1<<20 {
		return nil, errors.New("invalid keys")
	}
	var doc struct {
		Keys []struct {
			Kty string `json:"kty"`
			Kid string `json:"kid"`
			Use string `json:"use"`
			Alg string `json:"alg"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err = json.Unmarshal(b, &doc); err != nil {
		return nil, err
	}
	keys := map[string]*rsa.PublicKey{}
	for _, j := range doc.Keys {
		if j.Kty != "RSA" || j.Use != "sig" || j.Alg != "RS256" || j.Kid == "" {
			continue
		}
		n, e1 := base64.RawURLEncoding.DecodeString(j.N)
		e, e2 := base64.RawURLEncoding.DecodeString(j.E)
		if e1 != nil || e2 != nil || len(e) == 0 || len(e) > 4 {
			continue
		}
		exp := new(big.Int).SetBytes(e).Int64()
		mod := new(big.Int).SetBytes(n)
		if mod.BitLen() < 2048 || exp < 3 || exp%2 == 0 {
			continue
		}
		keys[j.Kid] = &rsa.PublicKey{N: mod, E: int(exp)}
	}
	if len(keys) == 0 {
		return nil, errors.New("invalid keys")
	}
	// Publish only a validated replacement; failed attempts must not evict
	// healthy keys or extend their one-hour lifetime.
	k.keys = keys
	k.fetched = now
	if key := keys[kid]; key != nil {
		return key, nil
	}
	return nil, errors.New("key unavailable")
}
func (a *appleAuth) verify(ctx context.Context, raw string, c appleChallenge) (string, error) {
	claims := jwt.MapClaims{}
	_, err := jwt.ParseWithClaims(raw, claims, func(token *jwt.Token) (any, error) {
		kid, ok := token.Header["kid"].(string)
		if !ok || kid == "" || len(kid) > 256 {
			return nil, errors.New("invalid key")
		}
		return a.keys.key(ctx, kid, a.now())
	}, jwt.WithValidMethods([]string{"RS256"}), jwt.WithIssuer("https://appleid.apple.com"), jwt.WithAudience(a.clientID), jwt.WithExpirationRequired(), jwt.WithIssuedAt(), jwt.WithTimeFunc(a.now))
	if err != nil {
		return "", err
	}
	aud, err := claims.GetAudience()
	if err != nil || len(aud) != 1 || aud[0] != a.clientID {
		return "", errors.New("invalid audience")
	}
	iat, err := claims.GetIssuedAt()
	if err != nil || iat == nil {
		return "", errors.New("invalid issued time")
	}
	sub, err := claims.GetSubject()
	if err != nil || strings.TrimSpace(sub) == "" || len(sub) > 1024 {
		return "", errors.New("invalid subject")
	}
	nonce, ok := claims["nonce"].(string)
	if !ok || !constantAuthEqual(nonce, c.Nonce) {
		return "", errors.New("invalid nonce")
	}
	return sub, nil
}
