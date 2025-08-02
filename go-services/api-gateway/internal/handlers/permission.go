package handlers

import (
	"fmt"
	"net/http"
	
	"github.com/Reg-Kris/pyairtable-api-gateway/internal/config"
	"github.com/gofiber/fiber/v2"
	"go.uber.org/zap"
)

type PermissionHandler struct {
	config *config.Config
	proxy  *ProxyHandler
}

func NewPermissionHandler(config *config.Config, httpClient *http.Client, logger *zap.Logger) *PermissionHandler {
	return &PermissionHandler{
		config: config,
		proxy:  NewProxyHandler(httpClient, logger),
	}
}

func (h *PermissionHandler) CheckPermissions(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/permissions/check?%s", h.config.PermissionServiceURL, c.Request().URI().QueryString())
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *PermissionHandler) GrantPermission(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/permissions/grant", h.config.PermissionServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *PermissionHandler) RevokePermission(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/permissions/revoke", h.config.PermissionServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *PermissionHandler) GetUserPermissions(c *fiber.Ctx) error {
	userID := c.Params("userId")
	targetURL := fmt.Sprintf("%s/permissions/user/%s", h.config.PermissionServiceURL, userID)
	return h.proxy.ProxyRequest(c, targetURL)
}