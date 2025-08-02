package handlers

import (
	"fmt"
	"net/http"
	
	"github.com/Reg-Kris/pyairtable-api-gateway/internal/config"
	"github.com/gofiber/fiber/v2"
	"go.uber.org/zap"
)

type AirtableHandler struct {
	config *config.Config
	proxy  *ProxyHandler
}

func NewAirtableHandler(config *config.Config, httpClient *http.Client, logger *zap.Logger) *AirtableHandler {
	return &AirtableHandler{
		config: config,
		proxy:  NewProxyHandler(httpClient, logger),
	}
}

func (h *AirtableHandler) ListBases(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/bases", h.config.AirtableGatewayURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AirtableHandler) GetBase(c *fiber.Ctx) error {
	baseID := c.Params("baseId")
	targetURL := fmt.Sprintf("%s/bases/%s", h.config.AirtableGatewayURL, baseID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AirtableHandler) ListTables(c *fiber.Ctx) error {
	baseID := c.Params("baseId")
	targetURL := fmt.Sprintf("%s/bases/%s/tables", h.config.AirtableGatewayURL, baseID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AirtableHandler) GetTable(c *fiber.Ctx) error {
	baseID := c.Params("baseId")
	tableID := c.Params("tableId")
	targetURL := fmt.Sprintf("%s/bases/%s/tables/%s", h.config.AirtableGatewayURL, baseID, tableID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AirtableHandler) ListRecords(c *fiber.Ctx) error {
	baseID := c.Params("baseId")
	tableID := c.Params("tableId")
	targetURL := fmt.Sprintf("%s/bases/%s/tables/%s/records?%s", 
		h.config.AirtableGatewayURL, baseID, tableID, c.Request().URI().QueryString())
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AirtableHandler) CreateRecord(c *fiber.Ctx) error {
	baseID := c.Params("baseId")
	tableID := c.Params("tableId")
	targetURL := fmt.Sprintf("%s/bases/%s/tables/%s/records", 
		h.config.AirtableGatewayURL, baseID, tableID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AirtableHandler) GetRecord(c *fiber.Ctx) error {
	baseID := c.Params("baseId")
	tableID := c.Params("tableId")
	recordID := c.Params("recordId")
	targetURL := fmt.Sprintf("%s/bases/%s/tables/%s/records/%s", 
		h.config.AirtableGatewayURL, baseID, tableID, recordID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AirtableHandler) UpdateRecord(c *fiber.Ctx) error {
	baseID := c.Params("baseId")
	tableID := c.Params("tableId")
	recordID := c.Params("recordId")
	targetURL := fmt.Sprintf("%s/bases/%s/tables/%s/records/%s", 
		h.config.AirtableGatewayURL, baseID, tableID, recordID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AirtableHandler) DeleteRecord(c *fiber.Ctx) error {
	baseID := c.Params("baseId")
	tableID := c.Params("tableId")
	recordID := c.Params("recordId")
	targetURL := fmt.Sprintf("%s/bases/%s/tables/%s/records/%s", 
		h.config.AirtableGatewayURL, baseID, tableID, recordID)
	return h.proxy.ProxyRequest(c, targetURL)
}