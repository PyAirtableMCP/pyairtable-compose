package handlers

import (
	"fmt"
	"net/http"
	
	"github.com/Reg-Kris/pyairtable-api-gateway/internal/config"
	"github.com/gofiber/fiber/v2"
	"go.uber.org/zap"
)

type TenantHandler struct {
	config *config.Config
	proxy  *ProxyHandler
}

func NewTenantHandler(config *config.Config, httpClient *http.Client, logger *zap.Logger) *TenantHandler {
	return &TenantHandler{
		config: config,
		proxy:  NewProxyHandler(httpClient, logger),
	}
}

func (h *TenantHandler) CreateTenant(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/tenants", h.config.TenantServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *TenantHandler) GetTenant(c *fiber.Ctx) error {
	tenantID := c.Params("id")
	targetURL := fmt.Sprintf("%s/tenants/%s", h.config.TenantServiceURL, tenantID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *TenantHandler) UpdateTenant(c *fiber.Ctx) error {
	tenantID := c.Params("id")
	targetURL := fmt.Sprintf("%s/tenants/%s", h.config.TenantServiceURL, tenantID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *TenantHandler) DeleteTenant(c *fiber.Ctx) error {
	tenantID := c.Params("id")
	targetURL := fmt.Sprintf("%s/tenants/%s", h.config.TenantServiceURL, tenantID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *TenantHandler) ListTenants(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/tenants?%s", h.config.TenantServiceURL, c.Request().URI().QueryString())
	return h.proxy.ProxyRequest(c, targetURL)
}