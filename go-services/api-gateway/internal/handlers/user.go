package handlers

import (
	"fmt"
	"net/http"
	
	"github.com/Reg-Kris/pyairtable-api-gateway/internal/config"
	"github.com/gofiber/fiber/v2"
	"go.uber.org/zap"
)

type UserHandler struct {
	config *config.Config
	proxy  *ProxyHandler
}

func NewUserHandler(config *config.Config, httpClient *http.Client, logger *zap.Logger) *UserHandler {
	return &UserHandler{
		config: config,
		proxy:  NewProxyHandler(httpClient, logger),
	}
}

func (h *UserHandler) GetCurrentUser(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/users/me", h.config.UserServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *UserHandler) UpdateCurrentUser(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/users/me", h.config.UserServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *UserHandler) GetUser(c *fiber.Ctx) error {
	userID := c.Params("id")
	targetURL := fmt.Sprintf("%s/users/%s", h.config.UserServiceURL, userID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *UserHandler) UpdateUser(c *fiber.Ctx) error {
	userID := c.Params("id")
	targetURL := fmt.Sprintf("%s/users/%s", h.config.UserServiceURL, userID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *UserHandler) DeleteUser(c *fiber.Ctx) error {
	userID := c.Params("id")
	targetURL := fmt.Sprintf("%s/users/%s", h.config.UserServiceURL, userID)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *UserHandler) ListUsers(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/users?%s", h.config.UserServiceURL, c.Request().URI().QueryString())
	return h.proxy.ProxyRequest(c, targetURL)
}