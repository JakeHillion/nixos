// Package jakehillion implements a DNS record management client for the
// custom ACME DNS-01 challenge API.
package jakehillion

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/libdns/libdns"
)

// Provider facilitates DNS record manipulation with the jakehillion ACME API.
type Provider struct {
	// APIEndpoint is the URL of the ACME DNS API server.
	APIEndpoint string `json:"api_endpoint,omitempty"`

	// KeyPath is the directory where keys are stored (default: /run/caddy-nebula-acme)
	KeyPath string `json:"key_path,omitempty"`

	client      *http.Client
	privateKey  ed25519.PrivateKey
	publicKey   ed25519.PublicKey
	mu          sync.Mutex
	initialized bool
}

// GetRecords lists all the records in the zone (not implemented).
func (p *Provider) GetRecords(ctx context.Context, zone string) ([]libdns.Record, error) {
	return nil, fmt.Errorf("GetRecords not implemented")
}

// AppendRecords adds records to the zone. It returns the records that were added.
func (p *Provider) AppendRecords(ctx context.Context, zone string, records []libdns.Record) ([]libdns.Record, error) {
	if err := p.ensureInitialized(); err != nil {
		return nil, fmt.Errorf("initialization failed: %w", err)
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	var appended []libdns.Record
	for _, record := range records {
		rr := record.RR()
		if rr.Type != "TXT" {
			continue
		}

		fqdn := libdns.AbsoluteName(rr.Name, zone)
		if err := p.present(ctx, fqdn, rr.Data); err != nil {
			return appended, err
		}
		appended = append(appended, record)
	}

	return appended, nil
}

// SetRecords sets the records in the zone (not implemented for this use case).
func (p *Provider) SetRecords(ctx context.Context, zone string, records []libdns.Record) ([]libdns.Record, error) {
	return nil, fmt.Errorf("SetRecords not implemented")
}

// DeleteRecords deletes the records from the zone.
func (p *Provider) DeleteRecords(ctx context.Context, zone string, records []libdns.Record) ([]libdns.Record, error) {
	if err := p.ensureInitialized(); err != nil {
		return nil, fmt.Errorf("initialization failed: %w", err)
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	var deleted []libdns.Record
	for _, record := range records {
		rr := record.RR()
		if rr.Type != "TXT" {
			continue
		}

		fqdn := libdns.AbsoluteName(rr.Name, zone)
		if err := p.cleanup(ctx, fqdn, rr.Data); err != nil {
			return deleted, err
		}
		deleted = append(deleted, record)
	}

	return deleted, nil
}

// ensureInitialized loads keys from disk
func (p *Provider) ensureInitialized() error {
	if p.initialized {
		return nil
	}

	if p.client == nil {
		p.client = &http.Client{Timeout: 30 * time.Second}
	}

	if p.KeyPath == "" {
		p.KeyPath = "/run/caddy-nebula-acme"
	}

	// Load existing keys (should exist via ExecStartPre)
	if err := p.loadKeys(); err != nil {
		return fmt.Errorf("failed to load keys: %w", err)
	}

	p.initialized = true
	return nil
}

// loadKeys attempts to load existing keys from disk
func (p *Provider) loadKeys() error {
	privateKeyPath := filepath.Join(p.KeyPath, "private.key")
	publicKeyPath := filepath.Join(p.KeyPath, "public.key")

	privateKeyData, err := os.ReadFile(privateKeyPath)
	if err != nil {
		return fmt.Errorf("failed to read private key: %w", err)
	}

	publicKeyData, err := os.ReadFile(publicKeyPath)
	if err != nil {
		return fmt.Errorf("failed to read public key: %w", err)
	}

	p.privateKey = ed25519.PrivateKey(privateKeyData)
	p.publicKey = ed25519.PublicKey(publicKeyData)

	return nil
}

type apiRequest struct {
	FQDN      string `json:"fqdn"`
	Value     string `json:"value"`
	Nonce     string `json:"nonce"`
	Signature string `json:"signature"`
}

type nonceResponse struct {
	Nonce string `json:"nonce"`
}

func (p *Provider) present(ctx context.Context, fqdn, value string) error {
	return p.doRequest(ctx, "/present", fqdn, value)
}

func (p *Provider) cleanup(ctx context.Context, fqdn, value string) error {
	return p.doRequest(ctx, "/cleanup", fqdn, value)
}

func (p *Provider) doRequest(ctx context.Context, endpoint, fqdn, value string) error {
	// Ensure FQDN ends with a dot
	if !strings.HasSuffix(fqdn, ".") {
		fqdn = fqdn + "."
	}

	// Step 1: Get nonce from server
	nonce, err := p.fetchNonce(ctx)
	if err != nil {
		return fmt.Errorf("fetching nonce: %w", err)
	}

	// Step 2: Create signed payload (JSON format)
	payload := map[string]string{
		"fqdn":  fqdn,
		"value": value,
		"nonce": nonce,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshaling payload: %w", err)
	}

	// Step 3: Sign the payload
	signature := ed25519.Sign(p.privateKey, payloadBytes)

	// Step 4: Create request with signature
	reqBody := apiRequest{
		FQDN:      fqdn,
		Value:     value,
		Nonce:     nonce,
		Signature: base64.StdEncoding.EncodeToString(signature),
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("marshaling request: %w", err)
	}

	url := strings.TrimSuffix(p.APIEndpoint, "/") + endpoint
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("creating request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.client.Do(req)
	if err != nil {
		return fmt.Errorf("making request to %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("API request to %s failed with status %d: %s", endpoint, resp.StatusCode, string(respBody))
	}

	return nil
}

func (p *Provider) fetchNonce(ctx context.Context) (string, error) {
	url := strings.TrimSuffix(p.APIEndpoint, "/") + "/nonce"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, nil)
	if err != nil {
		return "", fmt.Errorf("creating nonce request: %w", err)
	}

	resp, err := p.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("fetching nonce: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("nonce request failed with status %d: %s", resp.StatusCode, string(body))
	}

	var nonceResp nonceResponse
	if err := json.NewDecoder(resp.Body).Decode(&nonceResp); err != nil {
		return "", fmt.Errorf("decoding nonce response: %w", err)
	}

	return nonceResp.Nonce, nil
}

// Interface guards
var (
	_ libdns.RecordGetter   = (*Provider)(nil)
	_ libdns.RecordAppender = (*Provider)(nil)
	_ libdns.RecordSetter   = (*Provider)(nil)
	_ libdns.RecordDeleter  = (*Provider)(nil)
)
