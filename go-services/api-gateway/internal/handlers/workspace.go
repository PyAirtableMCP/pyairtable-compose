package handlers

import (
	"fmt"
	"net/http"
	
	"github.com/Reg-Kris/pyairtable-api-gateway/internal/config"
	"github.com/gofiber/fiber/v2"
	"go.uber.org/zap"
)

type WorkspaceHandler struct {
	config *config.Config
	proxy  *ProxyHandler
}

func NewWorkspaceHandler(config *config.Config, httpClient *http.Client, logger *zap.Logger) *WorkspaceHandler {
	return &WorkspaceHandler{
		config: config,
		proxy:  NewProxyHandler(httpClient, logger),
	}
}

func (h *WorkspaceHandler) CreateWorkspace(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/workspaces", h.config.WorkspaceServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *WorkspaceHandler) GetWorkspace(c *fiber.Ctx) error {
	workspaceID := c.Params("id")
	targetURL := fmt.Sprintf("%s/workspaces/%s", h.config.WorkspaceServiceURL, workspaceID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *WorkspaceHandler) UpdateWorkspace(c *fiber.Ctx) error {
	workspaceID := c.Params("id")
	targetURL := fmt.Sprintf("%s/workspaces/%s", h.config.WorkspaceServiceURL, workspaceID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *WorkspaceHandler) DeleteWorkspace(c *fiber.Ctx) error {
	workspaceID := c.Params("id")
	targetURL := fmt.Sprintf("%s/workspaces/%s", h.config.WorkspaceServiceURL, workspaceID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *WorkspaceHandler) ListWorkspaces(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/workspaces?%s", h.config.WorkspaceServiceURL, c.Request().URI().QueryString())
	return h.proxy.ProxyRequest(c, targetURL)
}