// Package jakehillion implements a DNS record management client for the
// custom ACME DNS-01 challenge API.
package jakehillion

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/libdns/libdns"
)

// Provider facilitates DNS record manipulation with the jakehillion ACME API.
type Provider struct {
	// APIEndpoint is the URL of the ACME DNS API server.
	APIEndpoint string `json:"api_endpoint,omitempty"`

	client *http.Client
	mu     sync.Mutex
}

// GetRecords lists all the records in the zone (not implemented).
func (p *Provider) GetRecords(ctx context.Context, zone string) ([]libdns.Record, error) {
	return nil, fmt.Errorf("GetRecords not implemented")
}

// AppendRecords adds records to the zone. It returns the records that were added.
func (p *Provider) AppendRecords(ctx context.Context, zone string, records []libdns.Record) ([]libdns.Record, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.client == nil {
		p.client = &http.Client{Timeout: 30 * time.Second}
	}

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
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.client == nil {
		p.client = &http.Client{Timeout: 30 * time.Second}
	}

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

type apiRequest struct {
	FQDN  string `json:"fqdn"`
	Value string `json:"value"`
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

	reqBody := apiRequest{
		FQDN:  fqdn,
		Value: value,
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

// Interface guards
var (
	_ libdns.RecordGetter   = (*Provider)(nil)
	_ libdns.RecordAppender = (*Provider)(nil)
	_ libdns.RecordSetter   = (*Provider)(nil)
	_ libdns.RecordDeleter  = (*Provider)(nil)
)
